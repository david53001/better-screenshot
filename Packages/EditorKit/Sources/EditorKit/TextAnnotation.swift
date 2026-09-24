import AppKit

public struct TextAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var text: String
    public var origin: CGPoint   // top-left
    /// Text-box width (image px): lines soft-wrap at it and alignment is relative to it.
    /// nil = a free label — only explicit newlines break lines, box hugs the text.
    public var wrapWidth: CGFloat?
    public init(text: String, origin: CGPoint, style: AnnotationStyle = .default,
                wrapWidth: CGFloat? = nil) {
        self.text = text; self.origin = origin; self.style = style; self.wrapWidth = wrapWidth
    }

    /// Font + colour + alignment + underline / strikethrough for `style` at `fontSize` points —
    /// shared with the canvas's inline editor (which passes a view-scaled size) so both lay out alike.
    public static func attributes(for style: AnnotationStyle,
                                  fontSize: CGFloat? = nil) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.alignment = style.textAlignment.nsAlignment
        var attrs: [NSAttributedString.Key: Any] = [
            .font: TextFont.font(family: style.fontFamily, size: fontSize ?? style.fontSize,
                                 bold: style.fontBold, italic: style.fontItalic),
            .foregroundColor: style.strokeColor.nsColor,
            .paragraphStyle: para]
        if style.textUnderline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.textStrikethrough { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attrs
    }

    /// The outline pass: stroke-only letters. `strokeWidth` is a percentage of the font size, and
    /// twice the outline width, because the letters drawn on top cover its inner half.
    private static func outlineAttributes(for style: AnnotationStyle) -> [NSAttributedString.Key: Any] {
        var attrs = attributes(for: style)
        attrs[.strokeWidth] = 200 * style.textOutlineWidth / style.fontSize
        attrs[.strokeColor] = style.textOutlineColor.nsColor
        return attrs
    }
    private var attributed: NSAttributedString {
        NSAttributedString(string: text.isEmpty ? " " : text, attributes: Self.attributes(for: style))
    }
    private static let drawOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    private var layoutSize: CGSize {
        let r = attributed.boundingRect(
            with: CGSize(width: wrapWidth ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: Self.drawOptions)
        return CGSize(width: wrapWidth ?? ceil(r.width), height: ceil(r.height))
    }
    /// How far the box behind the text extends past the text (zero without a box).
    var backgroundInsets: CGSize {
        style.textBackgroundMode == .none ? .zero : TextChip.insets(padding: style.textBackgroundPadding)
    }
    /// The text plus the box behind it — what selection, handles and hit-testing use.
    public func boundingBox() -> CGRect {
        let pad = backgroundInsets
        return CGRect(origin: origin, size: layoutSize).insetBy(dx: -pad.width, dy: -pad.height)
    }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.origin = CGPoint(x: origin.x + d.dx, y: origin.y + d.dy); return c
    }
    public func draw() { draw(letters: true) }

    /// The box, outline and shadow at the style's opacity, without the letters — the canvas
    /// draws this behind the live text editor, whose NSTextView draws the letters on top.
    func drawDecorations() {
        guard style.textBackgroundMode != .none || style.textOutline else { return }
        guard style.opacity < 1, let ctx = NSGraphicsContext.current?.cgContext else { draw(letters: false); return }
        ctx.saveGState()
        ctx.setAlpha(style.opacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        draw(letters: false)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Back to front: box, outline, letters. With a shadow, all of it is drawn as one layer that
    /// casts a single soft shadow (so a boxed text's shadow falls from the box).
    private func draw(letters: Bool) {
        let size = layoutSize
        let ctx = NSGraphicsContext.current?.cgContext
        if style.textShadow, let ctx { beginShadow(ctx) }
        defer { if style.textShadow, let ctx { ctx.endTransparencyLayer(); ctx.restoreGState() } }
        if let fill = backgroundFill {
            let pad = backgroundInsets
            let box = CGRect(origin: origin, size: size).insetBy(dx: -pad.width, dy: -pad.height)
            let r = min(style.textBackgroundCornerRadius, box.width / 2, box.height / 2)
            fill.nsColor.setFill()
            NSBezierPath(roundedRect: box, xRadius: r, yRadius: r).fill()
        }
        // +1 slack on a free label so float rounding can't wrap its last word.
        let rect = CGRect(origin: origin, size: CGSize(width: wrapWidth ?? size.width + 1, height: size.height + 1))
        if style.textOutline {
            ctx?.saveGState()
            ctx?.setLineJoin(.round)   // no miter spikes on sharp letter corners
            NSAttributedString(string: text, attributes: Self.outlineAttributes(for: style))
                .draw(with: rect, options: Self.drawOptions)
            ctx?.restoreGState()
        }
        if letters {
            NSAttributedString(string: text, attributes: Self.attributes(for: style))
                .draw(with: rect, options: Self.drawOptions)
        }
    }

    private var backgroundFill: RGBAColor? {
        switch style.textBackgroundMode {
        case .none: return nil
        case .solid: return style.textBackgroundColor
        case .auto: return TextChip.autoColor(forText: style.strokeColor)
        }
    }

    /// A soft shadow sized from the font (offset 5%, blur 15% of the size, 45% black), falling
    /// down in the image. Shadow offset and blur ignore the CTM, so they are mapped through it —
    /// the canvas's zoom and flip and the renderer's flip all end up with the same shadow in
    /// image pixels. Device space is y-down but the shadow offset is y-up, hence the minus
    /// (verified by `shadowFallsBelowTheText` / `canvasShadowFallsDownwardToo`).
    private func beginShadow(_ ctx: CGContext) {
        ctx.saveGState()
        let t = ctx.userSpaceToDeviceSpaceTransform
        let deviceScale = sqrt(abs(t.a * t.d - t.b * t.c))
        let drop = max(1, style.fontSize * 0.05)
        ctx.setShadow(offset: CGSize(width: t.c * drop, height: -t.d * drop),
                      blur: max(2, style.fontSize * 0.15) * deviceScale,
                      color: CGColor(gray: 0, alpha: 0.45))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    }
}

extension TextAlign {
    var nsAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}
