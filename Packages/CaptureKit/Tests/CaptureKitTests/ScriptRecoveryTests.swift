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
]
