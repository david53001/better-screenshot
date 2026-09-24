import AppKit

public enum SpotlightShape: String, Codable, CaseIterable {
    case rectangle, ellipse
}

/// An area to draw attention to: everything outside *all* spotlights is dimmed. A spotlight
/// draws nothing itself — `AnnotationPainter` draws one dim layer with a hole per spotlight.
/// Shape = `style.spotlightShape`, dim = `style.spotlightDim` (the canvas keeps every
/// spotlight's dim equal, since they share the layer).
public struct SpotlightAnnotation: Annotation {
    public let id = UUID()
    public var style: AnnotationStyle
    public var frame: CGRect
    public init(frame: CGRect, style: AnnotationStyle = .default) {
        self.frame = frame; self.style = style
    }

    public func boundingBox() -> CGRect { frame }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.frame = frame.offsetBy(dx: d.dx, dy: d.dy); return c
    }
    public func draw() {}

    /// The hole this spotlight cuts in the dim layer.
    var holePath: CGPath {
        style.spotlightShape == .ellipse ? CGPath(ellipseIn: frame, transform: nil) : CGPath(rect: frame, transform: nil)
    }
}

public extension AnnotationStyle {
    static let spotlightDimRange: ClosedRange<CGFloat> = 0.1...0.9
}

/// Draws a document's annotations — shared by the canvas and `DocumentRenderer`.
enum AnnotationPainter {
    /// Draws `annotations` in order into the current flipped, image-px context. The spotlight
    /// dim layer goes directly above the base image and below every object, so arrows and text
    /// stay bright; redactions are part of the picture, so the dim is re-applied over each one
    /// (clipped to it) — otherwise a blur outside the spotlight would glow undimmed.
    static func draw(_ annotations: [any Annotation], imageSize: CGSize) {
        let spots = annotations.compactMap { $0 as? SpotlightAnnotation }
        let dim = { (clip: CGRect?) in drawDimLayer(spots, imageSize: imageSize, clip: clip) }
        if !spots.isEmpty { dim(nil) }
        for a in annotations {
            a.drawComposited()
            if !spots.isEmpty, let r = a as? RedactionAnnotation { dim(r.patchRect) }
        }
    }

    /// Black at the topmost spotlight's dim over the whole image, minus every spotlight shape.
    /// Holes are cleared one by one inside a transparency layer, so overlapping spotlights stay
    /// bright where they overlap (an even-odd fill would dim the overlap again).
    static func drawDimLayer(_ spots: [SpotlightAnnotation], imageSize: CGSize, clip: CGRect? = nil) {
        guard let dim = spots.last?.style.spotlightDim, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        if let clip { ctx.clip(to: clip) }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(CGColor(gray: 0, alpha: dim))
        ctx.fill(CGRect(origin: .zero, size: imageSize))
        ctx.setBlendMode(.clear)
        for s in spots { ctx.addPath(s.holePath); ctx.fillPath() }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
