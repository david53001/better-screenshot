import TestKit
import AppKit
@testable import EditorKit

/// RGBA8 readback (premultiplied-last, device RGB).
private func pixels(_ image: CGImage) -> [UInt8] {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buf
}

/// 120×100 base of deterministic noise: every region differs from every other, so a patch
/// rendered for the wrong place can't pass for the right one.
private func noiseBase(width w: Int = 120, height h: Int = 100) -> CGImage {
    var buf = [UInt8](repeating: 255, count: w * h * 4)
    var seed: UInt32 = 12345
    for i in 0..<(w * h) {
        for c in 0..<3 {
            seed = seed &* 1664525 &+ 1013904223
            buf[i * 4 + c] = UInt8(truncatingIfNeeded: seed >> 24)
        }
    }
    return CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}

/// Max per-channel difference between the rendered document inside `rect` and `patch`.
private func maxDiff(render: CGImage, rect: CGRect, patch: CGImage) -> Int {
    guard let region = render.cropping(to: rect) else { return 255 }
    let a = pixels(region), b = pixels(patch)
    guard a.count == b.count else { return 255 }
    return zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0
}

private func style(_ mode: RedactionMode, strength: CGFloat = 12) -> AnnotationStyle {
    var s = AnnotationStyle.default
    s.redactionMode = mode
    s.blurRadius = strength
    s.pixelSize = strength
    return s
}

