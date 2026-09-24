import TestKit
import AppKit
@testable import EditorKit

/// Row index (top = 0) of the first/last rows containing any non-white pixel.
private func inkRows(_ image: CGImage) -> (first: Int, last: Int)? {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    // CGContext memory is top row first for this bitmap layout.
    var rows: [Int] = []
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            if buf[i] < 200 || buf[i + 1] < 200 || buf[i + 2] < 200 { rows.append(y); break }
        }
    }
    guard let f = rows.first, let l = rows.last else { return nil }
    return (f, l)
}

private func whiteImage(_ w: Int, _ h: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

let textFontTests: [TestCase] = [
    TestCase("presetsResolveToSystemDesigns") { t in
        let mono = TextFont.font(family: TextFont.mono, size: 20, bold: false, italic: false)
        t.isTrue(mono.isFixedPitch, "Mono preset should be fixed-pitch")
        t.approxEqual(Double(mono.pointSize), 20)
        let italic = TextFont.font(family: TextFont.system, size: 20, bold: false, italic: true)
        t.isTrue(italic.fontDescriptor.symbolicTraits.contains(.italic), "italic trait")
    },
    TestCase("installedFamilyHonoursBoldAndItalic") { t in
        let f = TextFont.font(family: "Helvetica", size: 30, bold: true, italic: true)
        t.equal(f.familyName, "Helvetica")
        let traits = NSFontManager.shared.traits(of: f)
        t.isTrue(traits.contains(.boldFontMask), "bold")
        t.isTrue(traits.contains(.italicFontMask), "italic")
    },
    TestCase("unknownFamilyFallsBackToSystemFont") { t in
        let f = TextFont.font(family: "No Such Font 123", size: 18, bold: false, italic: false)
        t.approxEqual(Double(f.pointSize), 18)
        t.equal(f.familyName, NSFont.systemFont(ofSize: 18).familyName)
    },
    TestCase("installedFamiliesListsRealFontsOnly") { t in
        let fams = TextFont.installedFamilies
        t.isTrue(fams.contains("Helvetica"))
        t.isFalse(fams.contains { $0.hasPrefix(".") })
    },
    TestCase("differentFamiliesMeasureDifferently") { t in
        var a = AnnotationStyle.default; a.fontFamily = TextFont.mono
        var b = AnnotationStyle.default; b.fontFamily = TextFont.system
        let text = "iiiiiiiiii"
        let wa = TextAnnotation(text: text, origin: .zero, style: a).boundingBox().width
        let wb = TextAnnotation(text: text, origin: .zero, style: b).boundingBox().width
        t.isTrue(wa > wb * 1.3, "mono i's are much wider (\(wa) vs \(wb))")
    },
    TestCase("textBoxWidthIsTheWrapWidth") { t in
        let ta = TextAnnotation(text: "Hi", origin: .zero, wrapWidth: 300)
        t.approxEqual(Double(ta.boundingBox().width), 300)
    },
    TestCase("wrappedTextRendersDownwardFromOrigin") { t in
        // A 3-line wrapped box at y=20 must put ink just below y=20 and keep going
        // down — an unflipped draw would land it at the bottom or upside down.
        var doc = EditorDocument(baseImage: whiteImage(300, 300))
        var s = AnnotationStyle.default; s.strokeColor = RGBAColor(r: 0, g: 0, b: 0, a: 1)
        let ta = TextAnnotation(text: "alpha beta gamma delta epsilon zeta", origin: CGPoint(x: 10, y: 20),
                                style: s, wrapWidth: 120)
        doc.add(ta)
        guard let out = t.unwrap(DocumentRenderer.render(doc)), let ink = t.unwrap(inkRows(out)) else { return }
        t.isTrue(ink.first >= 20 && ink.first < 40, "first ink row \(ink.first) near origin y=20")
        t.isTrue(ink.last > 20 + 60, "wraps onto several lines (last ink row \(ink.last))")
        t.isTrue(ink.last <= Int(ta.boundingBox().maxY) + 2, "ink stays inside the box")
    },
]
