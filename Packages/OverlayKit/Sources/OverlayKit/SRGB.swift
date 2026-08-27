import Foundation

/// WCAG 2.x sRGB primitives. Contrast is only meaningful on *linear* light, so every
/// luminance here gamma-expands first — unlike the legacy `averageLuminance`, which
/// weights the gamma-encoded bytes and therefore overstates dark pixels.
public enum SRGB {
    /// Gamma-expand one sRGB-encoded channel (0...1) to linear.
    public static func expand(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Inverse of `expand`.
    public static func encode(_ linear: Double) -> Double {
        linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1.0 / 2.4) - 0.055
    }

    /// WCAG 2.x relative luminance (0...1) of an sRGB byte triple.
    public static func relativeLuminance(r: UInt8, g: UInt8, b: UInt8) -> Double {
        0.2126 * expand(Double(r) / 255.0)
            + 0.7152 * expand(Double(g) / 255.0)
            + 0.0722 * expand(Double(b) / 255.0)
    }

    /// WCAG contrast ratio (1...21) between two relative luminances.
    public static func contrastRatio(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
