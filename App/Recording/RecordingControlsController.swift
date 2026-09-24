import AppKit

/// The floating pill shown for the whole recording session (countdown included):
/// red dot · elapsed time · Pause/Resume · Stop. Draggable. Whether it shows up
/// in the video is decided by RecordingCoordinator's content filter, not here —
/// `windowID` is what the coordinator excludes.
@MainActor
final class RecordingControlsController {
    private var panel: NSPanel?
    private var timeLabel: NSTextField?
    private var pauseButton: NSButton?

    var onStop: (() -> Void)?
    var onPauseResume: (() -> Void)?

    /// The panel's window-server ID (matches `SCWindow.windowID`), nil when hidden.
    var windowID: CGWindowID? { panel.map { CGWindowID($0.windowNumber) } }

    func show(on screen: NSScreen) {
        guard panel == nil else { return }
        let size = NSSize(width: 176, height: 40)
        let frame = NSRect(x: screen.visibleFrame.midX - size.width / 2,
                           y: screen.visibleFrame.minY + 20,
                           width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.appearance = NSAppearance(named: .vibrantDark)
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = size.height / 2
        bg.layer?.masksToBounds = true

        let dot = NSView(frame: NSRect(x: 16, y: (size.height - 10) / 2, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5
        bg.addSubview(dot)

        let label = NSTextField(labelWithString: "0:00")
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.frame = NSRect(x: 34, y: (size.height - 18) / 2, width: 64, height: 18)
        bg.addSubview(label)

        let pause = Self.button(symbol: "pause.fill", tip: "Pause recording",
                                target: self, action: #selector(pauseTapped))
        pause.frame = NSRect(x: size.width - 76, y: 4, width: 32, height: 32)
        bg.addSubview(pause)

        let stop = Self.button(symbol: "stop.fill", tip: "Stop recording",
                               target: self, action: #selector(stopTapped))
        stop.contentTintColor = .systemRed
        stop.frame = NSRect(x: size.width - 40, y: 4, width: 32, height: 32)
        bg.addSubview(stop)

        p.contentView = bg
        p.orderFrontRegardless()
        panel = p
        timeLabel = label
        pauseButton = pause
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        timeLabel = nil
        pauseButton = nil
    }

    /// `elapsed` is RecorderState's string ("1:23" / "Paused · 1:23"); nil before
    /// the engine starts (countdown), which keeps the 0:00 placeholder.
    func update(elapsed: String?, paused: Bool) {
        if let elapsed {
            timeLabel?.stringValue = elapsed.replacingOccurrences(of: "Paused · ", with: "")
        }
        timeLabel?.textColor = paused ? .secondaryLabelColor : .white
        pauseButton?.image = NSImage(systemSymbolName: paused ? "play.fill" : "pause.fill",
                                     accessibilityDescription: paused ? "Resume" : "Pause")
        pauseButton?.toolTip = paused ? "Resume recording" : "Pause recording"
    }

    @objc private func stopTapped() { onStop?() }
    @objc private func pauseTapped() { onPauseResume?() }

    private static func button(symbol: String, tip: String, target: AnyObject,
                               action: Selector) -> NSButton {
        let b = FirstMouseButton(image: NSImage(systemSymbolName: symbol,
                                                accessibilityDescription: tip)!,
                                 target: target, action: action)
        b.isBordered = false
        b.imageScaling = .scaleNone
        b.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        b.contentTintColor = .white
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        return b
    }
}

/// Clicks land on the first try even though the panel never becomes key.
private final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
