import AppKit
import TestKit
@testable import TourKit

// WCAG 2.x contrast (same formula as OverlayKit's `SRGB.swift`, copied: TourKit doesn't depend on it).
private func expand(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }

/// `colour` composited over `background` (both sRGB), then its relative luminance.
private func luminance(_ colour: NSColor, over background: NSColor) -> CGFloat {
    let f = colour.usingColorSpace(.sRGB)!, b = background.usingColorSpace(.sRGB)!
    let a = f.alphaComponent
    func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x * a + y * (1 - a) }
    return 0.2126 * expand(mix(f.redComponent, b.redComponent))
        + 0.7152 * expand(mix(f.greenComponent, b.greenComponent))
        + 0.0722 * expand(mix(f.blueComponent, b.blueComponent))
}

private func contrast(_ text: NSColor, on background: NSColor) -> CGFloat {
    let lt = luminance(text, over: background), lb = luminance(background, over: .black)
    return (max(lt, lb) + 0.05) / (min(lt, lb) + 0.05)
}

/// Every piece of text the tag draws, on what it's drawn on (review 2026-09-26, T1: all were < 4.5:1).
private let pairs: [(name: String, text: NSColor, background: NSColor)] = [
    ("title / body / done label on the tag", TagStyle.textColour, TagStyle.tourRed),
    ("counter + Skip Tour on the tag", TagStyle.secondaryTextColour, TagStyle.tourRed),
    ("Skip Step (outline button) on the tag", TagStyle.textColour, TagStyle.tourRed),
    ("Next / Done on the white capsule", TagStyle.filledButtonText, TagStyle.filledButtonFill),
]

let tagContrastTests: [TestCase] = [
    TestCase("everyTagTextClearsWCAGAA") { t in
        for p in pairs {
            let ratio = contrast(p.text, on: p.background)
            t.isTrue(ratio >= 4.5, "\(p.name): \(String(format: "%.2f", ratio)):1 < 4.5:1")
        }
    },
    TestCase("theContrastMathMatchesKnownValues") { t in
        t.approxEqual(Double(contrast(.white, on: .black)), 21, tol: 0.01)
        // The old tag: white on #FF453A was 3.41:1 and 80 % white 2.64:1 (the review's numbers).
        let old = NSColor(srgbRed: 1, green: 69 / 255, blue: 58 / 255, alpha: 1)
        t.approxEqual(Double(contrast(.white, on: old)), 3.41, tol: 0.01)
        t.approxEqual(Double(contrast(NSColor.white.withAlphaComponent(0.8), on: old)), 2.64, tol: 0.01)
        t.approxEqual(Double(contrast(.white, on: TagStyle.tourRed)), 5.53, tol: 0.01)
    },
]
