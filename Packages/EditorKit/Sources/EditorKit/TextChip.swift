import CoreGraphics
import Foundation

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

    /// WCAG 2.x contrast ratio (1…21) between two colours, ignoring alpha.
    public static func contrastRatio(_ a: RGBAColor, _ b: RGBAColor) -> Double {
        func luminance(_ c: RGBAColor) -> Double {
            func lin(_ v: CGFloat) -> Double {
                let x = Double(min(max(v, 0), 1))
                return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
        }
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Below this an outline doesn't separate from its letters (WCAG's minimum for graphics).
    public static let minOutlineContrast = 3.0

    /// The outline for `text` colour: `current` when it stands out against the letters, else
    /// black or white, whichever contrasts more — so turning Outline on for white text (the
    /// Label / Callout look) doesn't draw a white outline that melts the letters into a blob.
    public static func outlineColor(_ current: RGBAColor, forText text: RGBAColor) -> RGBAColor {
        if contrastRatio(current, text) >= minOutlineContrast { return current }
        let black = RGBAColor(r: 0, g: 0, b: 0, a: 1), white = RGBAColor(r: 1, g: 1, b: 1, a: 1)
        return contrastRatio(black, text) >= contrastRatio(white, text) ? black : white
    }

    /// How far the box extends past the text's line box: `padding` left/right, half of it
    /// top/bottom (line boxes already carry the font's leading). 6 → 6 × 3, the original chip.
    public static func insets(padding: CGFloat) -> CGSize {
        CGSize(width: padding, height: padding / 2)
    }
}
