import CoreGraphics

/// Horizontal alignment of a text annotation's lines within its box.
public enum TextAlign: String, Codable, CaseIterable {
    case left, center, right
}

/// What sits behind a text annotation: nothing, a box in `textBackgroundColor`, or the
/// auto-contrast box (dark or light, whichever stands out against the text colour — `TextChip`).
public enum TextBackgroundMode: String, Codable, CaseIterable {
    case none, solid, auto
}

public struct AnnotationStyle: Equatable, Codable {
    public var strokeColor: RGBAColor
    public var fillColor: RGBAColor
    public var lineWidth: CGFloat
    public var fontSize: CGFloat
    /// A `TextFont` preset ("System", "System Rounded", …) or an installed font family name.
    public var fontFamily: String
    /// Semibold for the system presets (the editor's historical look), Bold for other families.
    public var fontBold: Bool
    public var fontItalic: Bool
    public var textAlignment: TextAlign
    /// Whole-object opacity, `opacityRange` (1 = opaque). Applied as one transparency
    /// layer per object (`Annotation.drawComposited()`), so overlapping parts don't double up.
    public var opacity: CGFloat

    public static let opacityRange: ClosedRange<CGFloat> = 0.1...1

    // Text v2 (v3 Part 2). Defaults = the look before these fields existed.
    /// Replaces the v2 Bool `textBackground` (the auto chip): legacy true decodes to `.auto`.
    public var textBackgroundMode: TextBackgroundMode = .none
    /// The `.solid` box colour.
    public var textBackgroundColor = RGBAColor(r: 0, g: 0, b: 0, a: 0.8)
    /// Box padding (image px) left and right of the text; top and bottom get half (`TextChip.insets`).
    public var textBackgroundPadding: CGFloat = 6
    public var textBackgroundCornerRadius: CGFloat = 4
    public var textUnderline = false
    public var textStrikethrough = false
    /// An edge of `textOutlineWidth` image px around every letter, outside the letter.
    public var textOutline = false
    public var textOutlineColor = RGBAColor(r: 1, g: 1, b: 1, a: 1)
    public var textOutlineWidth: CGFloat = 3
    /// A fixed soft drop shadow under the text and its box (sized from the font size).
    public var textShadow = false

    public static let textBackgroundPaddingRange: ClosedRange<CGFloat> = 0...40
    public static let textBackgroundCornerRadiusRange: ClosedRange<CGFloat> = 0...40
    public static let textOutlineWidthRange: ClosedRange<CGFloat> = 1...20

    public init(strokeColor: RGBAColor, fillColor: RGBAColor,
                lineWidth: CGFloat, fontSize: CGFloat,
                fontFamily: String = TextFont.system, fontBold: Bool = true,
                fontItalic: Bool = false, textAlignment: TextAlign = .left, opacity: CGFloat = 1) {
        self.strokeColor = strokeColor; self.fillColor = fillColor
        self.lineWidth = lineWidth; self.fontSize = fontSize
        self.fontFamily = fontFamily; self.fontBold = fontBold
        self.fontItalic = fontItalic; self.textAlignment = textAlignment
        self.opacity = opacity
    }

    private enum CodingKeys: String, CodingKey {
        case strokeColor, fillColor, lineWidth, fontSize
        case fontFamily, fontBold, fontItalic, textAlignment, opacity
        case textBackgroundMode, textBackgroundColor, textBackgroundPadding, textBackgroundCornerRadius
        case textUnderline, textStrikethrough, textOutline, textOutlineColor, textOutlineWidth, textShadow
    }
    /// Keys only read from older styles.
    private enum LegacyKeys: String, CodingKey { case textBackground }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strokeColor = try container.decode(RGBAColor.self, forKey: .strokeColor)
        fillColor = try container.decode(RGBAColor.self, forKey: .fillColor)
        lineWidth = try container.decode(CGFloat.self, forKey: .lineWidth)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        // Text-font fields arrived later; a style persisted before them keeps today's look.
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? TextFont.system
        fontBold = try container.decodeIfPresent(Bool.self, forKey: .fontBold) ?? true
        fontItalic = try container.decodeIfPresent(Bool.self, forKey: .fontItalic) ?? false
        textAlignment = (try? container.decodeIfPresent(TextAlign.self, forKey: .textAlignment)) ?? .left
        // Opacity arrived in v3; older styles are opaque. Clamped so a bad value can't hide objects.
        let o = try container.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? 1
        opacity = min(max(o, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        // Text v2: missing keys keep the defaults above. Before the mode, a Bool turned on the auto chip.
        if let mode = try? container.decodeIfPresent(TextBackgroundMode.self, forKey: .textBackgroundMode) {
            textBackgroundMode = mode
        } else if try decoder.container(keyedBy: LegacyKeys.self)
                    .decodeIfPresent(Bool.self, forKey: .textBackground) == true {
            textBackgroundMode = .auto
        }
        if let c = try container.decodeIfPresent(RGBAColor.self, forKey: .textBackgroundColor) { textBackgroundColor = c }
        if let p = try container.decodeIfPresent(CGFloat.self, forKey: .textBackgroundPadding) {
            textBackgroundPadding = p.clamped(to: Self.textBackgroundPaddingRange)
        }
        if let r = try container.decodeIfPresent(CGFloat.self, forKey: .textBackgroundCornerRadius) {
            textBackgroundCornerRadius = r.clamped(to: Self.textBackgroundCornerRadiusRange)
        }
        textUnderline = try container.decodeIfPresent(Bool.self, forKey: .textUnderline) ?? false
        textStrikethrough = try container.decodeIfPresent(Bool.self, forKey: .textStrikethrough) ?? false
        textOutline = try container.decodeIfPresent(Bool.self, forKey: .textOutline) ?? false
        if let c = try container.decodeIfPresent(RGBAColor.self, forKey: .textOutlineColor) { textOutlineColor = c }
        if let w = try container.decodeIfPresent(CGFloat.self, forKey: .textOutlineWidth) {
            textOutlineWidth = w.clamped(to: Self.textOutlineWidthRange)
        }
        textShadow = try container.decodeIfPresent(Bool.self, forKey: .textShadow) ?? false
    }

    public static let `default` = AnnotationStyle(
        strokeColor: RGBAColor(r: 1, g: 0.23, b: 0.19, a: 1),
        fillColor: RGBAColor(r: 1, g: 0.23, b: 0.19, a: 0.25),
        lineWidth: 4, fontSize: 24)
}

fileprivate extension CGFloat {
    func clamped(to r: ClosedRange<CGFloat>) -> CGFloat { Swift.min(Swift.max(self, r.lowerBound), r.upperBound) }
}
