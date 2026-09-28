import TestKit
import CoreGraphics
@testable import CaptureKit

let displayMathTests: [TestCase] = [
    TestCase("displayNodesPrintAsLinearUnicodeMath") { t in
        typealias N = DisplayMath.Node
        t.equal(N.fraction(.text("a + b"), .text("2")).linear, "(a + b)/2")
        t.equal(N.op("∑", lower: .text("i = 1"), upper: .text("n")).linear, "∑ᵢ₌₁ⁿ")
        t.equal(N.op("∫", lower: .text("0"), upper: .text("1")).linear, "∫₀¹")
        // No subscript arrow: the limit goes in `_( )`; a read `o` after the arrow is 0.
        t.equal(N.op("lim", lower: .text("x→o"), upper: nil).linear, "lim_(x→0)")
        t.equal(N.op("lim", lower: .text("n→oo"), upper: nil).linear, "lim_(n→∞)")
        t.equal(N.row([.text("tan θ ="), .fraction(.text("sinθ"), .text("cos θ"))]).linear, "tan θ = (sin θ)/(cos θ)")
        t.isFalse(N.row([.text("x"), .text("= 1")]).hasStructure)
        t.isTrue(N.row([.text("x ="), .fraction(.text("1"), .text("3"))]).hasStructure)
    },
    TestCase("functionNamesGetTheirSpaceBack") { t in
        t.equal(DisplayMath.tidied("sinx"), "sin x")
        t.equal(DisplayMath.tidied("cosθ + lnx"), "cos θ + ln x")
        t.equal(DisplayMath.tidied("sin x"), "sin x")
        t.equal(DisplayMath.tidied("single"), "single")
    },
    TestCase("onlyShortMathLinesClusterIntoADisplay") { t in
        t.isTrue(DisplayMath.isMathy("f (x) = lim"))
        t.isTrue(DisplayMath.isMathy("n(n + 1)"))
        t.isFalse(DisplayMath.isMathy("The derivative of the function is defined as"))
    },
]
