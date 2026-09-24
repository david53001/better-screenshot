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

private func white(_ n: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
    return ctx.makeImage()!
}

private func red(opacity: CGFloat) -> AnnotationStyle {
    var s = AnnotationStyle.default
    s.strokeColor = RGBAColor(r: 1, g: 0, b: 0, a: 1)
    s.opacity = opacity
    return s
}

let opacityTests: [TestCase] = [
    TestCase("opacityDefaultsToOpaque") { t in
        t.approxEqual(Double(AnnotationStyle.default.opacity), 1)
    },
    TestCase("legacyStyleWithoutOpacityDecodesOpaque") { t in
        let json = """
        {"strokeColor": {"r": 1, "g": 0, "b": 0, "a": 1},
         "fillColor": {"r": 1, "g": 0, "b": 0, "a": 0.25}, "lineWidth": 4, "fontSize": 24}
        """
        do {
            let s = try JSONDecoder().decode(AnnotationStyle.self, from: Data(json.utf8))
            t.approxEqual(Double(s.opacity), 1)
        } catch { t.fail("legacy decode threw: \(error)") }
    },
    TestCase("opacityRoundTripsAndClampsOnDecode") { t in
        do {
            let half = try JSONDecoder().decode(AnnotationStyle.self,
                                                from: JSONEncoder().encode(red(opacity: 0.5)))
            t.approxEqual(Double(half.opacity), 0.5)
            let zero = try JSONDecoder().decode(AnnotationStyle.self,
                                                from: JSONEncoder().encode(red(opacity: 0)))
            t.approxEqual(Double(zero.opacity), 0.1, tol: 1e-9)
        } catch { t.fail("round-trip threw: \(error)") }
    },
    TestCase("halfOpacityFilledRectBlendsWithBase") { t in
        var doc = EditorDocument(baseImage: white(100))
        doc.add(FilledRectangleAnnotation(frame: CGRect(x: 20, y: 20, width: 40, height: 40),
                                          style: red(opacity: 0.5)))
        guard let out = t.unwrap(DocumentRenderer.render(doc)) else { return }
        let p = rgba(out, 40, 40)
        t.isTrue(p[0] > 245, "red stays full")
        t.isTrue(abs(p[1] - 128) <= 6 && abs(p[2] - 128) <= 6, "green/blue half-way to white: \(p)")
    },
    TestCase("translucentArrowDoesNotDoubleUpWhereShaftMeetsHead") { t in
        // The round shaft cap overlaps the head just past its base (x≈48…54).
        // One transparency layer per object keeps that overlap the same tint as the shaft.
        var doc = EditorDocument(baseImage: white(100))
        var s = red(opacity: 0.5); s.lineWidth = 12
        doc.add(ArrowAnnotation(start: CGPoint(x: 20, y: 50), end: CGPoint(x: 80, y: 50), style: s))
        guard let out = t.unwrap(DocumentRenderer.render(doc)) else { return }
        let shaft = rgba(out, 35, 50), overlap = rgba(out, 51, 50)
        t.isTrue(abs(shaft[1] - overlap[1]) <= 4, "shaft \(shaft) vs overlap \(overlap)")
        t.isTrue(abs(shaft[1] - 128) <= 6, "shaft is half-transparent: \(shaft)")
    },
    TestCase("canvasDrawsWithOpacityToo") { t in
        var doc = EditorDocument(baseImage: white(100))
        doc.add(FilledRectangleAnnotation(frame: CGRect(x: 20, y: 20, width: 40, height: 40),
                                          style: red(opacity: 0.5)))
        let canvas = EditorCanvasView(document: doc)
        canvas.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        guard let rep = t.unwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)) else { return }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        guard let img = t.unwrap(rep.cgImage) else { return }
        // Sample the middle of the rect in the cached bitmap's own pixel grid. The cache is
        // colour-managed (display space), so only check it is clearly translucent red.
        let p = rgba(img, img.width * 40 / 100, img.height * 40 / 100)
        t.isTrue(p[0] > 245 && p[1] > 100 && p[1] < 180, "canvas pixel half red: \(p)")
    },
]
