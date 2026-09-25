import AppKit
import AVFoundation
import RecordingKit

/// The pre-record strip: target buttons · Format · FPS on top, then one labelled
/// column per source (Microphone · System audio · Camera · Mouse cursor), each a
/// caption over a popup menu, with a live mic level meter beside the Microphone
/// caption, and a hint line at the bottom explaining whatever the pointer is over
/// (the hovered group's caption brightens to match). Every choice persists straight
/// into `SettingsStore.recording` (the same values the Settings window edits).
/// Drawn in the shared dark HUD look (`RecordingHUDStyle`).
/// Lives in App because it bridges RecordingConfig ↔ SettingsStore.
@MainActor
final class RecordStripController: NSObject {
    private var panel: NSPanel?
    private let store: SettingsStore
    private let micCatalog: DeviceCatalog
    private let cameraCatalog: DeviceCatalog

    var onFullScreen: (() -> Void)?
    var onArea: (() -> Void)?
    var onWindow: (() -> Void)?
    var onCancel: (() -> Void)?

    // Rebuilt by every `show()`.
    private var micPopup = RecordStripController.popup()
    private var audioPopup = RecordStripController.popup()
    private var cameraPopup = RecordStripController.popup()
    private var cursorPopup = RecordStripController.popup()
    private var meter = LevelMeterView()
    private var allowMic = NSButton()
    private var hintLabel = NSTextField(labelWithString: Hint.idle)
    /// Views whose hover/focus shows a hint, innermost last (nested areas win).
    private var hintViews: [(view: NSView, hint: Hint)] = []
    /// Captions/icons that brighten while their group's hint is showing.
    private var captions: [Hint: [NSView]] = [:]
    private var hovered: [Hint] = []
    private var focused: Hint?
    private var focusObservation: NSKeyValueObservation?
    private var deviceObservers: [NSObjectProtocol] = []
    private var meterCapturer: MicCapturer?
    private var level = 0.0

    /// Microphone, System audio and Camera share one column width that fits their
    /// usual content untruncated (measured regular popups: "All apps except
    /// BetterScreenshot" 251pt); Mouse cursor only needs "Shown"/"Hidden". Longer
    /// device names truncate and show the full name as a tooltip.
    private static let columnWidth: CGFloat = 252
    private static let cursorWidth: CGFloat = 128
    private static let columnGap: CGFloat = 16
    private static let meterWidth: CGFloat = 120

    init(store: SettingsStore, micCatalog: DeviceCatalog = AudioInputCatalog(),
         cameraCatalog: DeviceCatalog = CameraCatalog()) {
        self.store = store
        self.micCatalog = micCatalog
        self.cameraCatalog = cameraCatalog
        super.init()
    }

    var isVisible: Bool { panel != nil }

    func show(on screen: NSScreen) {
        guard panel == nil else { return }
        (micPopup, audioPopup, cameraPopup, cursorPopup) =
            (Self.popup(), Self.popup(), Self.popup(), Self.popup())
        meter = LevelMeterView()
        allowMic = NSButton()
        hintLabel = NSTextField(labelWithString: Hint.idle)
        hintViews = []
        captions = [:]
        hovered = []
        focused = nil

        let content = NSStackView(views: [topRow(), separator(), sourcesRow(), separator(), hintRow()])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 12, right: 16)
        let width = 3 * Self.columnWidth + Self.cursorWidth + 3 * Self.columnGap
        for row in content.arrangedSubviews {
            row.widthAnchor.constraint(equalToConstant: width).isActive = true
        }

