import TestKit
import AppKit
@testable import EditorKit

private func rgba(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let i = (y * w + x) * 4
    return [Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]), Int(buf[i + 3])]
}

private func white(_ n: Int = 100) -> CGImage {
    let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
    return ctx.makeImage()!
}

private func spot(_ frame: CGRect, dim: CGFloat = 0.6, shape: SpotlightShape = .rectangle) -> SpotlightAnnotation {
    var s = AnnotationStyle.default
    s.spotlightDim = dim; s.spotlightShape = shape
    return SpotlightAnnotation(frame: frame, style: s)
}

/// White darkened by `dim` black: 255 × (1 − dim).
private func dimmed(_ dim: Double) -> Int { Int((255 * (1 - dim)).rounded()) }

let spotlightTests: [TestCase] = [
    TestCase("insideUnchangedOutsideDarkenedByTheDimAmount") { t in
        for dim in [0.6, 0.3] {
            var doc = EditorDocument(baseImage: white())
            doc.add(spot(CGRect(x: 20, y: 20, width: 40, height: 40), dim: CGFloat(dim)))
            guard let out = t.unwrap(DocumentRenderer.render(doc)) else { return }
            let inside = rgba(out, 40, 40), outside = rgba(out, 80, 80)
            t.isTrue(inside[0] > 250 && inside[1] > 250 && inside[2] > 250, "inside stays white: \(inside)")
            t.isTrue(abs(outside[0] - dimmed(dim)) <= 3 && abs(outside[2] - dimmed(dim)) <= 3,
                     "outside darkened by \(dim): \(outside), want ≈\(dimmed(dim))")
        }
    },
    TestCase("ellipseSpotlightDimsTheBoxCorners") { t in
        var doc = EditorDocument(baseImage: white())
        doc.add(spot(CGRect(x: 20, y: 20, width: 60, height: 40), shape: .ellipse))
        guard let out = t.unwrap(DocumentRenderer.render(doc)) else { return }
        t.isTrue(rgba(out, 50, 40)[0] > 250, "centre bright")
        t.isTrue(abs(rgba(out, 22, 22)[0] - dimmed(0.6)) <= 3, "box corner dimmed")
    },
    TestCase("severalSpotlightsMakeOneLayerWithSeveralHoles") { t in
        var doc = EditorDocument(baseImage: white())
        doc.add(spot(CGRect(x: 10, y: 10, width: 30, height: 30)))
        doc.add(spot(CGRect(x: 30, y: 30, width: 30, height: 30)))   // overlaps the first at 30…40
        doc.add(spot(CGRect(x: 70, y: 70, width: 20, height: 20)))
        guard let out = t.unwrap(DocumentRenderer.render(doc)) else { return }
        for (x, y) in [(15, 15), (35, 35), (55, 55), (80, 80)] {
            t.isTrue(rgba(out, x, y)[0] > 250, "(\(x),\(y)) inside a spotlight stays bright — incl. the overlap")
        }
        t.isTrue(abs(rgba(out, 5, 95)[0] - dimmed(0.6)) <= 3, "outside dimmed once, not per spotlight")
    },
    TestCase("otherObjectsStayBrightAboveTheDim") { t in
        var doc = EditorDocument(baseImage: white())
        var red = AnnotationStyle.default
        red.strokeColor = RGBAColor(r: 1, g: 0, b: 0, a: 1)
        doc.add(FilledRectangleAnnotation(frame: CGRect(x: 70, y: 10, width: 20, height: 20), style: red))
        doc.add(spot(CGRect(x: 10, y: 50, width: 30, height: 30)))   // drawn after, yet below
        guard let out = t.unwrap(DocumentRenderer.render(doc)) else { return }
        let box = rgba(out, 80, 20)
        t.isTrue(box[0] > 245 && box[1] < 20, "a box outside the spotlight keeps its full colour: \(box)")
    },
    TestCase("redactionsOutsideTheSpotlightAreDimmedToo") { t in
        let base = white()
        var doc = EditorDocument(baseImage: base)
        var s = AnnotationStyle.default
        s.redactionMode = .pixelate
        doc.add(RedactionAnnotation(frame: CGRect(x: 60, y: 60, width: 30, height: 30), source: base, style: s))
        doc.add(spot(CGRect(x: 10, y: 10, width: 30, height: 30)))
        guard let out = t.unwrap(DocumentRenderer.render(doc)) else { return }
        t.isTrue(abs(rgba(out, 75, 75)[0] - dimmed(0.6)) <= 3, "the (white) pixelated box is dimmed like the image")
        t.isTrue(abs(rgba(out, 50, 50)[0] - dimmed(0.6)) <= 3, "and not dimmed twice next to it")
    },
    TestCase("canvasDrawsTheDimLayerToo") { t in
        var doc = EditorDocument(baseImage: white())
        doc.add(spot(CGRect(x: 20, y: 20, width: 40, height: 40)))
        let canvas = EditorCanvasView(document: doc)
        canvas.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        guard let rep = t.unwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)) else { return }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        guard let img = t.unwrap(rep.cgImage) else { return }
        let inside = rgba(img, img.width * 40 / 100, img.height * 40 / 100)
        let outside = rgba(img, img.width * 80 / 100, img.height * 80 / 100)
        t.isTrue(inside[0] > 245, "canvas: inside bright \(inside)")
        t.isTrue(outside[0] > 80 && outside[0] < 130, "canvas: outside dimmed \(outside)")
    },
    TestCase("dimEditReachesEverySpotlight") { t in
        let c = EditorCanvasView(document: EditorDocument(baseImage: white()))
        c.insert(spot(CGRect(x: 10, y: 10, width: 20, height: 20)))
        c.insert(spot(CGRect(x: 50, y: 50, width: 20, height: 20)))   // selected
        c.applyStyleEdit({ $0.spotlightDim = 0.3 }, group: "spotlightDim")
        t.isTrue(c.currentDocument().annotations.allSatisfy { abs($0.style.spotlightDim - 0.3) < 1e-9 }, "both take the new dim")
        c.applyStyleEdit({ $0.spotlightShape = .ellipse })
        t.equal(c.currentDocument().annotations.map(\.style.spotlightShape), [.rectangle, .ellipse], "shape converts only the selection")
        c.clearSelection()
        c.applyStyleEdit({ $0.spotlightDim = 0.8 }, group: "spotlightDim2")
        t.isTrue(c.currentDocument().annotations.allSatisfy { abs($0.style.spotlightDim - 0.8) < 1e-9 },
                 "with nothing selected the dim still changes the one layer")
        c.undo()
        t.isTrue(c.currentDocument().annotations.allSatisfy { abs($0.style.spotlightDim - 0.3) < 1e-9 }, "one undo step")
    },
    TestCase("spotlightsAreHitLastAndResizeLikeBoxes") { t in
        var doc = EditorDocument(baseImage: white())
        let arrow = ArrowAnnotation(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 40, y: 40))
        doc.add(arrow)
        let s = spot(CGRect(x: 10, y: 10, width: 80, height: 80))
        doc.add(s)   // later in the list, but drawn beneath
        t.equal(doc.topmostHit(at: CGPoint(x: 30, y: 30)), arrow.id, "the arrow inside the spotlight wins")
        t.equal(doc.topmostHit(at: CGPoint(x: 85, y: 85)), s.id, "empty spotlight area selects the spotlight")
        t.equal(EditorTool.maker(of: s), .spotlight)
    },
    TestCase("legacyStyleDecodesSpotlightDefaultsAndClamps") { t in
        do {
            let legacy = try JSONDecoder().decode(AnnotationStyle.self, from: Data("""
            {"strokeColor": {"r": 1, "g": 0, "b": 0, "a": 1},
             "fillColor": {"r": 1, "g": 0, "b": 0, "a": 0.25}, "lineWidth": 4, "fontSize": 24}
            """.utf8))
            t.equal(legacy.spotlightShape, .rectangle)
            t.approxEqual(Double(legacy.spotlightDim), 0.6, tol: 1e-9)
            var s = AnnotationStyle.default
            s.spotlightShape = .ellipse; s.spotlightDim = 0.45
            t.isTrue(try JSONDecoder().decode(AnnotationStyle.self, from: JSONEncoder().encode(s)) == s, "round-trip")
            s.spotlightDim = 1
            let c = try JSONDecoder().decode(AnnotationStyle.self, from: JSONEncoder().encode(s))
            t.approxEqual(Double(c.spotlightDim), 0.9, tol: 1e-9)
        } catch { t.fail("decode threw: \(error)") }
    },
]
