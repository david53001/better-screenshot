import AppKit

public protocol Annotation {
    var id: UUID { get }
    var style: AnnotationStyle { get set }
    func boundingBox() -> CGRect
    /// Draws into the CURRENT NSGraphicsContext (flipped, top-left origin, image-pixel units).
    func draw()
    func moved(by delta: CGVector) -> any Annotation
}

public extension Annotation {
    /// Lenient v1 hit-test: a few px of slop around the bounding box.
    func hitTest(_ point: CGPoint) -> Bool {
        boundingBox().insetBy(dx: -6, dy: -6).contains(point)
    }
}

public extension Annotation {
    /// Draws the object with its style's opacity. Below 1 it draws inside one
    /// transparency layer, so e.g. an arrow's shaft and head — or a text and its
    /// background — fade together instead of doubling up where they overlap.
    /// Canvas and renderer both call this, never `draw()` directly.
    func drawComposited() {
        guard style.opacity < 1, let ctx = NSGraphicsContext.current?.cgContext else { draw(); return }
        ctx.saveGState()
        ctx.setAlpha(style.opacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        draw()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
