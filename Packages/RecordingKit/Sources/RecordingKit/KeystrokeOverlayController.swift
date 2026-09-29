import AppKit
import DesignKit
import ApplicationServices

/// Dark pill showing each keypress ("⌘⇧4") near the bottom of the recorded
/// screen. Global keyDown monitoring requires Accessibility trust — the only
/// permission-gated feature in the app.
@MainActor
public final class KeystrokeOverlayController {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var monitors: [Any] = []
    private var fadeTimer: Timer?

    public init() {}

    public static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Prompts the user (opens System Settings) when not yet trusted.
    public static func requestPermission() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    public func start(on screen: NSScreen) {
        guard panel == nil, Self.hasPermission else { return }
        let size = CGSize(width: 280, height: 44)
        let frame = CGRect(x: screen.frame.midX - size.width / 2,
                           y: screen.visibleFrame.minY + 100,
                           width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = HUDSurfaceView(frame: CGRect(origin: .zero, size: size), cornerRadius: 10)
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedSystemFont(ofSize: 20, weight: .semibold)
        label.textColor = HUDSurfaceView.primaryText
        label.alignment = .center
        label.frame = content.bounds.insetBy(dx: 8, dy: 8)
        label.autoresizingMask = [.width, .height]
        content.addSubview(label)
        p.contentView = content
        p.alphaValue = 0
        p.orderFrontRegardless()

        self.panel = p
        self.label = label

        let handler: (NSEvent) -> Void = { [weak self] event in
            let text = Self.glyphString(for: event)
            Task { @MainActor in self?.show(text) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    public func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        fadeTimer?.invalidate()
        fadeTimer = nil
        panel?.orderOut(nil)
        panel = nil
        label = nil
    }

    private func show(_ text: String) {
        guard let panel, let label else { return }
        label.stringValue = text
        panel.alphaValue = 1
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            Task { @MainActor [weak self] in
                self?.panel?.animator().alphaValue = 0
            }
        }
    }

    /// "⌃⌥⇧⌘X" — modifier glyphs + the typed character (uppercased) or key name.
    static func glyphString(for event: NSEvent) -> String {
        var s = ""
        let f = event.modifierFlags
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        switch event.keyCode {
        case 36: return s + "↩"
        case 48: return s + "⇥"
        case 49: return s + "Space"
        case 51: return s + "⌫"
        case 53: return s + "Esc"
        case 123: return s + "←"
        case 124: return s + "→"
        case 125: return s + "↓"
        case 126: return s + "↑"
        default:
            let chars = event.charactersIgnoringModifiers ?? ""
            return s + chars.uppercased()
        }
    }
}
