import AppKit
import RecordingKit
import TourKit

/// The floating pill shown for the whole recording session (countdown included).
/// Expanded (default):
///   ● 1:23 │ Mic · System audio · Camera │ Switch Window… │ ↺ 🗑 ⏸ ■  ›
/// Collapsed (chevron): ● 1:23 ⏸ ■ ‹ — the pre-v3 compact pill.
/// Paused, the timer column reads "Paused" over the dimmed time. Hovering any control
/// shows what it does in a small bubble above the pill (below it at the top of the
/// screen) — at once, unlike a tooltip. The bubble is drawn in the pill's own window,
/// so it's left out of the recording along with the pill.
/// Draggable; the collapsed state and position persist in UserDefaults
/// (`recordingPillCollapsed`, `recordingPillAnchor` — the capsule's bottom-right corner,
/// so the chevron stays under the pointer when it resizes). Restart/Discard confirm
/// inline (the button turns into "Restart?"/"Discard?" for 3 s, filling the space of
/// both buttons so the pill keeps its size) — the panel never activates, so nothing
/// steals focus from the app being recorded. Whether it shows up in the video is
/// decided by RecordingCoordinator's content filter — `windowID` is what the
/// coordinator excludes. Drawn in the shared dark HUD look (`RecordingHUDStyle`).
@MainActor
final class RecordingControlsController {
    /// A recorded source's pill state. Mic/System audio: on = audible, off = muted.
    /// Camera: on = bubble showing. `unavailable` greys the button; the string
    /// is its hint (why).
    enum SourceState: Equatable { case on, off, unavailable(String) }
    enum SwitchKind { case window, area }

    /// Everything the pill shows, rebuilt by RecordingCoordinator on every tick.
    struct Status: Equatable {
        /// RecorderState's string ("1:23" / "Paused · 1:23"); nil before the engine starts.
        var elapsed: String?
        var paused = false
        /// The engine is running (recording or paused) — false during the countdown.
        var running = false
        var mic = SourceState.unavailable("")
        var sound = SourceState.unavailable("")
        var camera = SourceState.off
        /// nil = no switch button (full-screen recordings).
        var switchKind: SwitchKind?
    }

    var onStop: (() -> Void)?
    var onPauseResume: (() -> Void)?
    var onToggleMic: (() -> Void)?
    var onToggleSound: (() -> Void)?
    var onToggleCamera: (() -> Void)?
    var onSwitch: (() -> Void)?
    var onRestart: (() -> Void)?
    var onDiscard: (() -> Void)?

    /// The panel's window-server ID (matches `SCWindow.windowID`), nil when hidden.
    var windowID: CGWindowID? { panel.map { CGWindowID($0.windowNumber) } }

    private enum Metric {
        static let height: CGFloat = 40
        static let inset: CGFloat = 14         // left; right is `chevronInset`
        static let chevronInset: CGFloat = 6
        static let group: CGFloat = 10         // around separators
        static let tight: CGFloat = 2          // between buttons of one group
        static let iconButton: CGFloat = 28
        static let timeWidth: CGFloat = 46     // "88:88" without jitter as digits change
        static let hintHeight: CGFloat = 24
        static let hintGap: CGFloat = 6
        static let hintPadding: CGFloat = 10
        static let hintMargin: CGFloat = 8     // from the screen edges
    }
    private enum Key {
        static let collapsed = "recordingPillCollapsed"
        static let anchor = "recordingPillAnchor"
    }
    private static let confirmSeconds: TimeInterval = 3