        let bg = RecordingHUDStyle.makeBackground(cornerRadius: 12)
        content.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            content.topAnchor.constraint(equalTo: bg.topAnchor),
            content.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
        ])
        // Borderless so the HUD's own 12pt corners and border show; KeyablePanel keeps
        // it able to take keyboard focus (Tab with Full Keyboard Access) when clicked.
        let p = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.appearance = NSAppearance(named: .darkAqua)
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = bg
        panel = p
        refreshSources()   // fill the menus and show the meter/link before measuring
        let size = content.fittingSize
        p.setContentSize(size)
        p.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                                 y: screen.visibleFrame.minY + 60))

        for (view, hint) in hintViews {
            view.addTrackingArea(NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: ["hint": hint.rawValue]))
        }
        // Keyboard focus (Tab with Full Keyboard Access) explains a control too.
        focusObservation = p.observe(\.firstResponder, options: [.new]) { [weak self] panel, _ in
            MainActor.assumeIsolated { self?.focusChanged(to: panel.firstResponder) }
        }
        // AirPods connecting, a USB mic unplugged… keep the menus current.
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            deviceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.devicesChanged() }
            })
        }

        p.orderFrontRegardless()
    }

    func hide() {
        stopMeter()
        focusObservation = nil
        for observer in deviceObservers { NotificationCenter.default.removeObserver(observer) }
        deviceObservers = []
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Rows

    private func topRow() -> NSView {
        func target(_ title: String, _ symbol: String, _ hint: Hint, _ action: Selector) -> NSButton {
            let b = NSButton(title: title,
                             image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!,
                             target: self, action: action)
            b.imagePosition = .imageLeading
            b.bezelStyle = .rounded
            b.controlSize = .large
            track(b, hint)
            return b
        }
        let full = target("Full Screen", "display", .fullScreen, #selector(fullScreen))
        let area = target("Area…", "rectangle.dashed", .area, #selector(areaSelect))
        let window = target("Window…", "macwindow", .window, #selector(windowSelect))

        let format = ChoiceControl(["MP4", "GIF"], selected: store.recording.format == .mp4 ? 0 : 1,
                                   name: "Format") { [weak self] in self?.formatChanged(to: $0) }
        let fps = ChoiceControl(["30", "60"], selected: store.recording.fps == 60 ? 1 : 0,
                                name: "Frame rate") { [weak self] in self?.fpsChanged(to: $0) }

        let cancel = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill",
                                             accessibilityDescription: "Cancel")!,
                              target: self, action: #selector(cancelTapped))
        cancel.isBordered = false
        cancel.symbolConfiguration = .init(pointSize: 16, weight: .regular)
        cancel.contentTintColor = RecordingHUDStyle.secondaryText
        cancel.toolTip = "Close without recording"
        track(cancel, .cancel, captions: [cancel])

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let formatGroup = labelled("Format", format, .format)
        let fpsGroup = labelled("FPS", fps, .fps)
        let row = NSStackView(views: [full, area, window, spacer, formatGroup, fpsGroup, cancel])
        row.spacing = 8
        row.distribution = .fill
        row.setCustomSpacing(20, after: formatGroup)
        row.setCustomSpacing(16, after: fpsGroup)
        return row
    }

    /// "Caption [control]" as one hover target.
    private func labelled(_ caption: String, _ control: NSView, _ hint: Hint) -> NSView {
        let label = NSTextField(labelWithString: caption)
        label.font = .systemFont(ofSize: 12)
        label.textColor = RecordingHUDStyle.secondaryText
        let group = NSStackView(views: [label, control])
        group.spacing = 6
        track(group, hint, captions: [label])
        return group
    }

    private func sourcesRow() -> NSView {
        for (popup, name) in [(micPopup, "Microphone"), (audioPopup, "System audio"),
                              (cameraPopup, "Camera"), (cursorPopup, "Mouse cursor")] {
            popup.target = self
            popup.setAccessibilityLabel(name)
        }
        micPopup.action = #selector(micChosen(_:))
        audioPopup.action = #selector(audioChosen(_:))
        cameraPopup.action = #selector(cameraChosen(_:))
        cursorPopup.action = #selector(cursorChosen(_:))

        // Beside the Microphone caption: the live level meter, or a link to grant
        // access (neither when the mic is Off — so no empty band under the menus).
        allowMic.isBordered = false
        allowMic.attributedTitle = NSAttributedString(
            string: "Allow microphone access…",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.linkColor])
        allowMic.target = self
        allowMic.action = #selector(allowMicTapped)
        meter.translatesAutoresizingMaskIntoConstraints = false
        allowMic.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            meter.widthAnchor.constraint(equalToConstant: Self.meterWidth),
            meter.heightAnchor.constraint(equalToConstant: 6),
            // No taller than the caption, so the strip is the same height whether the
            // meter, the link or neither is showing.
            allowMic.heightAnchor.constraint(equalToConstant: 15),
            // Its intrinsic width comes out short and the title wraps (clipped) otherwise.
            allowMic.widthAnchor.constraint(equalToConstant: ceil(allowMic.attributedTitle.size().width) + 4),
        ])
        track(allowMic, .allowMic)

        let w = Self.columnWidth
        let row = NSStackView(views: [
            column("mic", "Microphone", micPopup, w, accessories: [meter, allowMic], hint: .microphone),
            column("speaker.wave.2", "System audio", audioPopup, w, hint: .systemAudio),
            column("video", "Camera", cameraPopup, w, hint: .camera),
            column("cursorarrow", "Mouse cursor", cursorPopup, Self.cursorWidth, hint: .cursor),
        ])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = Self.columnGap
        return row
    }

    /// Icon + caption (+ right-aligned `accessories`, e.g. the mic meter) over a popup.
    private func column(_ symbol: String, _ caption: String, _ popup: NSPopUpButton, _ width: CGFloat,
                        accessories: [NSView] = [], hint: Hint) -> NSView {
        popup.widthAnchor.constraint(equalToConstant: width).isActive = true
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        icon.contentTintColor = RecordingHUDStyle.secondaryText
        let label = NSTextField(labelWithString: caption)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = RecordingHUDStyle.secondaryText
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let header = NSStackView(views: [icon, label, spacer] + accessories)
        header.spacing = 5
        header.distribution = .fill
        header.widthAnchor.constraint(equalToConstant: width).isActive = true
        let column = NSStackView(views: [header, popup])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        track(column, hint, captions: [icon, label])
        return column
    }

    private func hintRow() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "info.circle",
                                              accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        icon.contentTintColor = RecordingHUDStyle.secondaryText
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = RecordingHUDStyle.secondaryText
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hintLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [icon, hintLabel])
        row.spacing = 6
        row.distribution = .fill
        return row
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    // MARK: - Source menus

    /// Rebuilds every menu from the saved config + the connected devices.
    private func refreshSources() {
        let config = store.recording
        let isGIF = config.format == .gif

        let mics = micCatalog.snapshot()
        fill(micPopup, mics.options.map { ($0.title, $0.choice.id, nil) },
             selected: mics.choice(enabled: config.microphone, saved: config.microphoneDeviceID).id)
        micPopup.isEnabled = !isGIF

        fill(audioPopup, SystemAudioMode.allCases.map { ($0.title, $0.rawValue, Self.tip(for: $0)) },
             selected: config.systemAudioMode.rawValue)
        audioPopup.isEnabled = !isGIF

        let cameras = cameraCatalog.snapshot()
        fill(cameraPopup, cameras.options.map { ($0.title, $0.choice.id, nil) },
             selected: cameras.choice(enabled: config.camera, saved: config.cameraDeviceID).id)
        let sizes = NSMenu()
        for size in CameraSize.allCases {
            let item = NSMenuItem(title: size == .small ? "Small" : "Medium",
                                  action: #selector(cameraSizeChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            item.state = size == config.cameraSize ? .on : .off
            sizes.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Camera Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizes
        cameraPopup.menu?.addItem(.separator())
        cameraPopup.menu?.addItem(sizeItem)

        fill(cursorPopup, [("Shown", "visible", "The mouse cursor is recorded as it moves."),
                           ("Hidden", "hidden", "The video shows no mouse cursor.")],
             selected: config.showsCursor ? "visible" : "hidden")

        refreshMeter()
        updateHint()
    }

    /// Replaces `popup`'s items (title, id, tooltip) and selects `selected`. Items are
    /// added directly so repeated titles aren't collapsed.
    private func fill(_ popup: NSPopUpButton, _ items: [(String, String, String?)], selected: String) {
        popup.removeAllItems()
        for (title, id, tip) in items {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = id
            item.toolTip = tip
            popup.menu?.addItem(item)
        }
        if let index = items.firstIndex(where: { $0.1 == selected }) { popup.selectItem(at: index) }
        showFullTitleIfTruncated(popup)
    }

    /// A device name too long for its column truncates; hovering shows it whole.
    /// (Not `cellSize` — that's the widest *menu item*, so "Off" got a tooltip too.)
    private func showFullTitleIfTruncated(_ popup: NSPopUpButton) {
        popup.window?.layoutIfNeeded()
        let truncated = (popup.cell as? EvenInsetPopUpCell)?.truncatesTitle(in: popup.bounds) ?? false
        popup.toolTip = truncated ? popup.titleOfSelectedItem : nil
    }

    private static func tip(for mode: SystemAudioMode) -> String {
        switch mode {
        case .off: return "No system sound in the recording."
        case .all: return "Every sound your Mac plays, including BetterScreenshot's own."
        case .allExceptSelf: return "Every sound except BetterScreenshot's own, like its capture sound."
        }
    }

    private func devicesChanged() {
        guard panel != nil else { return }
        refreshSources()
    }

    // MARK: - Mic level meter

    /// Runs the meter while a mic is chosen for an MP4 — but only once access is
    /// already granted, so opening the strip never pops the permission prompt.
    private func refreshMeter() {
        stopMeter()
        let config = store.recording
        let mics = micCatalog.snapshot()
        let wantsMic = panel != nil && config.format == .mp4
            && mics.choice(enabled: config.microphone, saved: config.microphoneDeviceID) != .off
        let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        meter.isHidden = !(wantsMic && granted)
        allowMic.isHidden = !(wantsMic && !granted)
        guard wantsMic, granted else { return }
        let capturer = MicCapturer()
        capturer.onLevel = { [weak self] db in
            Task { @MainActor in self?.showLevel(db) }
        }
        do {
            try capturer.start(deviceID: mics.resolvedID(saved: config.microphoneDeviceID),
                               queue: DispatchQueue(label: "betterscreenshot.strip.meter"),
                               onBuffer: { _ in })
            meterCapturer = capturer
        } catch {
            meter.isHidden = true
        }
    }

    private func stopMeter() {
        meterCapturer?.onLevel = nil
        meterCapturer?.stop()
        meterCapturer = nil
        level = 0
        meter.fraction = 0
    }

    private func showLevel(_ db: Float) {
        guard meterCapturer != nil else { return }
        level = MicLevel.smoothed(previous: level, target: MicLevel.fraction(decibels: db))
        meter.fraction = level
    }

    // MARK: - Hint line

    /// Plain-language explanation per control. `idle` shows when nothing is hovered.
    fileprivate enum Hint: String {
        case fullScreen, area, window, format, fps, cancel
        case microphone, systemAudio, camera, cursor, allowMic

        static let idle = "Pick what to record, then choose Full Screen, Area or Window."
        static let noSoundInGIF = "GIFs have no sound. Switch Format to MP4 to record audio."
    }

    /// With nothing hovered: in GIF mode, say up front why the audio menus are greyed out.
    private var idleHint: String { store.recording.format == .gif ? Hint.noSoundInGIF : Hint.idle }

    private func text(for hint: Hint) -> String {
        let isGIF = store.recording.format == .gif
        switch hint {
        case .fullScreen: return "Full Screen: records everything on this screen."
        case .area: return "Area: drag over the part of the screen you want, then recording starts."
        case .window: return "Window: click a window to record just that window, even as it moves."
        case .format: return "Format: MP4 is a video with sound. GIF is a silent, looping animation."
        case .fps: return "Frame rate: 60 looks smoother, 30 makes smaller files."
        case .cancel: return "Close this strip without recording."
        case .microphone:
            return isGIF ? Hint.noSoundInGIF
                : "Microphone: records your voice from the selected input. Choose \"Off\" to skip it."
        case .systemAudio:
            return isGIF ? Hint.noSoundInGIF
                : "System audio: records the sound your Mac plays, like videos and calls. Choose \"Off\" to skip it."
        case .camera: return "Camera: shows your webcam in a round bubble on the recording. Set its size in the menu."
        case .cursor: return "Mouse cursor: choose whether it appears in the video."
        case .allowMic:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
                ? "Click to let BetterScreenshot use the microphone. macOS asks once."
                : "Microphone access is off. Click to open System Settings and turn it on for BetterScreenshot."
        }
    }

    private func track(_ view: NSView, _ hint: Hint, captions: [NSView] = []) {
        hintViews.append((view, hint))
        if !captions.isEmpty { self.captions[hint, default: []] += captions }
    }

    /// Shows the hovered (else focused) control's hint, and brightens that group's
    /// caption so it's clear which control the hint line is about.
    private func updateHint() {
        let active = hovered.last ?? focused
        hintLabel.stringValue = active.map(text(for:)) ?? idleHint
        hintLabel.textColor = active == nil ? RecordingHUDStyle.secondaryText : RecordingHUDStyle.primaryText
        for (hint, views) in captions {
            let color = hint == active ? RecordingHUDStyle.primaryText : RecordingHUDStyle.secondaryText
            for view in views {
                switch view {
                case let label as NSTextField: label.textColor = color
                case let image as NSImageView: image.contentTintColor = color
                case let button as NSButton: button.contentTintColor = color
                default: break
                }
            }
        }
    }

    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) {
        guard let raw = event.trackingArea?.userInfo?["hint"] as? String,
              let hint = Hint(rawValue: raw) else { return }
        hovered.removeAll { $0 == hint }
        hovered.append(hint)
        updateHint()
    }

    @objc(mouseExited:) func mouseExited(with event: NSEvent) {
        guard let raw = event.trackingArea?.userInfo?["hint"] as? String else { return }
        hovered.removeAll { $0.rawValue == raw }
        updateHint()
    }

    private func focusChanged(to responder: NSResponder?) {
        let view = responder as? NSView
        focused = view.flatMap { v in hintViews.last(where: { v.isDescendant(of: $0.view) })?.hint }
        updateHint()
    }

    // MARK: - Actions

    @objc private func fullScreen() { onFullScreen?() }
    @objc private func areaSelect() { onArea?() }
    @objc private func windowSelect() { onWindow?() }
    @objc private func cancelTapped() { onCancel?() }
    private func formatChanged(to index: Int) {
        store.recording.format = index == 0 ? .mp4 : .gif
        store.persist()
        refreshSources()   // also refreshes the idle hint (GIF says why audio is off)
    }
    private func fpsChanged(to index: Int) {
        store.recording.fps = index == 1 ? 60 : 30
        store.persist()
    }
    @objc private func micChosen(_ sender: NSPopUpButton) {
        store.recording.setMicrophone(DeviceChoice(id: sender.selectedItem?.representedObject as? String))
        store.persist()
        refreshMeter()
    }
    @objc private func audioChosen(_ sender: NSPopUpButton) {
        store.recording.systemAudioMode = SystemAudioMode(
            rawValue: sender.selectedItem?.representedObject as? String ?? "") ?? .off
        store.persist()
    }
    @objc private func cameraChosen(_ sender: NSPopUpButton) {
        store.recording.setCamera(DeviceChoice(id: sender.selectedItem?.representedObject as? String))
        store.persist()
    }
    @objc private func cameraSizeChosen(_ sender: NSMenuItem) {
        guard let size = CameraSize(rawValue: sender.representedObject as? String ?? "") else { return }
        store.recording.cameraSize = size
        store.persist()
        refreshSources()   // moves the checkmark and keeps the camera row selected
    }
    @objc private func cursorChosen(_ sender: NSPopUpButton) {
        store.recording.showsCursor = sender.selectedItem?.representedObject as? String != "hidden"
        store.persist()
    }
    @objc private func allowMicTapped() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            Task { @MainActor in
                _ = await MicCapturer.ensurePermission()
                self.refreshMeter()
                self.updateHint()
            }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

private extension RecordStripController {
    static func popup() -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.cell = EvenInsetPopUpCell(textCell: "", pullsDown: false)
        return popup
    }
}

