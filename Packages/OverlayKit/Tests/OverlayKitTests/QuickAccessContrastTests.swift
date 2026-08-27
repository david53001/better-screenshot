import TestKit
@testable import OverlayKit

/// Relative luminance of `bg` after the scrim is alpha-composited over it,
/// mirroring what the card draws (compositing happens in gamma-encoded space).
private func composited(_ bg: Double, scrimIsWhite: Bool, alpha: Double) -> Double {
    let x = SRGB.encode(bg)
    let s = scrimIsWhite ? 1.0 : 0.0
    return SRGB.expand(x * (1 - alpha) + s * alpha)
}

private func glyphLuminance(_ palette: ContrastPalette) -> Double {
    let argb = palette.glyphARGB
    return SRGB.relativeLuminance(r: UInt8((argb >> 16) & 0xFF),
                                  g: UInt8((argb >> 8) & 0xFF),
                                  b: UInt8(argb & 0xFF))
}

/// Asserts the plan lands ≥ 4.5:1 on BOTH ends of the band, unless the alpha
/// saturated — the guarantee is only waived when it is mathematically unreachable.
private func assertReadable(_ t: TestContext, _ extremes: QuickAccessContrast.BandExtremes) {
    let plan = QuickAccessContrast.plan(for: extremes)
    guard plan.scrimAlpha < QuickAccessContrast.maxScrimAlpha else { return }
    let glyph = glyphLuminance(plan.palette)
    for bg in [extremes.dark, extremes.bright] {
        let after = composited(bg, scrimIsWhite: plan.palette.scrimIsWhite, alpha: plan.scrimAlpha)
        let ratio = SRGB.contrastRatio(after, glyph)
        t.isTrue(ratio >= 4.5 - 1e-6,
                 "bg \(bg) of \(extremes) gave \(ratio):1 at alpha \(plan.scrimAlpha)")
    }
}

