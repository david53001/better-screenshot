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

    /// Font + colour + alignment for `style` at `fontSize` points — shared with the
    /// canvas's inline editor (which passes a view-scaled size) so both lay out alike.
    public static func attributes(for style: AnnotationStyle,
                                  fontSize: CGFloat? = nil) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.alignment = style.textAlignment.nsAlignment
        return [.font: TextFont.font(family: style.fontFamily, size: fontSize ?? style.fontSize,
                                     bold: style.fontBold, italic: style.fontItalic),
                .foregroundColor: style.strokeColor.nsColor,
                .paragraphStyle: para]
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
    public func boundingBox() -> CGRect {
        CGRect(origin: origin, size: layoutSize)
    }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.origin = CGPoint(x: origin.x + d.dx, y: origin.y + d.dy); return c
    }
    public func draw() {
        let size = layoutSize
        if style.textBackground {
            let textRect = CGRect(origin: origin, size: size)
            let chipRect = textRect.insetBy(dx: -TextChip.horizontalPadding, dy: -TextChip.verticalPadding)
            let sc = style.strokeColor
            let luminance = 0.2126 * sc.r + 0.7152 * sc.g + 0.0722 * sc.b
            let chipColor = TextChip.chipIsDark(forTextLuminance: Double(luminance))
                ? NSColor(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1A / 255, alpha: 1)
                : NSColor(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF6 / 255, alpha: 1)
            let path = NSBezierPath(roundedRect: chipRect, xRadius: TextChip.cornerRadius, yRadius: TextChip.cornerRadius)
            chipColor.setFill()
            path.fill()
        }
        // +1 slack on a free label so float rounding can't wrap its last word.
        let width = wrapWidth ?? size.width + 1
        NSAttributedString(string: text, attributes: Self.attributes(for: style))
            .draw(with: CGRect(origin: origin, size: CGSize(width: width, height: size.height + 1)),
                  options: Self.drawOptions)
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
