import TestKit
import CoreGraphics
@testable import CaptureKit

// Boxes are normalized, top-left origin (see TextReflowTests).
private func line(_ text: String, top: CGFloat, left: CGFloat, right: CGFloat,
                  height: CGFloat = 0.10) -> TextReflow.Line {
    TextReflow.Line(text: text, box: CGRect(x: left, y: top, width: right - left, height: height))
}

/// `m =` beside `a + b` over `2` — Vision's three boxes for m = (a + b)/2.
private let stackedFraction = [
    line("m =", top: 0.45, left: 0.10, right: 0.30),
    line("a + b", top: 0.30, left: 0.35, right: 0.55),
    line("2", top: 0.52, left: 0.42, right: 0.47),
]

let mathLayoutTests: [TestCase] = [
    TestCase("mathOperatorsAreSpacedAsTypeset") { t in
        t.equal(TextReflow.spacedOperators("F= ma"), "F = ma")
        t.equal(TextReflow.spacedOperators("(x²-9)/(x - 3)"), "(x² - 9)/(x - 3)")
        t.equal(TextReflow.spacedOperators("f(x)= 2x³-3x²+5"), "f(x) = 2x³ - 3x² + 5")
        // Unary signs, compound relations and hyphenated words stay as they are.
        t.equal(TextReflow.spacedOperators("y = -3 + (-x)"), "y = -3 + (-x)")
        t.equal(TextReflow.spacedOperators("a <= b, c != d"), "a <= b, c != d")
        t.equal(TextReflow.spacedOperators("the x-axis ≥ 0"), "the x-axis ≥ 0")
    },
    TestCase("setSymbolsReadAsLettersAreRepaired") { t in
        t.equal(TextReflow.repairedMathSymbols("P(A n B) = P(A)P(B)"), "P(A ∩ B) = P(A)P(B)")
        t.equal(TextReflow.repairedMathSymbols("A U B"), "A ∪ B")
        t.equal(TextReflow.repairedMathSymbols("x E R, n E N"), "x ∈ ℝ, n ∈ ℕ")
        t.equal(TextReflow.repairedMathSymbols("P(A|B) =. P(B)"), "P(A|B) = P(B)")
        t.equal(TextReflow.repairedMathSymbols("a ≤ b,c ≥ d at (1,2)"), "a ≤ b, c ≥ d at (1,2)")
        t.equal(TextReflow.repairedMathSymbols("lal = √(14), a•b = | a|| b| cosθ"), "|a| = √14, a · b = |a||b| cos θ")
        t.equal(TextReflow.repairedMathSymbols("y = sin3x"), "y = sin 3x")
        // Words stay words.
        t.equal(TextReflow.repairedMathSymbols("Use n = 5 in E = mc²"), "Use n = 5 in E = mc²")
        t.equal(TextReflow.repairedMathSymbols("single, since, cost = 3"), "single, since, cost = 3")
    },
    TestCase("stackedFractionWithABarBecomesOneLine") { t in
        // The bar region handed over is twice the fraction's width; a bar as
        // wide as the fraction is half of it.
        t.equal(TextReflow.paragraphs(stackedFraction, ruleLength: { $0.width / 2 }), ["m = (a + b)/2"])
    },
    TestCase("stackedLinesWithoutABarStayApart") { t in
        // A matrix's rows (or two centred lines) have no bar between them.
        t.equal(TextReflow.paragraphs(stackedFraction, ruleLength: { _ in 0 }), ["m =", "a + b", "2"])
    },
    TestCase("aTableBorderIsNotAFractionBar") { t in
        // It runs the full width of the region, far past the two cells.
        t.equal(TextReflow.paragraphs(stackedFraction, ruleLength: { $0.width }), ["m =", "a + b", "2"])
    },
    TestCase("barReadAsALeadingMinusIsDropped") { t in
        let lines = [
            line("dy", top: 0.17, left: 0.165, right: 0.306, height: 0.17),
            line("-= 3x²-4", top: 0.265, left: 0.237, right: 0.839, height: 0.17),
            line("dx", top: 0.406, left: 0.165, right: 0.306, height: 0.135),
        ]
        t.equal(TextReflow.paragraphs(lines, ruleLength: { $0.width / 2 }), ["dy/dx = 3x² - 4"])
    },
    TestCase("fractionPartsGetParenthesesOnlyWhenNeeded") { t in
        t.equal(TextReflow.fractionPart("2a"), "2a")
        t.equal(TextReflow.fractionPart("n(n + 1)"), "n(n + 1)")
        t.equal(TextReflow.fractionPart("a + b"), "(a + b)")
        t.equal(TextReflow.fractionPart("sin x"), "(sin x)")
    },
    TestCase("detachedExponentJoinsItsBase") { t in
        let lines = [
            line("A = P(1 + r/n)", top: 0.30, left: 0.05, right: 0.60, height: 0.12),
            line("nt", top: 0.22, left: 0.61, right: 0.68, height: 0.07),
        ]
        t.equal(TextReflow.paragraphs(lines), ["A = P(1 + r/n)ⁿᵗ"])
    },
    TestCase("aNumberAfterAnEqualsSignIsNotAnExponent") { t in
        let lines = [
            line("x² dx =", top: 0.39, left: 0.29, right: 0.78, height: 0.19),
            line("1", top: 0.30, left: 0.81, right: 0.88, height: 0.13),
        ]
        t.isFalse(TextReflow.paragraphs(lines).joined().contains("¹"))
    },
    TestCase("mathLinesAreRecognized") { t in
        t.isTrue(TextReflow.isMath("x² + y² = z²"))
        t.isTrue(TextReflow.isMath("CO₂ + H₂O → H₂CO₃"))
        t.isFalse(TextReflow.isMath("The area of a circle is A = πr², so doubling the radius"))
        t.isFalse(TextReflow.isMath("A plain sentence."))
    },
]
