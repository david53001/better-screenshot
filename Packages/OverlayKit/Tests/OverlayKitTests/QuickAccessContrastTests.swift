import TestKit
@testable import OverlayKit

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
]

// MARK: - sRGB / WCAG primitives

let srgbTests: [TestCase] = [
    TestCase("srgbExpandEncodeRoundTrip") { t in
        // Tolerance is loose at the 0.04045 kink: the two standard thresholds
        // (0.04045 encoded, 0.0031308 linear) are rounded and don't map onto
        // each other exactly, so the branch can flip on the way back.
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
]
