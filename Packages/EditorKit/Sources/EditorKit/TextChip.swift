import CoreGraphics

/// The box behind a text annotation (`AnnotationStyle.textBackgroundMode`).
public enum TextChip {
    /// Light text (luminance > 0.5) gets a dark chip; dark text gets a light chip.
    public static func chipIsDark(forTextLuminance lum: Double) -> Bool { lum > 0.5 }

    /// The `.auto` box colour for `text`: near-black #18181A or near-white #F4F4F6.
    public static func autoColor(forText text: RGBAColor) -> RGBAColor {
        let luminance = 0.2126 * text.r + 0.7152 * text.g + 0.0722 * text.b
        return chipIsDark(forTextLuminance: Double(luminance))
            ? RGBAColor(r: 0x18 / 255, g: 0x18 / 255, b: 0x1A / 255, a: 1)
            : RGBAColor(r: 0xF4 / 255, g: 0xF4 / 255, b: 0xF6 / 255, a: 1)
    }

    /// How far the box extends past the text's line box: `padding` left/right, half of it
    /// top/bottom (line boxes already carry the font's leading). 6 → 6 × 3, the original chip.
    public static func insets(padding: CGFloat) -> CGSize {
        CGSize(width: padding, height: padding / 2)
    }
}
