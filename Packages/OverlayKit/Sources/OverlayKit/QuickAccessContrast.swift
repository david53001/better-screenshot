import Foundation

public enum ContrastTone: Equatable { case dark, light }

public struct ContrastPalette: Equatable {
    public let glyphARGB: UInt32
    public let hoverARGB: UInt32
    public let pressedARGB: UInt32
    public let scrimIsWhite: Bool
}

/// A glyph tone plus the scrim strength that makes it readable over the whole band.
public struct ContrastPlan: Equatable {
    public let tone: ContrastTone
    public let palette: ContrastPalette
    public let scrimAlpha: Double   // 0...1 — alpha to HOLD flat across the button row
}

public enum QuickAccessContrast {
    /// The darkest and brightest backgrounds the button row has to survive.
    public struct BandExtremes: Equatable {
        public let dark: Double      // low-percentile relative luminance
        public let bright: Double    // high-percentile relative luminance
        public init(dark: Double, bright: Double) {
            self.dark = dark
            self.bright = bright
        }
    }

    public static func palette(for tone: ContrastTone) -> ContrastPalette {
        switch tone {
        case .dark:  return ContrastPalette(glyphARGB: 0xFF18181A, hoverARGB: 0x24000000, pressedARGB: 0x3D000000, scrimIsWhite: true)
        case .light: return ContrastPalette(glyphARGB: 0xFFF4F4F6, hoverARGB: 0x2BFFFFFF, pressedARGB: 0x45FFFFFF, scrimIsWhite: false)
        }
    }

    public static let targetContrastRatio = 4.5
    public static let minScrimAlpha = 0.18   // aesthetic floor; keeps the current look on already-dark shots
    public static let maxScrimAlpha = 0.85   // never fully hide the picture

    /// Minimum scrim alpha needed so a background of relative luminance `bg`,
    /// composited under a `scrimIsWhite ? white : black` scrim, reaches
    /// `targetContrastRatio` against a glyph of relative luminance `glyph`.
    /// 0 when already sufficient; `maxScrimAlpha` when unreachable.
    public static func requiredScrimAlpha(backgroundLuminance bg: Double,
                                          glyphLuminance glyph: Double,
                                          scrimIsWhite: Bool) -> Double {
        // The scrim composites in gamma-encoded space, so solve there and treat the
        // background as an equivalent gray of that encoded value.
        let x = SRGB.encode(bg)
        let alpha: Double
        if scrimIsWhite {
            // A white scrim serves a dark glyph: push the background UP past Lmin.
            let target = SRGB.encode(targetContrastRatio * (glyph + 0.05) - 0.05)
            if target > 1 { return maxScrimAlpha }   // even pure white isn't bright enough
            if x >= 1 { return 0 }
            alpha = (target - x) / (1 - x)
        } else {
            // A black scrim serves a light glyph: push the background DOWN below Lmax.
            let limit = (glyph + 0.05) / targetContrastRatio - 0.05
            if limit <= 0 { return maxScrimAlpha }   // even pure black isn't dark enough
            if x <= 0 { return 0 }
            alpha = 1 - SRGB.encode(limit) / x
        }
        return min(max(alpha, 0), maxScrimAlpha)
    }

    /// Picks the tone that needs the LESS aggressive scrim over the whole band, so
    /// both the darkest and the brightest pixel behind the buttons stay readable —
    /// which a mean-luminance threshold cannot promise on a bimodal strip.
    public static func plan(for extremes: BandExtremes) -> ContrastPlan {
        let light = palette(for: .light)
        let dark = palette(for: .dark)
        // Light glyphs are hurt by the brightest pixel, dark glyphs by the darkest.
        let aLight = requiredScrimAlpha(backgroundLuminance: extremes.bright,
                                        glyphLuminance: luminance(of: light),
                                        scrimIsWhite: light.scrimIsWhite)
        let aDark = requiredScrimAlpha(backgroundLuminance: extremes.dark,
                                       glyphLuminance: luminance(of: dark),
                                       scrimIsWhite: dark.scrimIsWhite)
        // Ties go to .light, which is the app's long-standing default look.
        let useLight = aLight <= aDark
        let alpha = min(max(useLight ? aLight : aDark, minScrimAlpha), maxScrimAlpha)
        return ContrastPlan(tone: useLight ? .light : .dark,
                            palette: useLight ? light : dark,
                            scrimAlpha: alpha)
    }

    private static func luminance(of palette: ContrastPalette) -> Double {
        let argb = palette.glyphARGB
        return SRGB.relativeLuminance(r: UInt8((argb >> 16) & 0xFF),
                                      g: UInt8((argb >> 8) & 0xFF),
                                      b: UInt8(argb & 0xFF))
    }
}