    private var panel: NSPanel?
    private var capsule: NSVisualEffectView?
    private var hintBubble: NSVisualEffectView?
    private var hintLabel: NSTextField?
    private var stack: NSStackView?
    private var dot: NSView?
    private var pausedLabel: NSTextField?
    private var timeLabel: NSTextField?
    private var micButton: PillButton?
    private var soundButton: PillButton?
    private var cameraButton: PillButton?
    private var switchButton: PillButton?
    private var restartButton: PillButton?
    private var discardButton: PillButton?
    private var pauseButton: PillButton?
    private var stopButton: PillButton?
    private var chevron: PillButton?
    /// Views only in the expanded pill.
    private var expandedOnly: [NSView] = []
    /// The separator just before the Switch button (hidden with it).
    private var switchSeparator: NSView?
    private var moveObserver: NSObjectProtocol?
    /// Width of the Restart and Discard icon buttons — together they hold either confirm label.
    private var confirmPairWidth = Metric.iconButton

    /// The capsule's frame on screen. The window is this, plus the hint bubble while shown.
    private var pillFrame = NSRect.zero
    private var hovered: PillButton?
    /// Set while we move/resize the window ourselves (not a user drag).
    private var laying = false

    private var status = Status()
    private var collapsed = UserDefaults.standard.bool(forKey: Key.collapsed)
    private enum Confirm { case restart, discard }
    private var confirming: Confirm?
    private var confirmTimer: Timer?