let quickAccessContrastTests: [TestCase] = [
    TestCase("averageLuminanceWhiteAndBlack") { t in
        let white: [UInt8] = [255,255,255,255, 255,255,255,255]
        t.approxEqual(QuickAccessContrast.averageLuminance(rgba: white, pixelCount: 2), 1.0, tol: 0.001)
        let black: [UInt8] = [0,0,0,255, 0,0,0,255]
        t.approxEqual(QuickAccessContrast.averageLuminance(rgba: black, pixelCount: 2), 0.0, tol: 0.001)
    },
    TestCase("emptyBufferIsZero") { t in
        t.approxEqual(QuickAccessContrast.averageLuminance(rgba: [], pixelCount: 0), 0.0, tol: 0.001)
    },
    TestCase("toneThresholdBoundary") { t in
        t.equal(QuickAccessContrast.tone(forLuminance: 0.57), .light)
        t.equal(QuickAccessContrast.tone(forLuminance: 0.58), .light)
        t.equal(QuickAccessContrast.tone(forLuminance: 0.59), .dark)
    },
    TestCase("paletteForTone") { t in
        let d = QuickAccessContrast.palette(for: .dark)
        t.equal(d.glyphARGB, 0xFF18181A)
        t.equal(d.hoverARGB, 0x24000000)
        t.equal(d.pressedARGB, 0x3D000000)
        t.isTrue(d.scrimIsWhite)
        let l = QuickAccessContrast.palette(for: .light)
        t.equal(l.glyphARGB, 0xFFF4F4F6)
        t.equal(l.hoverARGB, 0x2BFFFFFF)
        t.equal(l.pressedARGB, 0x45FFFFFF)
        t.isFalse(l.scrimIsWhite)
    },
    TestCase("cardSizeSquareImage") { t in
        let s = QuickAccessCardSize.contentSize(imagePixelWidth: 1000, imagePixelHeight: 1000)
        t.approxEqual(Double(s.width), 210, tol: 0.001)
        t.approxEqual(Double(s.height), 210, tol: 0.001)
    },
    TestCase("cardSizeWideClampsToFloor") { t in
        let s = QuickAccessCardSize.contentSize(imagePixelWidth: 2000, imagePixelHeight: 500)
        t.approxEqual(Double(s.height), 150, tol: 0.001)
    },
    TestCase("cardSizeTallClampsToCeiling") { t in
        let s = QuickAccessCardSize.contentSize(imagePixelWidth: 500, imagePixelHeight: 2000)
        t.approxEqual(Double(s.height), 280, tol: 0.001)
    },
    TestCase("cardSizeZeroHeightFallback") { t in
        let s = QuickAccessCardSize.contentSize(imagePixelWidth: 1600, imagePixelHeight: 0)
        t.approxEqual(Double(s.height), min(max(210.0/(16.0/9.0),150),280), tol: 0.001)
    },

    // MARK: sRGB / WCAG primitives

    TestCase("srgbExpandEncodeRoundTrip") { t in
        // Loose at the 0.04045 kink: the two standard thresholds (0.04045 encoded,
        // 0.0031308 linear) are rounded and don't map exactly onto each other,
        // so the piecewise branch can flip on the way back.
        for c in [0.0, 0.002, 0.04045, 0.1, 0.5, 0.9, 1.0] {
            t.approxEqual(SRGB.encode(SRGB.expand(c)), c, tol: 1e-6)
        }
    },
    TestCase("srgbRelativeLuminanceEndpoints") { t in
        t.approxEqual(SRGB.relativeLuminance(r: 255, g: 255, b: 255), 1.0, tol: 1e-9)
        t.approxEqual(SRGB.relativeLuminance(r: 0, g: 0, b: 0), 0.0, tol: 1e-9)
    },
    TestCase("srgbContrastRatioWhiteOnBlackIs21") { t in
        t.approxEqual(SRGB.contrastRatio(1.0, 0.0), 21.0, tol: 1e-9)
    },
    TestCase("srgbContrastRatioIsSymmetric") { t in
        t.approxEqual(SRGB.contrastRatio(0.2, 0.7), SRGB.contrastRatio(0.7, 0.2), tol: 1e-12)
        t.approxEqual(SRGB.contrastRatio(0.4, 0.4), 1.0, tol: 1e-12)
    },

    // MARK: Guaranteed-contrast plan

    TestCase("requiredScrimAlphaWhiteUnderLightGlyph") { t in
        let glyph = glyphLuminance(QuickAccessContrast.palette(for: .light))
        let a = QuickAccessContrast.requiredScrimAlpha(backgroundLuminance: 1.0,
                                                       glyphLuminance: glyph, scrimIsWhite: false)
        t.isTrue(a > 0.55 && a < 0.58, "expected ~0.56, got \(a)")
    },
    TestCase("requiredScrimAlphaBlackUnderLightGlyphIsZero") { t in
        let glyph = glyphLuminance(QuickAccessContrast.palette(for: .light))
        t.approxEqual(QuickAccessContrast.requiredScrimAlpha(backgroundLuminance: 0.0,
                                                             glyphLuminance: glyph,
                                                             scrimIsWhite: false), 0.0, tol: 1e-9)
    },
    TestCase("requiredScrimAlphaBlackUnderDarkGlyph") { t in
        let glyph = glyphLuminance(QuickAccessContrast.palette(for: .dark))
        let a = QuickAccessContrast.requiredScrimAlpha(backgroundLuminance: 0.0,
                                                       glyphLuminance: glyph, scrimIsWhite: true)
        t.isTrue(a > 0.48 && a < 0.52, "expected ~0.50, got \(a)")
    },
    TestCase("requiredScrimAlphaWhiteUnderDarkGlyphIsZero") { t in
        let glyph = glyphLuminance(QuickAccessContrast.palette(for: .dark))
        t.approxEqual(QuickAccessContrast.requiredScrimAlpha(backgroundLuminance: 1.0,
                                                             glyphLuminance: glyph,
                                                             scrimIsWhite: true), 0.0, tol: 1e-9)
    },
    TestCase("planKeepsLightGlyphsOnADarkBand") { t in
        let plan = QuickAccessContrast.plan(for: .init(dark: 0.0, bright: 0.03))
        t.equal(plan.tone, .light)
        t.approxEqual(plan.scrimAlpha, QuickAccessContrast.minScrimAlpha, tol: 1e-9)
    },
    TestCase("planStaysWithinAlphaBounds") { t in
        for e in [QuickAccessContrast.BandExtremes(dark: 0.0, bright: 0.0),
                  .init(dark: 1.0, bright: 1.0),
                  .init(dark: 0.02, bright: 1.0),
                  .init(dark: 0.05, bright: 0.20),
                  .init(dark: 0.30, bright: 0.50),
                  .init(dark: 0.50, bright: 0.90)] {
            let a = QuickAccessContrast.plan(for: e).scrimAlpha
            t.isTrue(a >= QuickAccessContrast.minScrimAlpha && a <= QuickAccessContrast.maxScrimAlpha,
                     "alpha \(a) out of bounds for \(e)")
        }
    },
    TestCase("planGuaranteesContrastAcrossBands") { t in
        assertReadable(t, .init(dark: 0.0, bright: 0.0))
        assertReadable(t, .init(dark: 1.0, bright: 1.0))
        assertReadable(t, .init(dark: 0.05, bright: 0.20))
        assertReadable(t, .init(dark: 0.20, bright: 0.80))
        assertReadable(t, .init(dark: 0.30, bright: 0.50))
        assertReadable(t, .init(dark: 0.50, bright: 0.90))
    },
    TestCase("planRegressionStarfieldWithWhiteHeadline") { t in
        // The measured failure: near-black band plus a white headline at button height.
        // mean = 0.201 made the old code pick white glyphs, which vanished on the headline.
        assertReadable(t, .init(dark: 0.02, bright: 1.0))
    },
]
