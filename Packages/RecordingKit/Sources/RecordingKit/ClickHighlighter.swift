import AppKit

/// Fading accent circles at every mouse-down, drawn in a transparent
/// click-through panel covering the recorded screen. Global+local monitors —
/// mouse monitors need no special permission.
@MainActor
public final class ClickHighlighter {
    private var panel: NSPanel?
    private var monitors: [Any] = []

    public init() {}

    public func start(on screen: NSScreen) {
        guard panel == nil else { return }
        let p = NSPanel(contentRect: screen.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false   // a Dock app deactivates often; panels hide then by default
        p.canHide = false   // ⌘H / another app's Hide Others leave it on screen (Dock app, 3.3.0)
        p.contentView?.wantsLayer = true
        p.orderFrontRegardless()
        panel = p

        let down: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.flash(at: NSEvent.mouseLocation) }
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: down) {
            monitors.append(global)
        }
        // Global monitors don't see this app's own events — add a local one too.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            down(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    public func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }

    private func flash(at globalPoint: CGPoint) {
        guard let panel, let layer = panel.contentView?.layer,
              panel.frame.contains(globalPoint) else { return }
        let local = CGPoint(x: globalPoint.x - panel.frame.minX,
                            y: globalPoint.y - panel.frame.minY)
        let d: CGFloat = 36
        let circle = CAShapeLayer()
        circle.path = CGPath(ellipseIn: CGRect(x: local.x - d / 2, y: local.y - d / 2,
                                               width: d, height: d), transform: nil)
        circle.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
        layer.addSublayer(circle)
        CATransaction.begin()
        CATransaction.setCompletionBlock { circle.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = 0.4
        fade.isRemovedOnCompletion = false
        fade.fillMode = .forwards
        circle.add(fade, forKey: "fade")
        CATransaction.commit()
    }
}
