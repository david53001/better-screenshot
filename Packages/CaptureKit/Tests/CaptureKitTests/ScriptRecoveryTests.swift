import TestKit
import AppKit
import CoreGraphics
@testable import CaptureKit

private func glyph(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> ScriptRecovery.Glyph {
    ScriptRecovery.Glyph(box: CGRect(x: x, y: y, width: w, height: h), blobs: [])
}

private func measuredLine(_ glyphs: [ScriptRecovery.Glyph], cap: CGFloat, baseline: CGFloat) -> ScriptRecovery.Line {
    ScriptRecovery.Line(glyphs: glyphs, blobs: [], map: InkMap(width: 1, height: 1, ink: [false]),
                        capHeight: cap, baseline: baseline)
}

/// Black rectangles on white, given top-left-origin pixel rects.
private func inkImage(width: Int, height: Int, _ rects: [CGRect]) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setFillColor(gray: 0, alpha: 1)
    for r in rects { ctx.fill(CGRect(x: r.minX, y: CGFloat(height) - r.maxY, width: r.width, height: r.height)) }
    return ctx.makeImage()!
}

let scriptRecoveryTests: [TestCase] = [
    TestCase("scriptRunsUseUnicodeWhereItExists") { t in
        t.equal(ScriptRecovery.script("2", superscript: true), "²")
        t.equal(ScriptRecovery.script("n+1", superscript: true), "ⁿ⁺¹")
        t.equal(ScriptRecovery.script("-3", superscript: true), "⁻³")
        t.equal(ScriptRecovery.script("1", superscript: false), "₁")
        t.equal(ScriptRecovery.script("n", superscript: false), "ₙ")
        // No Unicode superscript π, no subscript q or b.
        t.equal(ScriptRecovery.script("iπ", superscript: true), "^(iπ)")
        t.equal(ScriptRecovery.script("q", superscript: false), "_q")
        t.equal(ScriptRecovery.script("ab", superscript: false), "_(ab)")
    },
    TestCase("raisedAndLoweredGlyphsAreJudgedAgainstTheirBase") { t in
        // x ² + a ₁ with the baseline at y = 40.
        var line = measuredLine([
            glyph(0, 20, 20, 20),   // x
            glyph(22, 6, 12, 16),   // ² — bottom well above x's
            glyph(40, 22, 16, 16),  // + — on the line
            glyph(60, 20, 18, 20),  // a
            glyph(80, 30, 10, 16),  // ₁ — drops below the baseline
            glyph(95, 36, 4, 7),    // , — too small to be a script
        ], cap: 16, baseline: 40)
        t.isTrue(ScriptRecovery.classify(&line))
        t.equal(line.glyphs.map { $0.kind }, [.normal, .sup, .normal, .normal, .sub, .normal])
    },
    TestCase("aDescenderIsNotASubscript") { t in
        // H y: the y dips below the line but is full size.
        var line = measuredLine([glyph(0, 0, 20, 28), glyph(22, 8, 18, 28)], cap: 28, baseline: 28)
        t.isFalse(ScriptRecovery.classify(&line))
    },
    TestCase("wordsSplitAtTheWidestGaps") { t in
        let glyphs = [glyph(0, 0, 10, 10), glyph(12, 0, 10, 10), glyph(40, 0, 10, 10), glyph(52, 0, 10, 10)]
        t.equal(ScriptRecovery.segment(glyphs, into: 2) ?? [], [[0, 1], [2, 3]])
        t.equal(ScriptRecovery.segment(glyphs, into: 1) ?? [], [[0, 1, 2, 3]])
        t.isNil(ScriptRecovery.segment(glyphs, into: 5))
    },
    TestCase("alignTakesOnlyTheScriptsFromTheReread") { t in
        // First read `Tr?,` (π → T, ² → ?), re-read `nir2,` (π → ni): the
        // right-hand side agrees, so the ² comes from the re-read.
        let aligned = ScriptRecovery.align(Array("nir2,"), to: Array("Tr?,"), kinds: [.normal, .normal, .sup, .normal])
        t.equal(aligned.map { String($0) }, "Tr2,")
        t.isNil(ScriptRecovery.align(Array("abc"), to: Array("xy?"), kinds: [.normal, .normal, .sup]))
    },
    TestCase("theGuardKeepsVisionsFullSizeCharacters") { t in
        // Repairs only go one way: `0` → `O` next to a subscript, not `O` → `0`;
        // an x-height capital lowercased, never the reverse.
        t.isTrue(ScriptRecovery.isFaithful(Array("CO"), kinds: [.normal, .normal], structure: [false, false], to: Array("C0")))
        t.isFalse(ScriptRecovery.isFaithful(Array("C0"), kinds: [.normal, .normal], structure: [false, false], to: Array("CO")))
        t.isTrue(ScriptRecovery.isFaithful(Array("x2"), kinds: [.normal, .sup], structure: [false, false], to: Array("X2")))
        t.isFalse(ScriptRecovery.isFaithful(Array("nr2"), kinds: [.normal, .normal, .sup], structure: [false, false, false],
                                            to: Array("Tr?")))
    },
    TestCase("aScriptDigitInsideANumberIsAnOldStyleFigure") { t in
        // `5,¹40` is Georgia's old-style 1; `log₂8` hangs off a letter.
        t.isFalse(ScriptRecovery.isFaithful(Array("5,140"), kinds: [.normal, .normal, .sup, .normal, .normal],
                                            structure: [false, false, false, false, false], to: Array("5,140")))
        t.isTrue(ScriptRecovery.isFaithful(Array("log28"), kinds: [.normal, .normal, .normal, .sub, .normal],
                                           structure: [false, false, false, false, false], to: Array("log,8")))
    },
    TestCase("aShakyReadMayChangeButNotBeyondRecognition") { t in
        t.isTrue(ScriptRecovery.isFaithful(Array("2H2O"), kinds: [.normal, .normal, .sub, .normal],
                                           structure: [false, false, false, false], to: Array("2112O"), confident: false))
        t.isFalse(ScriptRecovery.isFaithful(Array("abcd"), kinds: [.normal, .normal, .normal, .normal],
                                            structure: [false, false, false, false], to: Array("wxyz"), confident: false))
        t.equal(ScriptRecovery.distance("kitten", "sitting"), 3)
        t.equal(ScriptRecovery.distance("", "abc"), 3)
    },
    TestCase("logLookAlikesBeforeASubscriptAreLog") { t in
        t.equal(ScriptRecovery.repairingLog("10g₂8 = 3"), "log₂8 = 3")
        t.equal(ScriptRecovery.repairingLog("l0gₐx + 1og(y)"), "logₐx + log(y)")
        t.equal(ScriptRecovery.repairingLog("add 10g of salt"), "add 10g of salt")
        t.equal(ScriptRecovery.repairingLog("and In e³ = 3, In(x) = 0"), "and ln e³ = 3, ln(x) = 0")
        t.equal(ScriptRecovery.repairingLog("In a sense, In (b) we see"), "In a sense, In (b) we see")
    },
    TestCase("touchingItalicsTakeTwoCharactersAndScriptsOne") { t in
        // `2x³ + 1`: the 2 and the x touch (one wide glyph), ³ is raised.
        var glyphs = [glyph(0, 10, 20, 20), glyph(21, 4, 7, 12), glyph(34, 14, 10, 12), glyph(50, 10, 10, 20)]
        glyphs[1].kind = .sup
        let line = measuredLine(glyphs, cap: 20, baseline: 30)
        t.equal(ScriptRecovery.alignment([0, 1, 2, 3], Array("2x3+1"), spaces: [], line) ?? [], [0..<2, 2..<3, 3..<4, 4..<5])
        // Vision dropped the raised glyph: it gets nothing, to be read again.
        // (Known limit: when a *touching* pair precedes the dropped script, as in
        // `2x³` read `2x`, the cheaper assignment puts the x on the script glyph.)
        // `x²+1` read `x+1`:
        t.equal(ScriptRecovery.alignment([0, 1, 2, 3], Array("x+1"), spaces: [], measuredLine(
            [glyph(0, 14, 10, 16), glyph(11, 4, 7, 12), glyph(24, 14, 10, 12), glyph(40, 10, 10, 20)].enumerated().map { i, g in
                var g = g; if i == 1 { g.kind = .sup }; return g }, cap: 20, baseline: 30)) ?? [], [0..<1, 1..<1, 1..<2, 2..<3])
    },
    TestCase("aScriptTouchingItsLetterIsCutOff") { t in
        // Three capitals (20 tall, baseline y = 40), then an x-height block with
        // a raised block run into its top right: `x²` printed as one blob.
        let letters = [10, 30, 50].map { CGRect(x: $0, y: 20, width: 12, height: 20) }
        let image = inkImage(width: 120, height: 60, letters + [CGRect(x: 70, y: 26, width: 12, height: 14),
                                                             CGRect(x: 81, y: 16, width: 8, height: 11)])
        let line = ScriptRecovery.lineGlyphs(rect: CGRect(x: 5, y: 18, width: 100, height: 24), in: image)
        t.equal(line?.glyphs.count, 5)
        t.equal(line?.glyphs.last?.box.minX, 82)
        // Without the raised part rising clear of it, the letter stays whole.
        let hook = inkImage(width: 120, height: 60, letters + [CGRect(x: 70, y: 20, width: 12, height: 20),
                                                            CGRect(x: 81, y: 18, width: 8, height: 6)])
        t.equal(ScriptRecovery.lineGlyphs(rect: CGRect(x: 5, y: 18, width: 100, height: 24), in: hook)?.glyphs.count, 4)
    },
]
