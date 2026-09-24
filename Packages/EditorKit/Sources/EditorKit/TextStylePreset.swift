import CoreGraphics

/// One-click text looks — the chips of the side panel's Styles section. A preset sets only the
/// text look (colour, font, box, effects; Title and Subtle also the size): alignment, opacity,
/// line width and the box width are kept, and it applies to the selected text like any style edit.
public enum TextStylePreset: String, CaseIterable {
    case label, callout, note, code, title, subtle

    public var displayName: String { rawValue.capitalized }

    public var tooltip: String {
        switch self {
        case .label: return "Label — bold white text on a black box"
        case .callout: return "Callout — bold white text on a red box"
        case .note: return "Note — black text on a yellow box"
        case .code: return "Code — light monospaced text on a dark box"
        case .title: return "Title — 48 pt bold, no box (keeps the colour)"
        case .subtle: return "Subtle — 18 pt regular grey, no box"
        }
    }

    /// The fields a preset sets. nil colour / size = keep the current one.
    struct Look {
        var color: RGBAColor?
        var size: CGFloat?
        var family = TextFont.system
        var bold: Bool
        /// Solid box colour, padding, corner radius; nil = no box.
        var box: (color: RGBAColor, padding: CGFloat, radius: CGFloat)?
    }

    var look: Look {
        let white = RGBAColor(r: 1, g: 1, b: 1, a: 1), black = RGBAColor(r: 0, g: 0, b: 0, a: 1)
        switch self {
        case .label:
            return Look(color: white, bold: true, box: (RGBAColor(r: 0, g: 0, b: 0, a: 0.8), 6, 4))
        case .callout:
            return Look(color: white, bold: true, box: (RGBAColor(r: 1, g: 0.27, b: 0.23, a: 1), 8, 6))
        case .note:
            return Look(color: black, bold: false, box: (RGBAColor(r: 1, g: 0.84, b: 0.04, a: 1), 8, 2))
        case .code:
            return Look(color: RGBAColor(r: 0.90, g: 0.92, b: 0.95, a: 1), family: TextFont.mono, bold: false,
                        box: (RGBAColor(r: 0.12, g: 0.13, b: 0.15, a: 1), 6, 4))
        case .title:
            return Look(color: nil, size: 48, bold: true, box: nil)
        case .subtle:
            return Look(color: RGBAColor(r: 0.56, g: 0.56, b: 0.58, a: 1), size: 18, bold: false, box: nil)
        }
    }

    public func apply(to s: inout AnnotationStyle) {
        let l = look
        if let c = l.color {
            s.strokeColor = c
            s.fillColor = RGBAColor(r: c.r, g: c.g, b: c.b, a: 0.25)   // as a colour swatch sets it
        }
        if let size = l.size { s.fontSize = size }
        s.fontFamily = l.family
        s.fontBold = l.bold
        s.fontItalic = false
        s.textUnderline = false
        s.textStrikethrough = false
        s.textOutline = false
        s.textShadow = false
        if let box = l.box {
            s.textBackgroundMode = .solid
            s.textBackgroundColor = box.color
            s.textBackgroundPadding = box.padding
            s.textBackgroundCornerRadius = box.radius
        } else {
            s.textBackgroundMode = .none
        }
    }

    /// True when `style` already has this look (the panel highlights that chip).
    public func isApplied(to style: AnnotationStyle) -> Bool {
        var s = style
        apply(to: &s)
        return s == style
    }
}
