import AppKit
import DesignKit

/// Visual styling for a pin, decided at creation time (from app Settings).
public struct PinStyle {
    public let cornerRadius: CGFloat
    public let shadow: Bool
    public init(cornerRadius: CGFloat, shadow: Bool) {
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }
}

/// App-supplied actions; OverlayKit stays free of clipboard/file knowledge.
public struct PinActions {
    public let onCopy: () -> Void
    public let onSave: () -> Void
    public init(onCopy: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.onCopy = onCopy
        self.onSave = onSave
    }
}

/// Owns every live pin. Pins float above everything, appear on all Spaces,
/// and never steal focus. They live until closed or the app quits.
@MainActor
public final class PinPanelController {
    private var panels: [NSPanel] = []

    public init() {}

    public func pin(image: NSImage, pixelSize: CGSize, sourceRect: CGRect?,
                    on screen: NSScreen, style: PinStyle, actions: PinActions) {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return }
        let scale = screen.backingScaleFactor
        let frame = PinGeometry.initialFrame(
            imagePixelSize: pixelSize, backingScale: scale,
            visibleFrame: screen.visibleFrame, sourceRect: sourceRect)
        let naturalSize = CGSize(width: pixelSize.width / scale,
                                 height: pixelSize.height / scale)

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = style.shadow
        panel.hidesOnDeactivate = false

        let view = PinView(image: image, naturalSize: naturalSize, actions: actions,
                           onClose: { [weak self, weak panel] in
            guard let self, let panel else { return }
            panel.orderOut(nil)
            self.panels.removeAll { $0 === panel }
        })
        view.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = view
        view.layer?.setContinuousCorners(style.cornerRadius)
        panel.orderFrontRegardless()
        panels.append(panel)
    }
}