    func show(on screen: NSScreen) {
        guard panel == nil else { return }
        collapsed = UserDefaults.standard.bool(forKey: Key.collapsed)
        status = Status()

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        Self.pin(dot, width: 10, height: 10)

        let label = NSTextField(labelWithString: "0:00")
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = RecordingHUDStyle.primaryText
        label.alignment = .left
        Self.pin(label, width: Metric.timeWidth)
        // Paused: the word sits over the dimmed time, in the same fixed-width column.
        let paused = NSTextField(labelWithString: "Paused")
        paused.font = .systemFont(ofSize: 10, weight: .semibold)
        paused.textColor = RecordingHUDStyle.primaryText
        paused.isHidden = true
        let timeColumn = NSStackView(views: [paused, label])
        timeColumn.orientation = .vertical
        timeColumn.alignment = .leading
        timeColumn.spacing = 0
        timeColumn.detachesHiddenViews = true
        timeColumn.tourAnchor = "pill.timer"

        let mic = PillButton.labelled(["Mic"], symbols: ["mic.fill", "mic.slash.fill"],
                                      target: self, action: #selector(micTapped))
        let sound = PillButton.labelled(["System audio"], symbols: ["speaker.wave.2.fill", "speaker.slash.fill"],
                                        target: self, action: #selector(soundTapped))
        let camera = PillButton.labelled(["Camera"], symbols: ["video.fill", "video", "video.slash.fill"],
                                         target: self, action: #selector(cameraTapped))
        let switchButton = PillButton.labelled(["Switch Window…", "Switch Area…"],
                                               symbols: ["macwindow", "rectangle.dashed"],
                                               target: self, action: #selector(switchTapped))

        confirmPairWidth = RecordingPillLayout.confirmPairButtonWidth(
            confirmWidths: ["Restart?", "Discard?"].map(PillButton.confirmWidth(for:)),
            spacing: Metric.tight, minimum: Metric.iconButton)
        let restart = PillButton.icon("arrow.counterclockwise", target: self, action: #selector(restartTapped),
                                      width: confirmPairWidth)
        let discard = PillButton.icon("trash", target: self, action: #selector(discardTapped),
                                      width: confirmPairWidth)
        let pause = PillButton.icon("pause.fill", target: self, action: #selector(pauseTapped))
        let stop = PillButton.icon("stop.fill", target: self, action: #selector(stopTapped))
        stop.tint = .systemRed
        let chevron = PillButton.icon("chevron.right", target: self, action: #selector(chevronTapped),
                                      width: 20, pointSize: 11)
        chevron.tint = NSColor.white.withAlphaComponent(0.55)
        for b in [mic, sound, camera, switchButton, restart, discard, pause, stop, chevron] {
            b.onHover = { [weak self] button, inside in self?.hoverChanged(button, inside) }
        }
        // Tour anchors (the recording pill tour, spec §14.3). The mic's and camera's are set in render():
        // only while that control can be used (a mic track to mute, a camera to show).
        sound.tourAnchor = "pill.systemAudio"
        switchButton.tourAnchor = "pill.switch"
        restart.tourAnchor = "pill.restart"
        discard.tourAnchor = "pill.discard"
        pause.tourAnchor = "pill.pause"
        stop.tourAnchor = "pill.stop"
        chevron.tourAnchor = "pill.collapse"

        let sep1 = Self.separator(), sep2 = Self.separator(), sep3 = Self.separator()
        let views: [NSView] = [dot, timeColumn, sep1, mic, sound, camera, sep2, switchButton, sep3,
                               restart, discard, pause, stop, chevron]
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Metric.tight
        stack.detachesHiddenViews = true
        stack.setCustomSpacing(8, after: dot)
        for v in [timeColumn, sep1, camera, sep2, switchButton, sep3] {
            stack.setCustomSpacing(Metric.group, after: v)
        }
        stack.setCustomSpacing(6, after: stop)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let capsule = RecordingHUDStyle.makeBackground(cornerRadius: Metric.height / 2)
        capsule.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: Metric.inset),
            stack.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
        ])
        // The capsule is sized to the stack (`fittedSize`), not the other way round —
        // a required trailing pin would fight the old frame for a pass on every resize.
        let trailing = stack.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -Metric.chevronInset)
        trailing.priority = .defaultHigh
        trailing.isActive = true

        let bubble = RecordingHUDStyle.makeBackground(cornerRadius: 7)
        let hint = NSTextField(labelWithString: "")
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.textColor = RecordingHUDStyle.primaryText
        hint.lineBreakMode = .byTruncatingTail
        hint.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: Metric.hintPadding),
            hint.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -Metric.hintPadding),
            hint.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
        ])
        bubble.isHidden = true

        // Capsule and bubble are placed by hand (`layoutWindow`); the rest of the
        // window is transparent, and clicks there pass through to what's below.
        let root = NSView()
        root.addSubview(capsule)
        root.addSubview(bubble)

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: Metric.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = root

        self.panel = p
        self.capsule = capsule
        self.hintBubble = bubble
        self.hintLabel = hint
        self.stack = stack
        self.dot = dot
        self.pausedLabel = paused
        self.timeLabel = label
        self.micButton = mic
        self.soundButton = sound
        self.cameraButton = camera
        self.switchButton = switchButton
        self.restartButton = restart
        self.discardButton = discard
        self.pauseButton = pause
        self.stopButton = stop
        self.chevron = chevron
        self.expandedOnly = [sep1, mic, sound, camera, sep2, switchButton, sep3, restart, discard]
        self.switchSeparator = sep2

        render()
        let size = fittedSize
        let anchor = Self.savedAnchor(fitting: size)
            ?? NSPoint(x: screen.visibleFrame.midX + size.width / 2, y: screen.visibleFrame.minY + 20)
        place(size: size, anchor: anchor)
        p.orderFrontRegardless()
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelMoved() }
        }
        TourEvents.surfaceShown(.recordingPill, in: p)
    }

    func hide() {
        endConfirm()
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        panel?.orderOut(nil)
        panel = nil
        capsule = nil; hintBubble = nil; hintLabel = nil; hovered = nil
        stack = nil; dot = nil; pausedLabel = nil; timeLabel = nil
        micButton = nil; soundButton = nil; cameraButton = nil; switchButton = nil
        restartButton = nil; discardButton = nil; pauseButton = nil; stopButton = nil; chevron = nil
        expandedOnly = []; switchSeparator = nil
    }

    func update(_ new: Status) {
        guard new != status else { return }
        let relayout = new.switchKind != status.switchKind || new.running != status.running
        status = new
        if !new.running { endConfirm() }
        render()
        if relayout { resize() }
    }

    // MARK: - Rendering

    private func render() {
        guard panel != nil else { return }
        let s = status
        // nil during the countdown (and a Restart's) — show a fresh 0:00.
        timeLabel?.stringValue = s.elapsed?.replacingOccurrences(of: "Paused · ", with: "") ?? "0:00"
        let live = s.running && !s.paused
        timeLabel?.textColor = live ? RecordingHUDStyle.primaryText : RecordingHUDStyle.secondaryText
        pausedLabel?.isHidden = !(s.running && s.paused)
        dot?.layer?.backgroundColor = (live ? NSColor.systemRed : NSColor.systemGray).cgColor

        render(micButton, s.mic, on: "mic.fill", off: "mic.slash.fill", unavailable: "mic.slash.fill",
               offIsWarning: true,
               tipOn: "Mute microphone — the video keeps a silent gap, stays in sync",
               tipOff: "Unmute microphone")
        // "Mute the mic" (a Try step) only makes sense with a mic track: without one the tour skips it.
        if case .unavailable = s.mic { micButton?.tourAnchor = nil } else { micButton?.tourAnchor = "pill.mic" }
        render(soundButton, s.sound, on: "speaker.wave.2.fill", off: "speaker.slash.fill",
               unavailable: "speaker.slash.fill", offIsWarning: true,
               tipOn: "Mute system audio — the video keeps a silent gap, stays in sync",
               tipOff: "Unmute system audio")
        render(cameraButton, s.camera, on: "video.fill", off: "video", unavailable: "video.slash.fill",
               offIsWarning: false, tipOn: "Hide camera bubble", tipOff: "Show camera bubble")
        // No camera (or no access): a tour never points at the greyed button.
        if case .unavailable = s.camera { cameraButton?.tourAnchor = nil } else { cameraButton?.tourAnchor = "pill.camera" }

        if let b = switchButton {
            let window = s.switchKind != .area
            b.symbol = window ? "macwindow" : "rectangle.dashed"
            b.label = window ? "Switch Window…" : "Switch Area…"
            b.isEnabled = s.running
            b.setTip(!s.running ? "Available once recording starts"
                     : window ? "Record a different window — it's scaled to fit this video's frame"
                              : "Record a different area — it's scaled to fit this video's frame")
        }
        renderConfirmable(restartButton, symbol: "arrow.counterclockwise", confirm: .restart,
                          title: "Restart?", tip: "Restart — delete what's recorded so far and start over",
                          confirmTip: "Click again to restart — what's recorded so far is deleted")
        renderConfirmable(discardButton, symbol: "trash", confirm: .discard,
                          title: "Discard?", tip: "Discard — stop and delete this recording",
                          confirmTip: "Click again to delete this recording")
        pauseButton?.symbol = s.paused ? "play.fill" : "pause.fill"
        pauseButton?.isEnabled = s.running
        pauseButton?.setTip(!s.running ? "Available once recording starts"
                            : s.paused ? "Resume recording" : "Pause recording")
        stopButton?.setTip(s.running ? "Stop recording" : "Cancel recording")
        chevron?.symbol = collapsed ? "chevron.left" : "chevron.right"
        chevron?.setTip(collapsed ? "Show all controls" : "Collapse to timer, Pause and Stop")

        for v in expandedOnly { v.isHidden = collapsed }
        if !collapsed {
            switchButton?.isHidden = s.switchKind == nil
            switchSeparator?.isHidden = s.switchKind == nil
            // A confirming button takes its partner's space too (fixed pill width).
            restartButton?.isHidden = confirming == .discard
            discardButton?.isHidden = confirming == .restart
        }
    }

    private func render(_ b: PillButton?, _ state: SourceState, on: String, off: String, unavailable: String,
                        offIsWarning: Bool, tipOn: String, tipOff: String) {
        guard let b else { return }
        switch state {
        case .on:
            b.symbol = on; b.isEnabled = true; b.tint = .white; b.fill = nil; b.setTip(tipOn)
        case .off where offIsWarning:
            // A muted track is a red chip with a slashed icon (readable on any backdrop).
            b.symbol = off; b.isEnabled = true; b.tint = .white
            b.fill = NSColor.systemRed.withAlphaComponent(0.85)
            b.setTip(tipOff)
        case .off:
            // A hidden camera is simply "not on": outline icon, dimmed — no slash, no chip.
            b.symbol = off; b.isEnabled = true; b.tint = RecordingHUDStyle.secondaryText; b.fill = nil
            b.setTip(tipOff)
        case .unavailable(let why):
            b.symbol = unavailable; b.isEnabled = false; b.tint = .white; b.fill = nil; b.setTip(why)
        }
    }

    private func renderConfirmable(_ b: PillButton?, symbol: String, confirm: Confirm,
                                   title: String, tip: String, confirmTip: String) {
        guard let b else { return }
        b.isEnabled = status.running
        if confirming == confirm {
            b.symbol = nil; b.label = title; b.bold = true; b.fill = .systemRed
            b.fixedWidth = RecordingPillLayout.confirmSlotWidth(buttonWidth: confirmPairWidth, spacing: Metric.tight)
            b.setTip(confirmTip)
        } else {
            b.symbol = symbol; b.label = ""; b.bold = false; b.fill = nil; b.fixedWidth = confirmPairWidth
            b.setTip(status.running ? tip : "Available once recording starts")
        }
    }

    // MARK: - Sizing

    /// Refit the capsule to its content, keeping its bottom-right corner (where the
    /// chevron is) in place, clamped onto the screen.
    private func resize() {
        place(size: fittedSize, anchor: NSPoint(x: pillFrame.maxX, y: pillFrame.minY))
    }

    private var fittedSize: NSSize {
        NSSize(width: (stack?.fittingSize.width ?? 0) + Metric.inset + Metric.chevronInset,
               height: Metric.height)
    }

    private func place(size: NSSize, anchor: NSPoint) {
        guard let panel else { return }
        var frame = NSRect(x: anchor.x - size.width, y: anchor.y, width: size.width, height: size.height)
        if let visible = (NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) }
                          ?? panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - frame.width - 8)
            frame.origin.y = min(max(frame.minY, visible.minY + 8), visible.maxY - frame.height - 8)
        }
        pillFrame = frame
        layoutWindow()
    }

    /// Sizes the window to the capsule plus, while a control is hovered, its hint bubble.
    private func layoutWindow() {
        guard let panel, let capsule, let bubble = hintBubble, let hint = hintLabel else { return }
        var bubbleFrame: NSRect?
        if let b = hovered, !b.isHidden, !b.hint.isEmpty {
            capsule.frame.size = pillFrame.size
            capsule.layoutSubtreeIfNeeded()
            hint.stringValue = b.hint
            let size = CGSize(width: ceil(hint.attributedStringValue.size().width) + 2 * Metric.hintPadding,
                              height: Metric.hintHeight)
            let visible = (NSScreen.screens.first { $0.frame.intersects(pillFrame) } ?? NSScreen.main)?
                .visibleFrame ?? pillFrame
            bubbleFrame = RecordingPillLayout.hintFrame(
                size: size, anchorX: pillFrame.minX + b.convert(b.bounds, to: capsule).midX,
                pill: pillFrame, visible: visible, gap: Metric.hintGap, margin: Metric.hintMargin)
        }
        let frame = bubbleFrame.map { pillFrame.union($0) } ?? pillFrame
        laying = true
        panel.setFrame(frame, display: false)
        laying = false
        capsule.frame = pillFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        if let bubbleFrame { bubble.frame = bubbleFrame.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        bubble.isHidden = bubbleFrame == nil
        panel.contentView?.needsDisplay = true
        panel.invalidateShadow()
    }

    /// A user drag: remember where the capsule's bottom-right corner ended up.
    private func panelMoved() {
        guard !laying, let panel, let capsule else { return }
        pillFrame.origin = NSPoint(x: panel.frame.minX + capsule.frame.minX,
                                   y: panel.frame.minY + capsule.frame.minY)
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: pillFrame.maxX, y: pillFrame.minY)),
                                  forKey: Key.anchor)
    }

    /// The remembered bottom-right corner, if the pill would still be on a screen there.
    private static func savedAnchor(fitting size: NSSize) -> NSPoint? {
        guard let raw = UserDefaults.standard.string(forKey: Key.anchor) else { return nil }
        let anchor = NSPointFromString(raw)
        let probe = NSPoint(x: anchor.x - min(size.width, 40), y: anchor.y + size.height / 2)
        return NSScreen.screens.contains { $0.visibleFrame.contains(probe) } ? anchor : nil
    }

    // MARK: - Hover hint

    private func hoverChanged(_ b: PillButton, _ inside: Bool) {
        if inside { hovered = b } else if hovered === b { hovered = nil } else { return }
        layoutWindow()
    }

    // MARK: - Confirm

    private func beginConfirm(_ c: Confirm) {
        confirming = c
        confirmTimer?.invalidate()
        confirmTimer = Timer.scheduledTimer(withTimeInterval: Self.confirmSeconds, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.endConfirm(); self?.render(); self?.resize() }
        }
        render(); resize()
    }

    private func endConfirm() {
        confirmTimer?.invalidate()
        confirmTimer = nil
        confirming = nil
    }

    // MARK: - Actions

    @objc private func micTapped() {
        if status.mic == .on { TourEvents.post(.action("pill.micMuted")) }
        onToggleMic?()
    }
    @objc private func soundTapped() { onToggleSound?() }
    @objc private func cameraTapped() { onToggleCamera?() }
    @objc private func switchTapped() { cancelConfirm(); onSwitch?() }
    @objc private func pauseTapped() { cancelConfirm(); onPauseResume?() }
    @objc private func stopTapped() { cancelConfirm(); onStop?() }

    @objc private func restartTapped() {
        if confirming == .restart { cancelConfirm(); onRestart?() } else { beginConfirm(.restart) }
    }

    @objc private func discardTapped() {
        if confirming == .discard { cancelConfirm(); onDiscard?() } else { beginConfirm(.discard) }
    }

    @objc private func chevronTapped() {
        cancelConfirm()
        collapsed.toggle()
        UserDefaults.standard.set(collapsed, forKey: Key.collapsed)
        render(); resize()
    }

    /// Drop a pending "Restart?"/"Discard?" (another control was used).
    private func cancelConfirm() {
        guard confirming != nil else { return }
        endConfirm(); render(); resize()
    }

    // MARK: - Pieces

    private static func separator() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        pin(v, width: 1, height: 18)
        return v
    }

    private static func pin(_ v: NSView, width: CGFloat? = nil, height: CGFloat? = nil) {
        v.translatesAutoresizingMaskIntoConstraints = false
        if let width { v.widthAnchor.constraint(equalToConstant: width).isActive = true }
        if let height { v.heightAnchor.constraint(equalToConstant: height).isActive = true }
    }
}

