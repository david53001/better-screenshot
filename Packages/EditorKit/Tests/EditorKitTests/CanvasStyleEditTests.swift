import TestKit
import AppKit
@testable import EditorKit

private func canvasWithWhiteBase() -> EditorCanvasView {
    let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    return EditorCanvasView(document: EditorDocument(baseImage: ctx.makeImage()!))
}

private func firstStyle(_ c: EditorCanvasView) -> AnnotationStyle? {
    c.currentDocument().annotations.first?.style
}

let canvasStyleEditTests: [TestCase] = [
    TestCase("styleEditRestylesTheSelectionAsOneUndoStep") { t in
        let c = canvasWithWhiteBase()
        c.insert(ArrowAnnotation(start: .zero, end: CGPoint(x: 50, y: 50)))   // insert selects it
        c.applyStyleEdit({ $0.lineWidth = 9 })
        t.approxEqual(Double(firstStyle(c)?.lineWidth ?? 0), 9)
        c.undo()
        t.approxEqual(Double(firstStyle(c)?.lineWidth ?? 0), 4, tol: 1e-9)
        c.undo()
        t.equal(c.currentDocument().annotations.count, 0, "second undo removes the arrow itself")
    },
    TestCase("groupedEditsMergeUntilTheGroupEnds") { t in
        let c = canvasWithWhiteBase()
        c.insert(FilledRectangleAnnotation(frame: CGRect(x: 10, y: 10, width: 20, height: 20)))
        for o in [0.8, 0.6, 0.4] { c.applyStyleEdit({ $0.opacity = CGFloat(o) }, group: "opacity") }
        t.approxEqual(Double(firstStyle(c)?.opacity ?? 0), 0.4, tol: 1e-9)
        c.endStyleEditGroup()
        c.applyStyleEdit({ $0.opacity = 0.2 }, group: "opacity")
        c.undo()
        t.approxEqual(Double(firstStyle(c)?.opacity ?? 0), 0.4, tol: 1e-9)
        c.undo()
        t.approxEqual(Double(firstStyle(c)?.opacity ?? 0), 1, tol: 1e-9)
    },
    TestCase("editWithNothingSelectedLeavesTheDocumentAlone") { t in
        let c = canvasWithWhiteBase()
        c.insert(ArrowAnnotation(start: .zero, end: CGPoint(x: 50, y: 50)))
        c.clearSelection()
        c.applyStyleEdit({ $0.lineWidth = 9 })
        t.approxEqual(Double(firstStyle(c)?.lineWidth ?? 0), 4, tol: 1e-9)
        c.undo()
        t.equal(c.currentDocument().annotations.count, 0, "only the insert was undoable")
    },
    TestCase("selectionIsDescribedByTheToolsThatDrawIt") { t in
        let c = canvasWithWhiteBase()
        var s = AnnotationStyle.default
        s.opacity = 0.5
        c.insert(TextAnnotation(text: "Hi", origin: CGPoint(x: 5, y: 5), style: s))
        t.equal(c.selectedTools, [.text])
        t.approxEqual(Double(c.selectionStyle?.opacity ?? 0), 0.5)
        c.clearSelection()
        t.equal(c.selectedTools, [])
        t.isNil(c.selectionStyle)
    },
    TestCase("everyAnnotationTypeMapsToItsTool") { t in
        let r = CGRect(x: 0, y: 0, width: 4, height: 4)
        t.equal(EditorTool.maker(of: ArrowAnnotation(start: .zero, end: .zero)), .arrow)
        t.equal(EditorTool.maker(of: LineAnnotation(start: .zero, end: .zero)), .line)
        t.equal(EditorTool.maker(of: RectangleAnnotation(frame: r, filled: false)), .rectangle)
        t.equal(EditorTool.maker(of: FilledRectangleAnnotation(frame: r)), .filledRectangle)
        t.equal(EditorTool.maker(of: EllipseAnnotation(frame: r)), .ellipse)
        t.equal(EditorTool.maker(of: TextAnnotation(text: "x", origin: .zero)), .text)
        t.equal(EditorTool.maker(of: CounterAnnotation(number: 1, origin: .zero)), .counter)
    },
]
