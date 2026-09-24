import CoreGraphics

/// Horizontal alignment of a text annotation's lines within its box.
public enum TextAlign: String, Codable, CaseIterable {
    case left, center, right
}

public struct AnnotationStyle: Equatable, Codable {
    public var strokeColor: RGBAColor
    public var fillColor: RGBAColor
    public var lineWidth: CGFloat
    public var fontSize: CGFloat
    public var textBackground: Bool
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

    // Redaction (v3 Part 3; ranges + helpers in RedactionAnnotations.swift). Defaults here so
    // older persisted styles decode and the memberwise init needn't list them.
    /// Blur / Pixelate — a redaction's mode (the active tool picks it for new ones).
    public var redactionMode: RedactionMode = .blur
    /// Blur radius, image px (`blurRadiusRange`).
    public var blurRadius: CGFloat = 12
    /// Pixelate block size, image px (`pixelSizeRange`).
    public var pixelSize: CGFloat = 12
    /// The Highlighter tool's own sticky colour / width / opacity (HighlighterAnnotation.swift).
    public var highlighterPen: HighlighterPen = .default

    public init(strokeColor: RGBAColor, fillColor: RGBAColor,
                lineWidth: CGFloat, fontSize: CGFloat, textBackground: Bool = false,
                fontFamily: String = TextFont.system, fontBold: Bool = true,
                fontItalic: Bool = false, textAlignment: TextAlign = .left, opacity: CGFloat = 1) {
        self.strokeColor = strokeColor; self.fillColor = fillColor
        self.lineWidth = lineWidth; self.fontSize = fontSize
        self.textBackground = textBackground
        self.fontFamily = fontFamily; self.fontBold = fontBold
        self.fontItalic = fontItalic; self.textAlignment = textAlignment
        self.opacity = opacity
    }

    private enum CodingKeys: String, CodingKey {
        case strokeColor, fillColor, lineWidth, fontSize, textBackground
        case fontFamily, fontBold, fontItalic, textAlignment, opacity
        case redactionMode, blurRadius, pixelSize, highlighterPen
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strokeColor = try container.decode(RGBAColor.self, forKey: .strokeColor)
        fillColor = try container.decode(RGBAColor.self, forKey: .fillColor)
        lineWidth = try container.decode(CGFloat.self, forKey: .lineWidth)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        textBackground = try container.decodeIfPresent(Bool.self, forKey: .textBackground) ?? false
        // Text-font fields arrived later; a style persisted before them keeps today's look.
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? TextFont.system
        fontBold = try container.decodeIfPresent(Bool.self, forKey: .fontBold) ?? true
        fontItalic = try container.decodeIfPresent(Bool.self, forKey: .fontItalic) ?? false
        textAlignment = (try? container.decodeIfPresent(TextAlign.self, forKey: .textAlignment)) ?? .left
        // Opacity arrived in v3; older styles are opaque. Clamped so a bad value can't hide objects.
        let o = try container.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? 1
        opacity = min(max(o, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        // Part 3 fields: missing → defaults; out-of-range strengths are clamped.
        redactionMode = (try? container.decodeIfPresent(RedactionMode.self, forKey: .redactionMode)) ?? .blur
        blurRadius = Self.clamp(try container.decodeIfPresent(CGFloat.self, forKey: .blurRadius) ?? 12, Self.blurRadiusRange)
        pixelSize = Self.clamp(try container.decodeIfPresent(CGFloat.self, forKey: .pixelSize) ?? 12, Self.pixelSizeRange)
        highlighterPen = ((try? container.decodeIfPresent(HighlighterPen.self, forKey: .highlighterPen)) ?? .default).clamped
    }

    static func clamp(_ v: CGFloat, _ r: ClosedRange<CGFloat>) -> CGFloat { min(max(v, r.lowerBound), r.upperBound) }

    public static let `default` = AnnotationStyle(
        strokeColor: RGBAColor(r: 1, g: 0.23, b: 0.19, a: 1),
        fillColor: RGBAColor(r: 1, g: 0.23, b: 0.19, a: 0.25),
        lineWidth: 4, fontSize: 24)
}
