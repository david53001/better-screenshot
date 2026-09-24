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

    public init(strokeColor: RGBAColor, fillColor: RGBAColor,
                lineWidth: CGFloat, fontSize: CGFloat, textBackground: Bool = false,
                fontFamily: String = TextFont.system, fontBold: Bool = true,
                fontItalic: Bool = false, textAlignment: TextAlign = .left) {
        self.strokeColor = strokeColor; self.fillColor = fillColor
        self.lineWidth = lineWidth; self.fontSize = fontSize
        self.textBackground = textBackground
        self.fontFamily = fontFamily; self.fontBold = fontBold
        self.fontItalic = fontItalic; self.textAlignment = textAlignment
    }

    private enum CodingKeys: String, CodingKey {
        case strokeColor, fillColor, lineWidth, fontSize, textBackground
        case fontFamily, fontBold, fontItalic, textAlignment
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
    }

    public static let `default` = AnnotationStyle(
        strokeColor: RGBAColor(r: 1, g: 0.23, b: 0.19, a: 1),
        fillColor: RGBAColor(r: 1, g: 0.23, b: 0.19, a: 0.25),
        lineWidth: 4, fontSize: 24)
}