let redactionTests: [TestCase] = [
    TestCase("movedRedactionRedactsItsNewRegion") { t in
        // The bug: the patch was baked at creation, so a moved box showed the old area's blur.
        let base = noiseBase()
        for mode in RedactionMode.allCases where mode != .blackout {
            var doc = EditorDocument(baseImage: base)
            let r = RedactionAnnotation(frame: CGRect(x: 10, y: 10, width: 30, height: 20),
                                        source: base, style: style(mode))
            doc.add(r)
            _ = DocumentRenderer.render(doc)   // renders (and caches) the patch at the old place
            doc.move(id: r.id, by: CGVector(dx: 60, dy: 50))
            let moved = CGRect(x: 70, y: 60, width: 30, height: 20)
            guard let out = t.unwrap(DocumentRenderer.render(doc)),
                  let fresh = t.unwrap(mode == .blur ? Redactor.blur(base, region: moved, radius: 12)
                                                     : Redactor.pixelate(base, region: moved, blockSize: 12))
            else { return }
            let d = maxDiff(render: out, rect: moved, patch: fresh)
            t.isTrue(d <= 2, "\(mode): moved patch differs from a fresh render by \(d)")
        }
    },
    TestCase("resizedRedactionIsRenderedNotStretched") { t in
        let base = noiseBase()
        let c = EditorCanvasView(document: EditorDocument(baseImage: base))
        let r = RedactionAnnotation(frame: CGRect(x: 10, y: 10, width: 20, height: 20),
                                    source: base, style: style(.pixelate, strength: 6))
        _ = r.patch()
        var bigger = r
        bigger.frame = CGRect(x: 10, y: 10, width: 60, height: 50)
        c.insert(bigger)
        guard let out = t.unwrap(DocumentRenderer.render(c.currentDocument())),
              let fresh = t.unwrap(Redactor.pixelate(base, region: bigger.frame, blockSize: 6)) else { return }
        t.equal(bigger.patch()?.width, 60)
        let d = maxDiff(render: out, rect: bigger.frame, patch: fresh)
        t.isTrue(d <= 2, "resized patch differs from a fresh render by \(d)")
    },
    TestCase("patchIsCachedUntilFrameOrStrengthChanges") { t in
        let base = noiseBase()
        var r = RedactionAnnotation(frame: CGRect(x: 5, y: 5, width: 40, height: 30), source: base, style: style(.blur))
        let first = r.patch()
        t.isTrue(first != nil && first === r.patch(), "same frame + strength → same cached patch")
        r.style.blurRadius = 20
        t.isFalse(first === r.patch(), "a new strength re-renders")
        let second = r.patch()
        r.frame.origin.x += 1
        t.isFalse(second === r.patch(), "a new frame re-renders")
    },
    TestCase("redactionIsAlwaysOpaque") { t in
        var s = style(.blur)
        s.opacity = 0.3   // e.g. the default style after the user faded an arrow
        var r = RedactionAnnotation(frame: CGRect(x: 0, y: 0, width: 10, height: 10), source: noiseBase(), style: s)
        t.approxEqual(Double(r.style.opacity), 1)
        r.style.opacity = 0.5
        t.approxEqual(Double(r.style.opacity), 1)
    },
    TestCase("redactionFollowsTheBaseIntoACrop") { t in
        let base = noiseBase()
        var doc = EditorDocument(baseImage: base)
        doc.add(RedactionAnnotation(frame: CGRect(x: 50, y: 40, width: 30, height: 20), source: base, style: style(.pixelate)))
        guard let cropped = t.unwrap(doc.cropped(to: CGRect(x: 40, y: 30, width: 60, height: 50))),
              let r = t.unwrap(cropped.annotations.first as? RedactionAnnotation) else { return }
        t.isTrue(r.source === cropped.baseImage, "rebased onto the cropped image")
        t.equal(r.frame, CGRect(x: 10, y: 10, width: 30, height: 20))
        // Same pixels as before the crop: the cropped base holds the same content at the new place.
        guard let before = t.unwrap(Redactor.pixelate(base, region: CGRect(x: 50, y: 40, width: 30, height: 20), blockSize: 12)),
              let after = t.unwrap(r.patch()) else { return }
        let a = pixels(before), b = pixels(after)
        t.isTrue(a.count == b.count && zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= 2 }, "crop keeps the redaction's look")
    },
    TestCase("redactionMapsToTheToolOfItsMode") { t in
        let base = noiseBase()
        for mode in RedactionMode.allCases {
            let r = RedactionAnnotation(frame: CGRect(x: 0, y: 0, width: 8, height: 8), source: base, style: style(mode))
            t.equal(EditorTool.maker(of: r), mode.tool)
            t.equal(mode.tool.redactionMode, mode)
        }
        t.isNil(EditorTool.arrow.redactionMode)
    },
    TestCase("blackoutIsSolidBlackAndHasNoPatch") { t in
        let base = noiseBase()
        var doc = EditorDocument(baseImage: base)
        let r = RedactionAnnotation(frame: CGRect(x: 20.4, y: 10.6, width: 30, height: 20), source: base, style: style(.blackout))
        doc.add(r)
        t.isNil(r.patch())
        guard let out = t.unwrap(DocumentRenderer.render(doc)),
              let box = t.unwrap(out.cropping(to: CGRect(x: 20, y: 10, width: 31, height: 21))) else { return }
        // Snapped outward to whole pixels, so no sliver of the original survives at the edges.
        t.isTrue(stride(from: 0, to: pixels(box).count, by: 4).allSatisfy { i in
            let p = pixels(box); return p[i] == 0 && p[i + 1] == 0 && p[i + 2] == 0 && p[i + 3] == 255
        }, "every pixel of the (outward-snapped) box is opaque black")
    },
    TestCase("switchingModeConvertsTheSelectedRedactionInPlace") { t in
        let base = noiseBase()
        let c = EditorCanvasView(document: EditorDocument(baseImage: base))
        c.insert(RedactionAnnotation(frame: CGRect(x: 10, y: 10, width: 40, height: 30), source: base, style: style(.blur)))
        let id = c.currentDocument().annotations[0].id
        c.applyStyleEdit({ $0.redactionMode = .pixelate })
        t.equal(c.selectedTools, [.pixelate])
        t.equal(c.currentDocument().annotations[0].id, id, "same object, same place in the stack")
        c.applyStyleEdit({ $0.redactionMode = .blackout })
        t.equal(c.selectedTools, [.blackout])
        c.undo()
        t.equal(EditorTool.maker(of: c.currentDocument().annotations[0]), .pixelate, "each conversion is one undo step")
    },
    TestCase("strengthEditsRestyleTheSelectedRedaction") { t in
        let base = noiseBase()
        let c = EditorCanvasView(document: EditorDocument(baseImage: base))
        c.insert(RedactionAnnotation(frame: CGRect(x: 10, y: 10, width: 40, height: 30), source: base, style: style(.blur)))
        let before = (c.currentDocument().annotations[0] as? RedactionAnnotation)?.patch()
        for v in [16, 24, 32] { c.applyStyleEdit({ $0.blurRadius = CGFloat(v) }, group: "redactionStrength") }
        c.endStyleEditGroup()
        guard let r = t.unwrap(c.currentDocument().annotations[0] as? RedactionAnnotation) else { return }
        t.approxEqual(Double(r.style.blurRadius), 32)
        t.isFalse(before === r.patch(), "the patch re-rendered at the new strength")
        c.undo()
        t.approxEqual(Double(c.currentDocument().annotations[0].style.blurRadius), 12, tol: 1e-9)
    },
    TestCase("legacyStyleDecodesRedactionDefaults") { t in
        let json = """
        {"strokeColor": {"r": 1, "g": 0, "b": 0, "a": 1},
         "fillColor": {"r": 1, "g": 0, "b": 0, "a": 0.25}, "lineWidth": 4, "fontSize": 24}
        """
        do {
            let s = try JSONDecoder().decode(AnnotationStyle.self, from: Data(json.utf8))
            t.equal(s.redactionMode, .blur)
            t.approxEqual(Double(s.blurRadius), 12)
            t.approxEqual(Double(s.pixelSize), 12)
        } catch { t.fail("legacy decode threw: \(error)") }
    },
    TestCase("redactionFieldsRoundTripAndClamp") { t in
        var s = AnnotationStyle.default
        s.redactionMode = .pixelate; s.blurRadius = 30; s.pixelSize = 20
        do {
            let d = try JSONDecoder().decode(AnnotationStyle.self, from: JSONEncoder().encode(s))
            t.isTrue(d == s, "round-trip keeps the redaction fields")
            s.blurRadius = 500; s.pixelSize = 0
            let c = try JSONDecoder().decode(AnnotationStyle.self, from: JSONEncoder().encode(s))
            t.approxEqual(Double(c.blurRadius), 40)
            t.approxEqual(Double(c.pixelSize), 4)
            let bad = try JSONDecoder().decode(AnnotationStyle.self, from: Data("""
            {"strokeColor": {"r": 1, "g": 0, "b": 0, "a": 1}, "fillColor": {"r": 1, "g": 0, "b": 0, "a": 0.25},
             "lineWidth": 4, "fontSize": 24, "redactionMode": "smudge"}
            """.utf8))
            t.equal(bad.redactionMode, .blur, "an unknown mode falls back to Blur")
        } catch { t.fail("round-trip threw: \(error)") }
    },
]