/// Format / FPS picker: a rounded track with the chosen option filled in the accent
/// colour. NSSegmentedControl only draws a strong selection while its window is key,
/// and this non-activating panel rarely is — inactive, the chosen segment was only a
/// shade lighter than the other (UI review S5).
private final class ChoiceControl: NSStackView {
    private var selected: Int
    private let onChange: (Int) -> Void
    private var buttons: [NSButton] = []

    init(_ titles: [String], selected: Int, name: String, onChange: @escaping (Int) -> Void) {
        self.selected = selected
        self.onChange = onChange
        super.init(frame: .zero)
        spacing = 2
        edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(name)
        for (i, title) in titles.enumerated() {
            let b = NSButton(title: title, target: self, action: #selector(chosen(_:)))
            b.tag = i
            b.isBordered = false
            b.wantsLayer = true
            b.layer?.cornerRadius = 5
            b.setAccessibilityRole(.radioButton)
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 22).isActive = true
            b.widthAnchor.constraint(equalToConstant: 40).isActive = true
            buttons.append(b)
            addArrangedSubview(b)
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func chosen(_ sender: NSButton) {
        guard sender.tag != selected else { return }
        selected = sender.tag
        refresh()
        onChange(selected)
    }

    private func refresh() {
        for b in buttons {
            let on = b.tag == selected
            b.layer?.backgroundColor = (on ? NSColor.controlAccentColor : .clear).cgColor
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: on ? .semibold : .regular),
                .foregroundColor: on ? NSColor.white : RecordingHUDStyle.secondaryText])
            b.setAccessibilityValue(on)
        }
    }
}

