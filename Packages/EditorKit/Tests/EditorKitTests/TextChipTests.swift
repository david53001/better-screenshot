import TestKit
@testable import EditorKit

let textChipTests: [TestCase] = [
    TestCase("darkChipBehindLightText") { t in t.isTrue(TextChip.chipIsDark(forTextLuminance: 0.9)) },
    TestCase("lightChipBehindDarkText") { t in t.isFalse(TextChip.chipIsDark(forTextLuminance: 0.1)) },
    TestCase("contrastRatioIsWCAG") { t in
        let white = RGBAColor(r: 1, g: 1, b: 1, a: 1), black = RGBAColor(r: 0, g: 0, b: 0, a: 1)
        t.approxEqual(TextChip.contrastRatio(white, black), 21, tol: 0.01)
        t.approxEqual(TextChip.contrastRatio(black, white), 21, tol: 0.01)
        t.approxEqual(TextChip.contrastRatio(white, white), 1, tol: 1e-9)
        // Preset red (1, 0.27, 0.23): ≈ 3.4 against white, ≈ 6.2 against black.
        t.approxEqual(TextChip.contrastRatio(AnnotationStyle.defaultRed, white), 3.4, tol: 0.1)
        t.approxEqual(TextChip.contrastRatio(AnnotationStyle.defaultRed, black), 6.2, tol: 0.1)
    },
    TestCase("outlineContrastsWithTheTextColour") { t in
        let white = RGBAColor(r: 1, g: 1, b: 1, a: 1), black = RGBAColor(r: 0, g: 0, b: 0, a: 1)
        let yellow = RGBAColor(r: 1, g: 0.84, b: 0.04, a: 1), blue = RGBAColor(r: 0.04, g: 0.52, b: 1, a: 1)
        // The default white outline on white text (Label / Callout) becomes black…
        t.isTrue(TextChip.outlineColor(white, forText: white) == black, "white text → black outline")
        t.isTrue(TextChip.outlineColor(white, forText: yellow) == black, "yellow text → black outline")
        t.isTrue(TextChip.outlineColor(black, forText: black) == white, "black text → white outline")
        // …but an outline that already stands out is the user's choice and is kept.
        t.isTrue(TextChip.outlineColor(white, forText: AnnotationStyle.defaultRed) == white, "red text keeps white")
        t.isTrue(TextChip.outlineColor(blue, forText: white) == blue, "blue on white text is kept")
        t.isTrue(TextChip.outlineColor(black, forText: white) == black)
    },
]
