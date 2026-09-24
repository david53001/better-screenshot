import CoreGraphics

/// Corner-handle scaling of a text annotation: the whole text grows or shrinks like an image
/// (font size, box width, box padding / corner radius, outline width) while the corner
/// opposite the dragged one stays put. Pure; the canvas maps its handles onto `Corner`.
public enum TextScale {
    public static let fontSizeRange: ClosedRange<CGFloat> = 8...400

    public enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    /// The corner's position in `box` (top-left origin).
    public static func point(of corner: Corner, in box: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: box.minX, y: box.minY)
        case .topRight: return CGPoint(x: box.maxX, y: box.minY)
        case .bottomLeft: return CGPoint(x: box.minX, y: box.maxY)
        case .bottomRight: return CGPoint(x: box.maxX, y: box.maxY)
        }
    }

    /// The corner diagonally opposite `corner` — the point that stays fixed.
    public static func anchor(of corner: Corner, in box: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return point(of: .bottomRight, in: box)
        case .topRight: return point(of: .bottomLeft, in: box)
        case .bottomLeft: return point(of: .topRight, in: box)
        case .bottomRight: return point(of: .topLeft, in: box)
        }
    }

    /// Scale factor for moving `corner` of `box` by `drag`: the dragged corner's new distance
    /// from the anchor, measured along the box's diagonal (a drag across the diagonal does
    /// nothing), relative to the diagonal. 1 = unchanged; ≤ 0 when dragged past the anchor.
    public static func factor(box: CGRect, corner: Corner, by drag: CGVector) -> CGFloat {
        let a = anchor(of: corner, in: box), c = point(of: corner, in: box)
        let d = CGVector(dx: c.x - a.x, dy: c.y - a.y)
        let lengthSquared = d.dx * d.dx + d.dy * d.dy
        guard lengthSquared > 0 else { return 1 }
        let moved = CGVector(dx: c.x + drag.dx - a.x, dy: c.y + drag.dy - a.y)
        return (moved.dx * d.dx + moved.dy * d.dy) / lengthSquared
    }

    /// `style` and `wrapWidth` scaled by `factor`. The font size is rounded to whole px and
    /// clamped to `fontSizeRange`; everything else moves by the factor the font actually moved
    /// (so a clamped font doesn't leave the box width behind) — padding, corner radius and
    /// outline width within their ranges. A free label (nil width) stays free.
    public static func scaled(_ style: AnnotationStyle, wrapWidth: CGFloat?,
                              by factor: CGFloat) -> (style: AnnotationStyle, wrapWidth: CGFloat?) {
        var s = style
        s.fontSize = clamp((style.fontSize * factor).rounded(), fontSizeRange)
        let k = s.fontSize / style.fontSize
        s.textBackgroundPadding = clamp(style.textBackgroundPadding * k, AnnotationStyle.textBackgroundPaddingRange)
        s.textBackgroundCornerRadius = clamp(style.textBackgroundCornerRadius * k,
                                             AnnotationStyle.textBackgroundCornerRadiusRange)
        s.textOutlineWidth = clamp(style.textOutlineWidth * k, AnnotationStyle.textOutlineWidthRange)
        return (s, wrapWidth.map { $0 * k })
    }

    /// A rect of `size` whose corner opposite `corner` sits at `anchor`.
    public static func placed(size: CGSize, anchor: CGPoint, corner: Corner) -> CGRect {
        let x = (corner == .topLeft || corner == .bottomLeft) ? anchor.x - size.width : anchor.x
        let y = (corner == .topLeft || corner == .topRight) ? anchor.y - size.height : anchor.y
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func clamp(_ v: CGFloat, _ r: ClosedRange<CGFloat>) -> CGFloat {
        min(max(v, r.lowerBound), r.upperBound)
    }
}

extension TextAnnotation {
    /// This text scaled by dragging `corner` of its box by `drag` (image px) — see `TextScale`.
    /// Always scale the text as it was when the drag began, not incrementally.
    public func scaled(dragging corner: TextScale.Corner, by drag: CGVector) -> TextAnnotation {
        let box = boundingBox()
        let r = TextScale.scaled(style, wrapWidth: wrapWidth,
                                 by: TextScale.factor(box: box, corner: corner, by: drag))
        var c = self
        c.style = r.style
        c.wrapWidth = r.wrapWidth
        let now = c.boundingBox()
        let target = TextScale.placed(size: now.size, anchor: TextScale.anchor(of: corner, in: box), corner: corner)
        c.origin.x += target.minX - now.minX
        c.origin.y += target.minY - now.minY
        return c
    }
}