/// A borderless panel that can still become key (keyboard focus in the strip).
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// NSPopUpButtonCell squeezes its title's left inset from 12pt to 5pt when the title
/// doesn't fit, so a truncated device name started ~7pt left of every other menu's
/// title. Keep the inset a fitting title gets.
private final class EvenInsetPopUpCell: NSPopUpButtonCell {
    private func fittingInset(in bounds: NSRect) -> CGFloat {
        let reference = NSPopUpButtonCell(textCell: "", pullsDown: false)
        reference.controlSize = controlSize
        reference.font = font
        reference.addItem(withTitle: "Off")
        return reference.titleRect(forBounds: bounds).minX
    }

    func truncatesTitle(in bounds: NSRect) -> Bool {
        let rect = titleRect(forBounds: bounds)
        let available = rect.maxX - max(rect.minX, fittingInset(in: bounds))
        return attributedTitle.size().width > available + 0.5
    }

    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect,
                            in controlView: NSView) -> NSRect {
        let inset = fittingInset(in: controlView.bounds)
        guard frame.minX < inset else { return super.drawTitle(title, withFrame: frame, in: controlView) }
        var rect = frame
        rect.size.width -= inset - frame.minX
        rect.origin.x = inset
        return super.drawTitle(title, withFrame: rect, in: controlView)
    }
}

/// Menu-item ids: "off" for Off, else the device's uniqueID.
private extension DeviceChoice {
    init(id: String?) {
        guard let id, id != "off" else { self = .off; return }
        self = .device(id)
    }
    var id: String {
        switch self {
        case .off: return "off"
        case .device(let id): return id
        }
    }
}

/// A row of small segments lit green → yellow → red with the mic level (0…1).
private final class LevelMeterView: NSView {
    static let segments = 16

    var fraction = 0.0 {
        didSet {
            if MicLevel.litSegments(fraction: fraction, count: Self.segments)
                != MicLevel.litSegments(fraction: oldValue, count: Self.segments) { needsDisplay = true }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let n = Self.segments
        let gap: CGFloat = 2
        let w = (bounds.width - gap * CGFloat(n - 1)) / CGFloat(n)
        let lit = MicLevel.litSegments(fraction: fraction, count: n)
        for i in 0..<n {
            let rect = NSRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: bounds.height)
            let position = Double(i + 1) / Double(n)
            let color: NSColor = i >= lit ? .white.withAlphaComponent(0.14)
                : position > 0.9 ? .systemRed : position > 0.7 ? .systemYellow : .systemGreen
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}