/// A borderless pill control: SF Symbol and/or label, hover highlight, a state
/// fill (muted / confirm — ringed in white so it stands out on red content), a
/// hint shown by the pill's hover bubble, and first-mouse clicks so it works while
/// the panel never becomes key. Every property change funnels through `refresh()`.
private final class PillButton: NSButton {
    var symbol: String? { didSet { if symbol != oldValue { refresh() } } }
    var label = "" { didSet { if label != oldValue { refresh() } } }
    var tint: NSColor = .white { didSet { if tint != oldValue { refresh() } } }
    var fill: NSColor? { didSet { if fill != oldValue { applyBackground() } } }
    var bold = false { didSet { if bold != oldValue { refresh() } } }
    /// nil = natural width plus padding.
    var fixedWidth: CGFloat? { didSet { if fixedWidth != oldValue { refresh() } } }
    override var isEnabled: Bool { didSet { if isEnabled != oldValue { refresh(); applyBackground() } } }
    /// What the control does (or why it's unavailable) — the pill's hover bubble text.
    private(set) var hint = ""
    var onHover: ((PillButton, Bool) -> Void)?

    private var pointSize: CGFloat = 14
    private var widthConstraint: NSLayoutConstraint?
    private var hovering = false
    private static let padding: CGFloat = 8

