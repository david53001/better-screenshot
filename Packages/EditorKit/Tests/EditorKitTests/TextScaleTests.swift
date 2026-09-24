import TestKit
import AppKit
@testable import EditorKit

let textScaleTests: [TestCase] = [
    TestCase("draggingACornerAlongTheDiagonalScalesProportionally") { t in
        let box = CGRect(x: 100, y: 100, width: 200, height: 50)
        // Every corner scales about the opposite one: one more diagonal outward = 2×.
        t.approxEqual(Double(TextScale.factor(box: box, corner: .bottomRight, by: CGVector(dx: 200, dy: 50))), 2)
        t.approxEqual(Double(TextScale.factor(box: box, corner: .topRight, by: CGVector(dx: 200, dy: -50))), 2)
        t.approxEqual(Double(TextScale.factor(box: box, corner: .bottomLeft, by: CGVector(dx: -200, dy: 50))), 2)
        t.approxEqual(Double(TextScale.factor(box: box, corner: .topLeft, by: CGVector(dx: -200, dy: -50))), 2)
        // Half a diagonal inward = 0.5×.
        t.approxEqual(Double(TextScale.factor(box: box, corner: .topLeft, by: CGVector(dx: 100, dy: 25))), 0.5)
    },
    TestCase("dragAcrossTheDiagonalDoesNotScale") { t in
        // (-50, 200) is perpendicular to the (200, 50) diagonal.
        let box = CGRect(x: 0, y: 0, width: 200, height: 50)
        t.approxEqual(Double(TextScale.factor(box: box, corner: .bottomRight, by: CGVector(dx: -50, dy: 200))), 1)
        t.approxEqual(Double(TextScale.factor(box: .zero, corner: .bottomRight, by: CGVector(dx: 5, dy: 5))), 1)
    },
    TestCase("scaledRoundsTheFontAndScalesTheRestByTheSameFactor") { t in
        var s = AnnotationStyle.default                  // 24 pt
        s.textOutlineWidth = 3
        let r = TextScale.scaled(s, wrapWidth: 240, by: 1.55)   // 37.2 → 37 pt
        t.approxEqual(Double(r.style.fontSize), 37)
        let k = 37.0 / 24.0                              // the factor the font actually moved
        t.approxEqual(Double(r.wrapWidth ?? 0), 240 * k, tol: 1e-9)
        t.approxEqual(Double(r.style.textBackgroundPadding), 6 * k, tol: 1e-9)
        t.approxEqual(Double(r.style.textBackgroundCornerRadius), 4 * k, tol: 1e-9)
        t.approxEqual(Double(r.style.textOutlineWidth), 3 * k, tol: 1e-9)
        t.isNil(TextScale.scaled(s, wrapWidth: nil, by: 2).wrapWidth, "a free label stays a free label")
    },
    TestCase("scaledClampsTheFontTo8Through400") { t in
        let s = AnnotationStyle.default
        t.approxEqual(Double(TextScale.scaled(s, wrapWidth: 100, by: 100).style.fontSize), 400)
        let small = TextScale.scaled(s, wrapWidth: 120, by: 0.01)
        t.approxEqual(Double(small.style.fontSize), 8)
        t.approxEqual(Double(small.wrapWidth ?? 0), 40, tol: 1e-9)   // 120 × 8/24: box follows the clamp
        t.approxEqual(Double(TextScale.scaled(s, wrapWidth: nil, by: -3).style.fontSize), 8)  // past the anchor
    },
    TestCase("scaledKeepsPaddingRadiusAndOutlineInTheirRanges") { t in
        var s = AnnotationStyle.default
        s.fontSize = 10; s.textBackgroundPadding = 30; s.textBackgroundCornerRadius = 30; s.textOutlineWidth = 2
        let big = TextScale.scaled(s, wrapWidth: nil, by: 10).style
        t.approxEqual(Double(big.textBackgroundPadding), Double(AnnotationStyle.textBackgroundPaddingRange.upperBound))
        t.approxEqual(Double(big.textBackgroundCornerRadius), Double(AnnotationStyle.textBackgroundCornerRadiusRange.upperBound))
        t.approxEqual(Double(big.textOutlineWidth), Double(AnnotationStyle.textOutlineWidthRange.upperBound))
        s.textOutlineWidth = 1
        let tiny = TextScale.scaled(s, wrapWidth: nil, by: 0.8).style   // 10 → 8 pt
        t.approxEqual(Double(tiny.textOutlineWidth), Double(AnnotationStyle.textOutlineWidthRange.lowerBound))
    },
    TestCase("placedKeepsTheOppositeCornerFixed") { t in
        let size = CGSize(width: 80, height: 30)
        let a = CGPoint(x: 100, y: 100)
        t.equal(TextScale.placed(size: size, anchor: a, corner: .bottomRight), CGRect(x: 100, y: 100, width: 80, height: 30))
        t.equal(TextScale.placed(size: size, anchor: a, corner: .topLeft), CGRect(x: 20, y: 70, width: 80, height: 30))
        t.equal(TextScale.placed(size: size, anchor: a, corner: .topRight), CGRect(x: 100, y: 70, width: 80, height: 30))
        t.equal(TextScale.placed(size: size, anchor: a, corner: .bottomLeft), CGRect(x: 20, y: 100, width: 80, height: 30))
        let box = CGRect(x: 10, y: 20, width: 30, height: 40)
        t.equal(TextScale.anchor(of: .topLeft, in: box), CGPoint(x: 40, y: 60))
        t.equal(TextScale.anchor(of: .bottomLeft, in: box), CGPoint(x: 40, y: 20))
    },
    TestCase("cornerDragScalesATextAndKeepsTheOppositeCorner") { t in
        let ta = TextAnnotation(text: "Hello world", origin: CGPoint(x: 100, y: 100), wrapWidth: 200)
        let box = ta.boundingBox()
        let big = ta.scaled(dragging: .bottomRight, by: CGVector(dx: box.width, dy: box.height))
        t.approxEqual(Double(big.style.fontSize), 48)
        t.approxEqual(Double(big.wrapWidth ?? 0), 400, tol: 1e-9)
        t.approxEqual(Double(big.boundingBox().minX), Double(box.minX), tol: 0.01)
        t.approxEqual(Double(big.boundingBox().minY), Double(box.minY), tol: 0.01)
        t.equal(big.id, ta.id, "same object, so undo and selection follow it")
        let small = ta.scaled(dragging: .topLeft, by: CGVector(dx: box.width / 2, dy: box.height / 2))
        t.approxEqual(Double(small.style.fontSize), 12)
        t.approxEqual(Double(small.boundingBox().maxX), Double(box.maxX), tol: 0.01)
        t.approxEqual(Double(small.boundingBox().maxY), Double(box.maxY), tol: 0.01)
    },
    TestCase("cornerDragKeepsLineBreaks") { t in
        let ta = TextAnnotation(text: "Wrap this sentence onto several lines please", origin: .zero, wrapWidth: 150)
        let box = ta.boundingBox()
        let big = ta.scaled(dragging: .bottomRight, by: CGVector(dx: box.width, dy: box.height))
        let ratio = big.boundingBox().height / box.height
        t.isTrue(ratio > 1.9 && ratio < 2.1, "same line count at 2×: height ratio \(ratio)")
    },
    TestCase("cornerDragAnchorsTheBoxBehindTheText") { t in
        var s = AnnotationStyle.default
        s.textBackgroundMode = .solid
        let ta = TextAnnotation(text: "Boxed", origin: CGPoint(x: 50, y: 50), style: s)
        let box = ta.boundingBox()
        let big = ta.scaled(dragging: .topLeft, by: CGVector(dx: -box.width, dy: -box.height))
        t.approxEqual(Double(big.boundingBox().maxX), Double(box.maxX), tol: 0.01)
        t.approxEqual(Double(big.boundingBox().maxY), Double(box.maxY), tol: 0.01)
        t.approxEqual(Double(big.style.textBackgroundPadding), 12, tol: 1e-9)
    },
]
