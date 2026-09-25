import AppKit
import SwiftUI
import CaptureKit

/// Click-to-record shortcut well. Active state captures the next keypress with a
/// local NSEvent monitor: a combo containing ⌘/⌥/⌃ is reported, Esc cancels,
/// ⌫ clears the binding. Events are swallowed while recording.
struct ShortcutRecorderField: NSViewRepresentable {
    var combo: HotkeyCombo?
    @Binding var isRecording: Bool
    /// nil = clear the binding (⌫ pressed while recording).
    var onCombo: (HotkeyCombo?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> RecorderWell {
        let well = RecorderWell()
        well.onClick = { context.coordinator.toggle() }
        return well
    }

    func updateNSView(_ well: RecorderWell, context: Context) {
        context.coordinator.parent = self
        well.label = isRecording ? "Type shortcut…" : (combo?.displayString ?? "—")
        well.active = isRecording
        context.coordinator.setMonitoring(isRecording, window: well.window)
    }

    @MainActor
    final class Coordinator {
        var parent: ShortcutRecorderField
        private var monitor: Any?
        private var closeObserver: NSObjectProtocol?

        init(_ parent: ShortcutRecorderField) { self.parent = parent }

        deinit {
            // Last-resort teardown: SwiftUI may discard the representable while
            // recording without a final updateNSView(false) pass.
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        }

        func toggle() { parent.isRecording.toggle() }

        func setMonitoring(_ on: Bool, window: NSWindow?) {
            if on, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    MainActor.assumeIsolated { self?.handle(event) }
                    return nil   // swallow every keypress while recording
                }
                if let window {
                    closeObserver = NotificationCenter.default.addObserver(
                        forName: NSWindow.willCloseNotification, object: window, queue: .main
                    ) { [weak self] _ in
                        // Rebind strongly: older Swift compilers (5.10, the CI
                        // toolchain) reject referencing a weak `var` capture
                        // inside the nested concurrent Task.
                        guard let self else { return }
                        Task { @MainActor in self.parent.isRecording = false }
                    }
                }
            } else if !on, monitor != nil {
                stopMonitoring()
            }
        }

        private func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
            closeObserver = nil
        }

        private func handle(_ event: NSEvent) {
            let plain = event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty
            if event.keyCode == 53, plain {            // Esc — cancel
                parent.isRecording = false
                return
            }
            if event.keyCode == 51, plain {            // ⌫ — clear binding
                parent.isRecording = false
                parent.onCombo(nil)
                return
            }
            let combo = HotkeyCombo(keyCode: UInt32(event.keyCode),
                                    cocoaModifierFlagsRaw: UInt(event.modifierFlags.rawValue))
            guard combo.isValid else { return }        // keep waiting for ⌘/⌥/⌃
            parent.isRecording = false
            parent.onCombo(combo)
        }
    }
}

/// The visual well: rounded rect + centered label; click reports to the field.
/// It is the only control for changing a shortcut, so it outlines on hover and
/// carries a tooltip to read as clickable rather than as a static label.
final class RecorderWell: NSView {
    var onClick: (() -> Void)?
    var label: String = "—" { didSet { needsDisplay = true } }
    var active: Bool = false { didSet { needsDisplay = true } }
    private var hovered = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "Click, then press a new shortcut"
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 22) }

    /// A well under `view` is waiting for a key press (its window then leaves Return/Esc to it).
    static func anyRecording(in view: NSView) -> Bool {
        if let well = view as? RecorderWell, well.active { return true }
        return view.subviews.contains { anyRecording(in: $0) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                             xRadius: 5, yRadius: 5)
        (active ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                : NSColor.controlBackgroundColor).setFill()
        r.fill()
        (active ? NSColor.controlAccentColor
                : hovered ? NSColor.secondaryLabelColor : NSColor.separatorColor).setStroke()
        r.stroke()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: active ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                               y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}