    static func icon(_ symbol: String, target: AnyObject, action: Selector,
                     width: CGFloat = 28, pointSize: CGFloat = 14) -> PillButton {
        let b = PillButton(target: target, action: action, pointSize: pointSize)
        b.fixedWidth = width
        b.symbol = symbol
        return b
    }

    /// Icon + label; its width is locked to the widest of `symbols` × `labels`
    /// so toggling states never shifts the pill.
    static func labelled(_ labels: [String], symbols: [String], target: AnyObject,
                         action: Selector) -> PillButton {
        let b = PillButton(target: target, action: action, pointSize: 13)
        var widest: CGFloat = 0
        for l in labels { for s in symbols { b.label = l; b.symbol = s; widest = max(widest, b.naturalWidth) } }
        b.label = labels[0]; b.symbol = symbols[0]
        b.fixedWidth = widest
        return b
    }

    /// Natural width of a bold confirm label ("Restart?") with padding.
    static func confirmWidth(for title: String) -> CGFloat {
        let b = PillButton(target: nil, action: nil, pointSize: 14)
        b.label = title
        b.bold = true
        return b.naturalWidth
    }

    private convenience init(target: AnyObject?, action: Selector?, pointSize: CGFloat) {
        self.init(frame: .zero)
        self.target = target
        self.action = action
        self.pointSize = pointSize
        isBordered = false
        bezelStyle = .regularSquare
        imageScaling = .scaleNone
        imageHugsTitle = true
        wantsLayer = true
        layer?.cornerRadius = 7
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true   // spec: controls 24–28 pt
        refresh()
    }

