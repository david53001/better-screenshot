import TestKit
import CoreGraphics
@testable import EditorKit

let textAnnotationTests: [TestCase] = [
    TestCase("longerStringHasWiderBox") { t in
        let short = TextAnnotation(text: "Hi", origin: CGPoint(x: 0, y: 0))
        let long = TextAnnotation(text: "Hello world, this is longer", origin: CGPoint(x: 0, y: 0))
        t.isTrue(long.boundingBox().width > short.boundingBox().width)
    },
    TestCase("moveOffsetsOrigin") { t in
        let ta = TextAnnotation(text: "Hi", origin: CGPoint(x: 10, y: 10))
        let m = ta.moved(by: CGVector(dx: 5, dy: 7))
        t.approxEqual(Double(m.boundingBox().minX), 15, tol: 0.5)
        t.approxEqual(Double(m.boundingBox().minY), 17, tol: 0.5)
    },
    TestCase("newlineStacksLinesInsteadOfOverwriting") { t in
        let one = TextAnnotation(text: "Hello", origin: .zero)
        let two = TextAnnotation(text: "Hello\nWorld", origin: .zero)
        t.isTrue(two.boundingBox().height > one.boundingBox().height * 1.8)
    },
    TestCase("wrapWidthWrapsLongTextOntoMoreLines") { t in
        let text = "The quick brown fox jumps over the lazy dog again and again"
        let unwrapped = TextAnnotation(text: text, origin: .zero)
        let wrapped = TextAnnotation(text: text, origin: .zero, wrapWidth: 200)
        t.isTrue(wrapped.boundingBox().width <= 200)
        t.isTrue(wrapped.boundingBox().height > unwrapped.boundingBox().height * 1.8)
    },
]
