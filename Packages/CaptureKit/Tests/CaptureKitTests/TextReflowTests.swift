import TestKit
import CoreGraphics
@testable import CaptureKit

// Geometry is Vision-style normalized (0…1), but with a top-left origin:
// `top` grows downward. Character width ≈ (right - left) / text.count, so the
// fixtures pick widths that make the "does the next word fit?" arithmetic
// unambiguous.
private func line(_ text: String, top: CGFloat, left: CGFloat, right: CGFloat,
                  height: CGFloat = 0.05) -> TextReflow.Line {
    TextReflow.Line(text: text, box: CGRect(x: left, y: top, width: right - left, height: height))
}

let textReflowTests: [TestCase] = [
    TestCase("emptyInputIsEmpty") { t in
        t.equal(TextReflow.paragraphs([]), [])
    },
    TestCase("wrappedLinesJoinIntoOneParagraph") { t in
        // "over" (≈0.1 wide) would not fit after "jumps" at the column edge 0.6.
        let lines = [
            line("The quick brown fox jumps", top: 0.10, left: 0.1, right: 0.6),
            line("over the lazy dog", top: 0.16, left: 0.1, right: 0.44),
        ]
        t.equal(TextReflow.paragraphs(lines), ["The quick brown fox jumps over the lazy dog"])
    },
    TestCase("shortLineEndsParagraph") { t in
        // Code-style: each short line leaves room for the next word, so none wrapped.
        let lines = [
            line("let x = 1", top: 0.10, left: 0.1, right: 0.28),
            line("let y = 2", top: 0.16, left: 0.1, right: 0.28),
            line("return veryLongExpression(with: lots, of: arguments)", top: 0.22, left: 0.1, right: 1.0),
        ]
        t.equal(TextReflow.paragraphs(lines), ["let x = 1", "let y = 2",
                                               "return veryLongExpression(with: lots, of: arguments)"])
    },
    TestCase("bulletMarkerStartsNewParagraph") { t in
        let lines = [
            line("• The Boston Consulting Group", top: 0.10, left: 0.1, right: 0.7),
            line("matrix is a planning tool.", top: 0.16, left: 0.14, right: 0.66),
            line("• It looks at market growth", top: 0.24, left: 0.1, right: 0.64),
            line("and market share.", top: 0.30, left: 0.14, right: 0.48),
        ]
        t.equal(TextReflow.paragraphs(lines), [
            "• The Boston Consulting Group matrix is a planning tool.",
            "• It looks at market growth and market share.",
        ])
    },
    TestCase("numberedMarkerStartsNewParagraph") { t in
        let lines = [
            line("1. First item that wraps onto", top: 0.10, left: 0.1, right: 0.7),
            line("a second line", top: 0.16, left: 0.14, right: 0.4),
            line("2. Second item", top: 0.22, left: 0.1, right: 0.38),
        ]
        t.equal(TextReflow.paragraphs(lines), ["1. First item that wraps onto a second line", "2. Second item"])
    },
    TestCase("largeGapStartsNewParagraph") { t in
        // Full-width line, so the fit test alone would merge; the gap (1.2× line height) must not.
        let lines = [
            line("A full width line of prose that reaches", top: 0.10, left: 0.1, right: 0.9),
            line("Next paragraph here", top: 0.21, left: 0.1, right: 0.5),
        ]
        t.equal(TextReflow.paragraphs(lines), ["A full width line of prose that reaches", "Next paragraph here"])
    },
    TestCase("pitchJumpStartsNewParagraph") { t in
        // Three lines at a 0.06 pitch, then one at 0.09 (gap only 0.8× height, so the
        // absolute gap rule stays quiet — the block's own rhythm has to catch it).
        let lines = [
            line("first line of the block here", top: 0.10, left: 0.1, right: 0.66),
            line("second line of the block too", top: 0.16, left: 0.1, right: 0.66),
            line("third line of the block ends", top: 0.22, left: 0.1, right: 0.66),
            line("fourth line after a paragraph", top: 0.31, left: 0.1, right: 0.68),
        ]
        t.equal(TextReflow.paragraphs(lines), [
            "first line of the block here second line of the block too third line of the block ends",
            "fourth line after a paragraph",
        ])
    },
    TestCase("fontSizeChangeStartsNewParagraph") { t in
        let lines = [
            line("Big heading here", top: 0.10, left: 0.1, right: 0.6, height: 0.08),
            line("body text that is long enough", top: 0.19, left: 0.1, right: 0.6, height: 0.04),
        ]
        t.equal(TextReflow.paragraphs(lines), ["Big heading here", "body text that is long enough"])
    },
    TestCase("columnsStaySeparate") { t in
        // Two side-by-side columns whose lines interleave top-to-bottom.
        let lines = [
            line("left column first", top: 0.10, left: 0.05, right: 0.45),
            line("right column first", top: 0.10, left: 0.55, right: 0.95),
            line("wrapped", top: 0.16, left: 0.05, right: 0.2),
            line("wrapped too", top: 0.16, left: 0.55, right: 0.78),
        ]
        t.equal(TextReflow.paragraphs(lines), ["left column first wrapped", "right column first wrapped too"])
    },
    TestCase("sameRowFragmentsJoinWhenAdjacent") { t in
        let lines = [
            line("Hello", top: 0.10, left: 0.10, right: 0.20),
            line("world", top: 0.10, left: 0.21, right: 0.31),
        ]
        t.equal(TextReflow.paragraphs(lines), ["Hello world"])
    },
    TestCase("sameRowDistantFragmentsStaySeparate") { t in
        let lines = [
            line("Name", top: 0.10, left: 0.1, right: 0.2),
            line("Value", top: 0.10, left: 0.6, right: 0.7),
        ]
        t.equal(TextReflow.paragraphs(lines), ["Name", "Value"])
    },
    TestCase("linesAreSortedTopToBottom") { t in
        let lines = [
            line("over the lazy dog", top: 0.16, left: 0.1, right: 0.44),
            line("The quick brown fox jumps", top: 0.10, left: 0.1, right: 0.6),
        ]
        t.equal(TextReflow.paragraphs(lines), ["The quick brown fox jumps over the lazy dog"])
    },
    TestCase("hyphenatedBreakJoinsWithoutSpace") { t in
        let lines = [
            line("a tool for product portfo-", top: 0.10, left: 0.1, right: 0.62),
            line("lio analysis", top: 0.16, left: 0.1, right: 0.34),
        ]
        t.equal(TextReflow.paragraphs(lines), ["a tool for product portfolio analysis"])
    },
    TestCase("bulletGlyphsNormalizeAndWhitespaceTrims") { t in
        let lines = [
            line("  · first thing ", top: 0.10, left: 0.1, right: 0.4),
            line("● second thing", top: 0.18, left: 0.1, right: 0.4),
        ]
        t.equal(TextReflow.paragraphs(lines), ["• first thing", "• second thing"])
    },
]