    private var naturalWidth: CGFloat { ceil(intrinsicContentSize.width) + Self.padding * 2 }

    private func refresh() {
        image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        symbolConfiguration = .init(pointSize: pointSize, weight: .semibold)
        imagePosition = symbol == nil ? .noImage : label.isEmpty ? .imageOnly : .imageLeading
        let color = isEnabled ? tint : NSColor.white.withAlphaComponent(0.3)
        contentTintColor = color
        attributedTitle = NSAttributedString(string: label, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 12, weight: bold ? .semibold : .medium)])
        let w = fixedWidth ?? naturalWidth
        if widthConstraint?.constant != w {
            widthConstraint?.isActive = false
            widthConstraint = widthAnchor.constraint(equalToConstant: w)
            widthConstraint?.isActive = true
        }
    }

    /// Sets the hover hint (and the VoiceOver label); a hint shown right now updates in place.
    func setTip(_ tip: String) {
        guard hint != tip else { return }
        hint = tip
        setAccessibilityLabel(tip)
        if hovering { onHover?(self, true) }
    }

    private func applyBackground() {
        let hover = hovering && isEnabled
        let c = fill.map { hover ? $0.blended(withFraction: 0.15, of: .white) ?? $0 : $0 }
            ?? (hover ? NSColor.white.withAlphaComponent(0.12) : .clear)
        layer?.backgroundColor = c.cgColor
        // A thin white ring keeps a red chip distinct over red content.
        layer?.borderWidth = fill == nil ? 0 : 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Frame == constraints: SF Symbols' alignment insets would otherwise grow some
    /// buttons (and their hover/chip background) past 28 pt.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited,
                                                              .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; applyBackground(); onHover?(self, true) }
    override func mouseExited(with event: NSEvent) { hovering = false; applyBackground(); onHover?(self, false) }
}
