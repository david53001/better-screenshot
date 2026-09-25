import AppKit
import CaptureKit
import TourKit

/// Manages up to `maxCount` post-capture overlays stacked at a screen corner.
/// Index 0 is the newest capture and sits at the corner slot; older overlays
/// step away from the screen edge. A capture beyond the limit evicts the
/// oldest; dismissing any overlay compacts the stack. Each card's actual size
/// (which varies with its capture's aspect ratio) drives the stacking via
/// `OverlayPositioner.stackedOrigins`, so OverlayKit stays the source of the
/// per-card size while CaptureKit remains the source of positioning logic.
@MainActor
public final class QuickAccessStackController {
    public let maxCount = 3
    private var entries: [QuickAccessOverlayController] = []   // index 0 = newest
    private var corner: OverlayCorner = .bottomRight
    private var screenFrame: CGRect = .zero
    private var margin: CGFloat = 24

    public init() {}

    public func present(image: NSImage, kind: QuickAccessKind = .screenshot,
                        actions: QuickAccessActions, autoDismissSeconds: Int,
                        corner: OverlayCorner, screenFrame: CGRect, margin: CGFloat = 24,
                        badge: String? = nil,
                        onDismissed: ((DismissReason) -> Void)? = nil) {
        self.corner = corner
        self.screenFrame = screenFrame
        self.margin = margin
        if entries.count == maxCount, let oldest = entries.last {
            entries.removeLast()
            oldest.dismiss(reason: .evicted)   // stack bookkeeping no-ops: already removed
        }
        let controller = QuickAccessOverlayController()
        controller.onDismissed = { [weak self, weak controller] reason in
            onDismissed?(reason)
            guard let self, let controller else { return }
            self.entries.removeAll { $0 === controller }
            self.restack()
        }
        entries.insert(controller, at: 0)
        // Provisional origin: present() computes the card's real contentSize
        // from the image's aspect ratio, then restack() repositions precisely.
        controller.present(image: image, at: CGPoint(x: screenFrame.maxX, y: screenFrame.minY),
                           kind: kind, actions: actions, autoDismissSeconds: autoDismissSeconds,
                           badge: badge)
        restack()
        // Once it sits in its final slot. The Quick Access tour is about screenshot cards (Edit →
        // editor); a recording's card has no Edit button.
        if kind == .screenshot, let window = controller.window {
            TourEvents.surfaceShown(.quickAccess, in: window)
        }
    }

    private func restack() {
        let sizes = entries.map { $0.contentSize }
        let origins = OverlayPositioner.stackedOrigins(corner: corner, sizes: sizes,
                                                        screenFrame: screenFrame, margin: margin,
                                                        spacing: 12)
        for (i, entry) in entries.enumerated() { entry.move(to: origins[i]) }
    }
}
