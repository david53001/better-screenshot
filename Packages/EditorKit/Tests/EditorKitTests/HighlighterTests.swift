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

/// 100×100: white, with a black band (text stand-in) at x 40…59 and a mid-grey band at x 70…89.
private func base() -> CGImage {
    let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 40, y: 0, width: 20, height: 100))
    ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)); ctx.fill(CGRect(x: 70, y: 0, width: 20, height: 100))
    return ctx.makeImage()!
}

private func pen(opacity: CGFloat) -> AnnotationStyle {
    var s = AnnotationStyle.default
    s.highlighterPen = HighlighterPen(color: RGBAColor(r: 1, g: 1, b: 0, a: 1), width: 20, opacity: opacity)
    return s.withHighlighterPen
}

/// A horizontal stroke across the whole image at y = 50.
private func stroke(_ style: AnnotationStyle) -> HighlighterAnnotation {
    HighlighterAnnotation(points: [CGPoint(x: 0, y: 50), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 50)], style: style)
}

let highlighterTests: [TestCase] = [
    TestCase("highlighterMultipliesSoTextUnderneathStaysReadable") { t in
        var doc = EditorDocument(baseImage: base())
        doc.add(stroke(pen(opacity: 1)))
        guard let out = t.unwrap(DocumentRenderer.render(doc)) else { return }
        let white = rgba(out, 20, 50), black = rgba(out, 50, 50), grey = rgba(out, 80, 50)
        t.isTrue(white[0] > 245 && white[1] > 245 && white[2] < 10, "white paper turns yellow: \(white)")
        t.isTrue(black[0] < 10 && black[1] < 10 && black[2] < 10, "black text stays black: \(black)")
        // Multiply, not replace: grey × yellow keeps the grey's red/green (a plain yellow would be
        // 255) and only loses its blue.
        let plainGrey = rgba(out, 80, 20)
        t.isTrue(abs(grey[0] - plainGrey[0]) <= 4 && abs(grey[1] - plainGrey[1]) <= 4 && grey[0] < 200 && grey[2] < 10,
                 "grey is tinted, not covered: \(grey) (grey outside the stroke: \(plainGrey))")
        let outside = rgba(out, 20, 20)
        t.isTrue(outside[0] > 245 && outside[2] > 245, "untouched outside the stroke: \(outside)")
    },
    TestCase("highlighterOpacityFadesTheTint") { t in
        var doc = EditorDocument(baseImage: base())
        doc.add(stroke(pen(opacity: 0.4)))
        guard let out = t.unwrap(DocumentRenderer.render(doc)) else { return }
        let white = rgba(out, 20, 50), black = rgba(out, 50, 50)
        // white × (1 − 0.4) + (white × yellow) × 0.4 → blue ≈ 0.6 × 255.
        t.isTrue(white[0] > 245 && white[1] > 245 && abs(white[2] - 153) <= 8, "40% yellow on white: \(white)")
        t.isTrue(black[0] < 10 && black[1] < 10 && black[2] < 10, "black stays black at 40%: \(black)")
    },
    TestCase("selfCrossingStrokeDoesNotDarkenTwice") { t in
        var doc = EditorDocument(baseImage: base())
        // Out to x 90 and back to x 50: x 40…100 is covered twice, x < 40 once (white paper at 20 and 65).
        doc.add(HighlighterAnnotation(points: [CGPoint(x: 5, y: 30), CGPoint(x: 90, y: 30), CGPoint(x: 50, y: 31)],
                                      style: pen(opacity: 0.4)))
        guard let out = t.unwrap(DocumentRenderer.render(doc)) else { return }
        let single = rgba(out, 20, 30), overlap = rgba(out, 65, 30)
        t.isTrue(abs(single[2] - overlap[2]) <= 4, "overlap \(overlap) vs single \(single)")
    },
    TestCase("canvasMultipliesToo") { t in
        var doc = EditorDocument(baseImage: base())
        doc.add(stroke(pen(opacity: 1)))
        let canvas = EditorCanvasView(document: doc)
        canvas.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        guard let rep = t.unwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)) else { return }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        guard let img = t.unwrap(rep.cgImage) else { return }
        let black = rgba(img, img.width * 50 / 100, img.height * 50 / 100)
        let white = rgba(img, img.width * 20 / 100, img.height * 50 / 100)
        t.isTrue(black[0] < 20 && black[1] < 20, "text under the marker stays dark on the canvas: \(black)")
        t.isTrue(white[0] > 230 && white[2] < 60, "paper turns yellow on the canvas: \(white)")
    },
    TestCase("boundingBoxIsPathPlusHalfWidthAndMovesWithIt") { t in
        let h = HighlighterAnnotation(points: [CGPoint(x: 10, y: 20), CGPoint(x: 60, y: 25), CGPoint(x: 40, y: 50)],
                                      style: pen(opacity: 0.4))
        t.equal(h.boundingBox(), CGRect(x: 0, y: 10, width: 70, height: 50))
        let m = h.moved(by: CGVector(dx: 5, dy: -5))
        t.equal(m.boundingBox(), CGRect(x: 5, y: 5, width: 70, height: 50))
        t.equal(EditorTool.maker(of: m), .highlighter)
    },
    TestCase("penStyleIsItsOwnStickyDefault") { t in
        var s = AnnotationStyle.default   // red, 4 px, opaque — the other tools' default
        let penView = s.withHighlighterPen
        t.isTrue(RecentColors.same(penView.strokeColor, RGBAColor(r: 1, g: 0.84, b: 0.04, a: 1)), "default pen is yellow")
        t.approxEqual(Double(penView.lineWidth), 20)
        t.approxEqual(Double(penView.opacity), 0.4, tol: 1e-9)
        var edited = penView
        edited.lineWidth = 32; edited.opacity = 0.6
        s.rememberHighlighterPen(from: edited)
        t.approxEqual(Double(s.highlighterPen.width), 32)
        t.approxEqual(Double(s.lineWidth), 4, tol: 1e-9)
        t.approxEqual(Double(s.opacity), 1, tol: 1e-9)
    },
    TestCase("adoptingAnObjectsStyleKeepsTheCurrentToolDefaults") { t in
        // An old text carries the defaults from when it was drawn; opening it must not roll them back.
        let old = AnnotationStyle.default
        var current = AnnotationStyle.default
        current.blurRadius = 30; current.pixelSize = 20; current.redactionMode = .blackout
        current.highlighterPen.width = 32; current.spotlightShape = .ellipse; current.spotlightDim = 0.3
        var text = old
        text.fontSize = 48
        let adopted = text.keepingToolDefaults(of: current)
        t.approxEqual(Double(adopted.fontSize), 48)
        t.isTrue(adopted.keepingToolDefaults(of: text) == text, "only the tool-default fields change")
        t.approxEqual(Double(adopted.blurRadius), 30)
        t.approxEqual(Double(adopted.pixelSize), 20)
        t.equal(adopted.redactionMode, .blackout)
        t.approxEqual(Double(adopted.highlighterPen.width), 32)
        t.equal(adopted.spotlightShape, .ellipse)
        t.approxEqual(Double(adopted.spotlightDim), 0.3, tol: 1e-9)
    },
    TestCase("legacyStyleDecodesTheDefaultPenAndClampsABadOne") { t in
        do {
            let legacy = try JSONDecoder().decode(AnnotationStyle.self, from: Data("""
            {"strokeColor": {"r": 1, "g": 0, "b": 0, "a": 1},
             "fillColor": {"r": 1, "g": 0, "b": 0, "a": 0.25}, "lineWidth": 4, "fontSize": 24}
            """.utf8))
            t.isTrue(legacy.highlighterPen == .default)
            var s = AnnotationStyle.default
            s.highlighterPen = HighlighterPen(color: RGBAColor(r: 0, g: 1, b: 0, a: 1), width: 30, opacity: 0.5)
            let round = try JSONDecoder().decode(AnnotationStyle.self, from: JSONEncoder().encode(s))
            t.isTrue(round == s, "pen round-trips")
            s.highlighterPen = HighlighterPen(color: RGBAColor(r: 0, g: 1, b: 0, a: 1), width: 900, opacity: 0)
            let clamped = try JSONDecoder().decode(AnnotationStyle.self, from: JSONEncoder().encode(s))
            t.approxEqual(Double(clamped.highlighterPen.width), 48)
            t.approxEqual(Double(clamped.highlighterPen.opacity), 0.1, tol: 1e-9)
        } catch { t.fail("decode threw: \(error)") }
    },
]
