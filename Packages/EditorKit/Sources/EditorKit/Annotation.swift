import AppKit

public protocol Annotation {
    var id: UUID { get }
    var style: AnnotationStyle { get set }
    func boundingBox() -> CGRect
    /// Draws into the CURRENT NSGraphicsContext (flipped, top-left origin, image-pixel units).
    func draw()
    func moved(by delta: CGVector) -> any Annotation
    /// How the object composites onto what's under it (the highlighter multiplies).
    var blendMode: CGBlendMode { get }
}

public extension Annotation {
    var blendMode: CGBlendMode { .normal }
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
    /// Canvas and renderer both call this, never `draw()` directly. A non-normal `blendMode`
    /// applies to the whole layer, so it blends with the image, not with the object's own parts.
    func drawComposited() {
        guard style.opacity < 1 || blendMode != .normal,
              let ctx = NSGraphicsContext.current?.cgContext else { draw(); return }
        ctx.saveGState()
        ctx.setAlpha(style.opacity)
        ctx.setBlendMode(blendMode)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        draw()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
