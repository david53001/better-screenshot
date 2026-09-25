import AppKit

/// A small transient confirmation toast ("Text copied — 132 characters").
/// Bottom-center of the given screen; disappears after ~1.5 s. Showing a new
/// message replaces the current one.
@MainActor
public final class HUDController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    public init() {}

    deinit { dismissTask?.cancel() }

    /// `symbol` is an optional SF Symbol name drawn before the message.
    public func show(_ message: String, symbol: String? = nil, on screen: NSScreen? = NSScreen.main) {
        dismissTask?.cancel()
        panel?.orderOut(nil); panel = nil
        guard let screen else { return }

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = HUDStyle.primaryText
        label.sizeToFit()

        let icon = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            .map { img -> NSImageView in
                let v = NSImageView(image: img)
                v.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
                v.contentTintColor = HUDStyle.primaryText
                v.sizeToFit()
                return v
            }
        let iconGap: CGFloat = 7
        let iconWidth = icon.map { $0.frame.width + iconGap } ?? 0

        let pad = NSSize(width: 18, height: 10)
        let size = NSSize(width: iconWidth + label.frame.width + pad.width * 2,
                          height: label.frame.height + pad.height * 2)
        let vf = screen.visibleFrame
        let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 80)

        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = HUDStyle.makeBackground(frame: NSRect(origin: .zero, size: size),
                                                cornerRadius: size.height / 2)
        if let icon {
            icon.frame.origin = NSPoint(x: pad.width, y: ((size.height - icon.frame.height) / 2).rounded())
            container.addSubview(icon)
        }
        label.frame.origin = NSPoint(x: pad.width + iconWidth, y: pad.height)
        container.addSubview(label)

        panel.contentView = container
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
    }
}
