import AppKit

/// The floating pill shown for the whole recording session (countdown included).
/// Expanded (default):
///   ● 1:23 │ Mic · Sound · Camera │ Switch window… │ ↺ 🗑 ⏸ ■  ›
/// Collapsed (chevron): ● 1:23 ⏸ ■ ‹ — the pre-v3 compact pill.
/// Draggable; the collapsed state and position persist in UserDefaults
/// (`recordingPillCollapsed`, `recordingPillAnchor` — its bottom-right corner, so
/// the chevron stays under the pointer when it resizes). Restart/Discard confirm
/// inline (the button turns into "Restart?"/"Discard?" for 3 s) — the panel never
/// activates, so nothing steals focus from the app being recorded. Whether it
/// shows up in the video is decided by RecordingCoordinator's content filter —
/// `windowID` is what the coordinator excludes.
@MainActor
final class RecordingControlsController {
    /// A recorded source's pill state. Mic/Sound: on = audible, off = muted.
    /// Camera: on = bubble showing. `unavailable` greys the button; the string
    /// is its tooltip (why).
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
    }
    private enum Key {
        static let collapsed = "recordingPillCollapsed"
        static let anchor = "recordingPillAnchor"
    }
    private static let confirmSeconds: TimeInterval = 3

    private var panel: NSPanel?
    private var stack: NSStackView?
    private var dot: NSView?
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
        label.textColor = .white
        label.alignment = .left
        Self.pin(label, width: 46)             // "88:88" without jitter as digits change

        let mic = PillButton.labelled(["Mic"], symbols: ["mic.fill", "mic.slash.fill"],
                                      target: self, action: #selector(micTapped))
        let sound = PillButton.labelled(["Sound"], symbols: ["speaker.wave.2.fill", "speaker.slash.fill"],
                                        target: self, action: #selector(soundTapped))
        let camera = PillButton.labelled(["Camera"], symbols: ["video.fill", "video.slash.fill"],
                                         target: self, action: #selector(cameraTapped))
        let switchButton = PillButton.labelled(["Switch window…", "Switch area…"],
                                               symbols: ["macwindow", "rectangle.dashed"],
                                               target: self, action: #selector(switchTapped))

        let restart = PillButton.icon("arrow.counterclockwise", target: self, action: #selector(restartTapped))
        let discard = PillButton.icon("trash", target: self, action: #selector(discardTapped))
        let pause = PillButton.icon("pause.fill", target: self, action: #selector(pauseTapped))
        let stop = PillButton.icon("stop.fill", target: self, action: #selector(stopTapped))
        stop.tint = .systemRed
        let chevron = PillButton.icon("chevron.right", target: self, action: #selector(chevronTapped),
                                      width: 20, pointSize: 11)
        chevron.tint = NSColor.white.withAlphaComponent(0.55)

        let sep1 = Self.separator(), sep2 = Self.separator(), sep3 = Self.separator()
        let views: [NSView] = [dot, label, sep1, mic, sound, camera, sep2, switchButton, sep3,
                               restart, discard, pause, stop, chevron]
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Metric.tight
        stack.detachesHiddenViews = true
        stack.setCustomSpacing(8, after: dot)
        for v in [label, sep1, camera, sep2, switchButton, sep3] {
            stack.setCustomSpacing(Metric.group, after: v)
        }
        stack.setCustomSpacing(6, after: stop)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let bg = NSVisualEffectView()
        bg.appearance = NSAppearance(named: .vibrantDark)
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = Metric.height / 2
        bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 1
        bg.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        // A light dark wash keeps white text readable over bright backdrops.
        let wash = NSView()
        wash.wantsLayer = true
        wash.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        wash.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(wash)
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            wash.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            wash.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            wash.topAnchor.constraint(equalTo: bg.topAnchor),
            wash.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: Metric.inset),
            stack.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
        ])
        // The panel is sized to the stack (`fittedSize`), not the other way round —
        // a required trailing pin would fight the old frame for a pass on every resize.
        let trailing = stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -Metric.chevronInset)
        trailing.priority = .defaultHigh
        trailing.isActive = true

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: Metric.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.allowsToolTipsWhenApplicationIsInactive = true   // we never activate
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = bg

        self.panel = p
        self.stack = stack
        self.dot = dot
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
            forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak p] _ in
            guard let p else { return }
            UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: p.frame.maxX, y: p.frame.minY)),
                                      forKey: Key.anchor)
        }
    }

    func hide() {
        endConfirm()
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        panel?.orderOut(nil)
        panel = nil
        stack = nil; dot = nil; timeLabel = nil
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
        timeLabel?.textColor = live ? .white : .secondaryLabelColor
        dot?.layer?.backgroundColor = (live ? NSColor.systemRed : NSColor.systemGray).cgColor

        render(micButton, s.mic, on: "mic.fill", off: "mic.slash.fill", offIsWarning: true,
               tipOn: "Mute microphone — the video keeps a silent gap, stays in sync",
               tipOff: "Unmute microphone")
        render(soundButton, s.sound, on: "speaker.wave.2.fill", off: "speaker.slash.fill", offIsWarning: true,
               tipOn: "Mute system audio — the video keeps a silent gap, stays in sync",
               tipOff: "Unmute system audio")
        render(cameraButton, s.camera, on: "video.fill", off: "video.slash.fill", offIsWarning: false,
               tipOn: "Hide camera bubble", tipOff: "Show camera bubble")

        if let b = switchButton {
            let window = s.switchKind != .area
            b.symbol = window ? "macwindow" : "rectangle.dashed"
            b.label = window ? "Switch window…" : "Switch area…"
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
        pauseButton?.setTip(s.paused ? "Resume recording" : "Pause recording")
        stopButton?.setTip(s.running ? "Stop recording" : "Cancel recording")
        chevron?.symbol = collapsed ? "chevron.left" : "chevron.right"
        chevron?.setTip(collapsed ? "Show all controls" : "Collapse to timer, Pause and Stop")

        for v in expandedOnly { v.isHidden = collapsed }
        if !collapsed {
            switchButton?.isHidden = s.switchKind == nil
            switchSeparator?.isHidden = s.switchKind == nil
        }
    }

    private func render(_ b: PillButton?, _ state: SourceState, on: String, off: String,
                        offIsWarning: Bool, tipOn: String, tipOff: String) {
        guard let b else { return }
        switch state {
        case .on:
            b.symbol = on; b.isEnabled = true; b.tint = .white; b.fill = nil; b.setTip(tipOn)
        case .off:
            // A muted track is a red chip (readable on any backdrop); a hidden
            // camera just shows the slashed icon.
            b.symbol = off; b.isEnabled = true; b.tint = .white
            b.fill = offIsWarning ? NSColor.systemRed.withAlphaComponent(0.85) : nil
            b.setTip(tipOff)
        case .unavailable(let why):
            b.symbol = off; b.isEnabled = false; b.tint = .white; b.fill = nil; b.setTip(why)
        }
    }

    private func renderConfirmable(_ b: PillButton?, symbol: String, confirm: Confirm,
                                   title: String, tip: String, confirmTip: String) {
        guard let b else { return }
        b.isEnabled = status.running
        if confirming == confirm {
            b.symbol = nil; b.label = title; b.bold = true; b.fill = .systemRed; b.fixedWidth = nil
            b.setTip(confirmTip)
        } else {
            b.symbol = symbol; b.label = ""; b.bold = false; b.fill = nil; b.fixedWidth = 28
            b.setTip(status.running ? tip : "Available once recording starts")
        }
    }

    // MARK: - Sizing

    /// Refit the panel to its content, keeping the bottom-right corner (where the
    /// chevron is) in place, clamped onto the screen.
    private func resize() {
        guard let panel else { return }
        place(size: fittedSize, anchor: NSPoint(x: panel.frame.maxX, y: panel.frame.minY))
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
        panel.setFrame(frame, display: true)
    }

    /// The remembered bottom-right corner, if the pill would still be on a screen there.
    private static func savedAnchor(fitting size: NSSize) -> NSPoint? {
        guard let raw = UserDefaults.standard.string(forKey: Key.anchor) else { return nil }
        let anchor = NSPointFromString(raw)
        let probe = NSPoint(x: anchor.x - min(size.width, 40), y: anchor.y + size.height / 2)
        return NSScreen.screens.contains { $0.visibleFrame.contains(probe) } ? anchor : nil
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

    @objc private func micTapped() { onToggleMic?() }
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
/// fill (muted / confirm), and first-mouse clicks so it works while the panel
/// never becomes key. Every property change funnels through `refresh()`.
private final class PillButton: NSButton {
    var symbol: String? { didSet { if symbol != oldValue { refresh() } } }
    var label = "" { didSet { if label != oldValue { refresh() } } }
    var tint: NSColor = .white { didSet { if tint != oldValue { refresh() } } }
    var fill: NSColor? { didSet { if fill != oldValue { applyBackground() } } }
    var bold = false { didSet { if bold != oldValue { refresh() } } }
    /// nil = natural width plus padding.
    var fixedWidth: CGFloat? { didSet { if fixedWidth != oldValue { refresh() } } }
    override var isEnabled: Bool { didSet { if isEnabled != oldValue { refresh(); applyBackground() } } }

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

    private convenience init(target: AnyObject, action: Selector, pointSize: CGFloat) {
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

    func setTip(_ tip: String) {
        if toolTip != tip { toolTip = tip; setAccessibilityLabel(tip) }
    }

    private func applyBackground() {
        let hover = hovering && isEnabled
        let c = fill.map { hover ? $0.blended(withFraction: 0.15, of: .white) ?? $0 : $0 }
            ?? (hover ? NSColor.white.withAlphaComponent(0.12) : .clear)
        layer?.backgroundColor = c.cgColor
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

    override func mouseEntered(with event: NSEvent) { hovering = true; applyBackground() }
    override func mouseExited(with event: NSEvent) { hovering = false; applyBackground() }
}
