import TestKit
import AppKit
@testable import EditorKit

/// RGBA8 pixels of `image`, top row first.
private struct Pixels {
    let w: Int, h: Int
    var buf: [UInt8]
    init(_ image: CGImage) {
        w = image.width; h = image.height
        buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    func at(_ x: Int, _ y: Int) -> [Int] {
        let i = (y * w + x) * 4
        return [Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2])]
    }
    /// Anything visibly off the white base.
    func isInk(_ x: Int, _ y: Int) -> Bool { at(x, y).contains { $0 < 235 } }
    /// Bounding box (x0, y0, x1, y1) of the ink.
    var inkBounds: (x0: Int, y0: Int, x1: Int, y1: Int)? {
        var r: (Int, Int, Int, Int)?
        for y in 0..<h { for x in 0..<w where isInk(x, y) {
            r = r.map { (min($0.0, x), min($0.1, y), max($0.2, x), max($0.3, y)) } ?? (x, y, x, y)
        } }
        return r
    }
    func inkCount(row y: Int) -> Int { (0..<w).filter { isInk($0, y) }.count }
}

private func whiteBase(_ w: Int, _ h: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

private func render(_ text: TextAnnotation, _ w: Int = 300, _ h: Int = 120) -> Pixels? {
    var doc = EditorDocument(baseImage: whiteBase(w, h))
    doc.add(text)
    return DocumentRenderer.render(doc).map(Pixels.init)
}

private func style(_ edit: (inout AnnotationStyle) -> Void) -> AnnotationStyle {
    var s = AnnotationStyle.default
    s.strokeColor = RGBAColor(r: 0, g: 0, b: 0, a: 1)
    edit(&s)
    return s
}

let textRenderTests: [TestCase] = [
    TestCase("solidBackgroundFillsTheBoxWithItsColour") { t in
        let s = style { $0.strokeColor = RGBAColor(r: 1, g: 1, b: 1, a: 1)
                        $0.textBackgroundMode = .solid
                        $0.textBackgroundColor = RGBAColor(r: 0, g: 0, b: 1, a: 1) }
        let ta = TextAnnotation(text: "Hi", origin: CGPoint(x: 40, y: 30), style: s)
        guard let px = t.unwrap(render(ta)) else { return }
        let box = ta.boundingBox()
        // Left padding strip, vertically centred: pure box colour, no glyph ink.
        let p = px.at(Int(box.minX) + 3, Int(box.midY))
        t.isTrue(p[0] < 10 && p[1] < 10 && p[2] > 245, "box pixel is the chosen blue: \(p)")
        t.isTrue(px.at(Int(box.minX) - 3, Int(box.midY)) == [255, 255, 255], "outside the box stays white")
    },
    TestCase("autoBackgroundKeepsTheContrastingChip") { t in
        let s = style { $0.strokeColor = RGBAColor(r: 1, g: 1, b: 1, a: 1); $0.textBackgroundMode = .auto }
        let ta = TextAnnotation(text: "Hi", origin: CGPoint(x: 40, y: 30), style: s)
        guard let px = t.unwrap(render(ta)) else { return }
        let p = px.at(Int(ta.boundingBox().minX) + 3, Int(ta.boundingBox().midY))
        t.isTrue(p.allSatisfy { abs($0 - 0x18) <= 3 }, "dark chip behind white text: \(p)")
    },
    TestCase("noBackgroundDrawsNoBox") { t in
        let ta = TextAnnotation(text: "Hi", origin: CGPoint(x: 40, y: 30), style: style { _ in })
        guard let px = t.unwrap(render(ta)) else { return }
        t.equal(px.at(38, Int(ta.boundingBox().midY)), [255, 255, 255])
    },
    TestCase("boundingBoxIncludesTheBoxPadding") { t in
        let plain = TextAnnotation(text: "Hi", origin: CGPoint(x: 40, y: 30))
        var boxed = plain
        boxed.style.textBackgroundMode = .solid
        boxed.style.textBackgroundPadding = 10
        t.equal(boxed.boundingBox(), plain.boundingBox().insetBy(dx: -10, dy: -5))
        boxed.style.textBackgroundMode = .auto
        t.equal(boxed.boundingBox(), plain.boundingBox().insetBy(dx: -10, dy: -5))
    },
    TestCase("paddingAndCornerRadiusShapeTheBox") { t in
        let square = style { $0.textBackgroundMode = .solid; $0.textBackgroundColor = RGBAColor(r: 0, g: 0, b: 1, a: 1)
                             $0.textBackgroundPadding = 20; $0.textBackgroundCornerRadius = 0 }
        var round = square
        round.textBackgroundCornerRadius = 20
        let a = TextAnnotation(text: "Hi", origin: CGPoint(x: 60, y: 40), style: square)
        let b = TextAnnotation(text: "Hi", origin: CGPoint(x: 60, y: 40), style: round)
        guard let pa = t.unwrap(render(a)), let pb = t.unwrap(render(b)) else { return }
        let box = a.boundingBox()
        t.isTrue(pa.at(Int(box.minX) + 15, Int(box.midY))[2] > 245, "20 px padding is filled")
        t.isTrue(pa.at(Int(box.minX) + 1, Int(box.minY) + 1)[0] < 10, "square corner filled")
        t.equal(pb.at(Int(box.minX) + 1, Int(box.minY) + 1), [255, 255, 255], "round corner cut away")
    },
    TestCase("outlineWidensTheInkInItsColour") { t in
        let plain = TextAnnotation(text: "Hello", origin: CGPoint(x: 40, y: 30), style: style { _ in })
        var outlined = plain
        outlined.style.textOutline = true
        outlined.style.textOutlineColor = RGBAColor(r: 1, g: 0, b: 0, a: 1)
        outlined.style.textOutlineWidth = 4
        guard let a = t.unwrap(render(plain)?.inkBounds), let pb = t.unwrap(render(outlined)),
              let b = t.unwrap(pb.inkBounds) else { return }
        t.isTrue(a.x0 - b.x0 >= 3 && b.x1 - a.x1 >= 3, "ink grows ~4 px each side: \(a) → \(b)")
        t.isTrue(b.y1 - a.y1 >= 3, "and downward: \(a) → \(b)")
        let edge = pb.at(b.x0 + 1, (b.y0 + b.y1) / 2)
        let reds = (b.y0...b.y1).filter { y in let p = pb.at(b.x0 + 1, y); return p[0] > 200 && p[1] < 60 }
        t.isTrue(!reds.isEmpty, "the widened edge is the outline colour (e.g. \(edge))")
    },
    TestCase("underlineAddsInkBelowTheBaseline") { t in
        let plain = TextAnnotation(text: "ace", origin: CGPoint(x: 40, y: 30), style: style { _ in })
        var under = plain
        under.style.textUnderline = true
        guard let a = t.unwrap(render(plain)?.inkBounds), let b = t.unwrap(render(under)?.inkBounds) else { return }
        t.isTrue(b.y1 > a.y1, "underline ink below the letters: \(a.y1) → \(b.y1)")
    },
    TestCase("strikethroughCrossesTheGapsBetweenLetters") { t in
        let plain = TextAnnotation(text: "i  i  i", origin: CGPoint(x: 40, y: 30), style: style { _ in })
        var struck = plain
        struck.style.textStrikethrough = true
        guard let pa = t.unwrap(render(plain)), let pb = t.unwrap(render(struck)),
              let a = t.unwrap(pa.inkBounds) else { return }
        let fullestPlain = (a.y0...a.y1).map { pa.inkCount(row: $0) }.max() ?? 0
        let fullestStruck = (a.y0...a.y1).map { pb.inkCount(row: $0) }.max() ?? 0
        t.isTrue(fullestStruck >= a.x1 - a.x0 - 2 && fullestStruck > fullestPlain * 2,
                 "one row spans the whole text: \(fullestPlain) → \(fullestStruck) of \(a.x1 - a.x0)")
    },
    TestCase("shadowFallsBelowTheText") { t in
        let plain = TextAnnotation(text: "HH", origin: CGPoint(x: 40, y: 20), style: style { $0.fontSize = 48 })
        var shadowed = plain
        shadowed.style.textShadow = true
        guard let a = t.unwrap(render(plain, 300, 140)?.inkBounds),
              let b = t.unwrap(render(shadowed, 300, 140)?.inkBounds) else { return }
        t.isTrue(b.y1 >= a.y1 + 2, "shadow ink below the letters: \(a) → \(b)")
        t.isTrue(a.y0 - b.y0 < b.y1 - a.y1, "and it falls downward, not upward: \(a) → \(b)")
    },
    TestCase("canvasShadowFallsDownwardToo") { t in
        // The canvas draws through the view's flipped, scaled context — the shadow must still fall down.
        var doc = EditorDocument(baseImage: whiteBase(200, 100))
        doc.add(TextAnnotation(text: "HH", origin: CGPoint(x: 20, y: 10),
                               style: style { $0.fontSize = 40; $0.textShadow = true }))
        let canvas = EditorCanvasView(document: doc)
        canvas.frame = NSRect(x: 0, y: 0, width: 100, height: 50)   // half size: image px = 2 × view pt
        guard let rep = t.unwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)) else { return }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        guard let img = t.unwrap(rep.cgImage) else { return }
        var plainDoc = EditorDocument(baseImage: whiteBase(200, 100))
        plainDoc.add(TextAnnotation(text: "HH", origin: CGPoint(x: 20, y: 10), style: style { $0.fontSize = 40 }))
        let plainCanvas = EditorCanvasView(document: plainDoc)
        plainCanvas.frame = canvas.frame
        guard let rep2 = t.unwrap(plainCanvas.bitmapImageRepForCachingDisplay(in: plainCanvas.bounds)) else { return }
        plainCanvas.cacheDisplay(in: plainCanvas.bounds, to: rep2)
        guard let a = t.unwrap(Pixels(rep2.cgImage!).inkBounds), let b = t.unwrap(Pixels(img).inkBounds) else { return }
        t.isTrue(b.y1 > a.y1 && a.y0 - b.y0 < b.y1 - a.y1, "canvas shadow below: \(a) → \(b)")
    },
]
