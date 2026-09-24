import AppKit

/// A freehand translucent marker stroke, like a highlighter pen. Drawn with multiply blending,
/// so dark text under it stays dark and readable while light areas take the colour. Colour =
/// `style.strokeColor`, width = `style.lineWidth`, see-through = `style.opacity`.
public struct HighlighterAnnotation: Annotation {
    public let id = UUID()
    public var style: AnnotationStyle
    /// The pointer's path in image px (at least one point).
    public var points: [CGPoint]
    public init(points: [CGPoint], style: AnnotationStyle = AnnotationStyle.default.withHighlighterPen) {
        self.points = points; self.style = style
    }

    public var blendMode: CGBlendMode { .multiply }

    /// Path bounds plus half the pen width.
    public func boundingBox() -> CGRect {
        guard let first = points.first else { return .zero }
        var r = CGRect(origin: first, size: .zero)
        for p in points.dropFirst() { r = r.union(CGRect(origin: p, size: .zero)) }
        return r.insetBy(dx: -style.lineWidth / 2, dy: -style.lineWidth / 2)
    }

    public func moved(by d: CGVector) -> any Annotation {
        var c = self
        c.points = points.map { CGPoint(x: $0.x + d.dx, y: $0.y + d.dy) }
        return c
    }

    public func draw() {
        guard let first = points.first else { return }
        // One path, stroked once: where the stroke crosses itself it doesn't darken twice.
        let path = NSBezierPath()
        path.move(to: first)
        for p in points.dropFirst() { path.line(to: p) }
        if points.count == 1 { path.line(to: first) }   // a dot
        path.lineWidth = style.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        style.strokeColor.nsColor.setStroke()
        path.stroke()
    }
}

/// The highlighter's own sticky colour, width and opacity, kept apart from the other tools'
/// (a yellow 40% marker shouldn't make the next arrow yellow and see-through).
public struct HighlighterPen: Equatable, Codable {
    public var color: RGBAColor
    public var width: CGFloat
    public var opacity: CGFloat
    public init(color: RGBAColor, width: CGFloat, opacity: CGFloat) {
        self.color = color; self.width = width; self.opacity = opacity
    }

    /// The panel's yellow preset, Medium width, 40%.
    public static let `default` = HighlighterPen(color: RGBAColor(r: 1, g: 0.84, b: 0.04, a: 1), width: 20, opacity: 0.4)
    public static let widthRange: ClosedRange<CGFloat> = 4...48
    /// Thin / Medium / Thick.
    public static let widthPresets: [CGFloat] = [12, 20, 32]

    /// Width and opacity pulled into range (a bad persisted value can't hide the pen).
    var clamped: HighlighterPen {
        HighlighterPen(color: color,
                       width: AnnotationStyle.clamp(width, Self.widthRange),
                       opacity: AnnotationStyle.clamp(opacity, AnnotationStyle.opacityRange))
    }
}

public extension AnnotationStyle {
    /// This style with the pen's colour, width and opacity — what new highlighter strokes use
    /// and what the panel shows (and edits) while the Highlighter tool is active.
    var withHighlighterPen: AnnotationStyle {
        var s = self
        s.strokeColor = highlighterPen.color
        s.fillColor = RGBAColor(r: highlighterPen.color.r, g: highlighterPen.color.g, b: highlighterPen.color.b, a: 0.25)
        s.lineWidth = highlighterPen.width
        s.opacity = highlighterPen.opacity
        return s
    }

    /// Keeps `penStyle`'s colour, width and opacity (e.g. `withHighlighterPen` after a panel
    /// edit) as the sticky pen.
    mutating func rememberHighlighterPen(from penStyle: AnnotationStyle) {
        highlighterPen = HighlighterPen(color: penStyle.strokeColor, width: penStyle.lineWidth,
                                        opacity: penStyle.opacity)
    }
}
