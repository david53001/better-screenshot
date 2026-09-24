import TestKit
import CoreGraphics
@testable import EditorKit

private func makeBase() -> CGImage {
    let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    return ctx.makeImage()!
}

/// White base with 2px black vertical stripes every 4px — maximal hard edges,
/// so any working redaction must measurably destroy detail.
private func makeStripedBase() -> CGImage {
    let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    var x = 0
    while x < 100 { ctx.fill(CGRect(x: x, y: 0, width: 2, height: 100)); x += 4 }
    return ctx.makeImage()!
}

/// RGBA8 readback of an image (premultiplied-last, device RGB).
private func pixels(_ image: CGImage) -> [UInt8] {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buf
}

/// Number of horizontally adjacent pixel pairs whose red channels differ by
/// more than 128 — a proxy for "readable hard edges" in the region.
private func highContrastPairCount(_ image: CGImage) -> Int {
    let w = image.width, h = image.height
    let buf = pixels(image)
    var count = 0
    for y in 0..<h {
        for x in 0..<(w - 1) {
            let a = Int(buf[(y * w + x) * 4])
            let b = Int(buf[(y * w + x + 1) * 4])
            if abs(a - b) > 128 { count += 1 }
        }
    }
    return count
}

/// Deterministic RGB noise — every pixel differs from its neighbours.
private func makeNoiseBase(_ n: Int = 400) -> CGImage {
    var buf = [UInt8](repeating: 255, count: n * n * 4)
    var seed: UInt32 = 7
    for i in 0..<(n * n) {
        for c in 0..<3 { seed = seed &* 1664525 &+ 1013904223; buf[i * 4 + c] = UInt8(truncatingIfNeeded: seed >> 24) }
    }
    return CGContext(data: &buf, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}

/// Local variation: mean absolute difference between horizontally and vertically adjacent
/// pixels (red channel). Pixelate keeps whole blocks of one colour, so fewer, bigger blocks
/// mean fewer changes between neighbours.
private func localVariation(_ image: CGImage) -> Double {
    let w = image.width, h = image.height, buf = pixels(image)
    var sum = 0, count = 0
    for y in 0..<(h - 1) {
        for x in 0..<(w - 1) {
            let v = Int(buf[(y * w + x) * 4])
            sum += abs(v - Int(buf[(y * w + x + 1) * 4])) + abs(v - Int(buf[((y + 1) * w + x) * 4]))
            count += 2
        }
    }
    return Double(sum) / Double(count)
}

/// Variance of the red channel over the patch. Lower = flatter = less of the original survives.
/// (A strong blur's neighbour differences all round to the 8-bit floor, so blur uses this.)
private func variance(_ image: CGImage) -> Double {
    let buf = pixels(image)
    let reds = stride(from: 0, to: buf.count, by: 4).map { Double(buf[$0]) }
    let mean = reds.reduce(0, +) / Double(reds.count)
    return reds.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(reds.count)
}

let redactorTests: [TestCase] = [
    TestCase("higherBlurStrengthLeavesLessDetail") { t in
        let base = makeNoiseBase(), region = CGRect(x: 120, y: 140, width: 160, height: 120)
        let v = [2, 6, 12, 24, 40].compactMap { Redactor.blur(base, region: region, radius: CGFloat($0)) }.map(variance)
        t.equal(v.count, 5)
        t.isTrue(zip(v, v.dropFirst()).allSatisfy { $0 > $1 }, "variance falls as the radius grows: \(v)")
    },
    TestCase("biggerPixelsLeaveLessDetail") { t in
        let base = makeNoiseBase(), region = CGRect(x: 120, y: 140, width: 160, height: 120)
        let v = [4, 8, 16, 32, 48].compactMap { Redactor.pixelate(base, region: region, blockSize: CGFloat($0)) }.map(localVariation)
        t.equal(v.count, 5)
        t.isTrue(zip(v, v.dropFirst()).allSatisfy { $0 > $1 }, "variance falls as the blocks grow: \(v)")
    },
    TestCase("pixelatePatchHasRegionSize") { t in
        let region = CGRect(x: 10, y: 10, width: 40, height: 30)
        let patch = Redactor.pixelate(makeBase(), region: region, blockSize: 10)
        guard let p = t.unwrap(patch) else { return }
        t.equal(p.width, 40)
        t.equal(p.height, 30)
    },
    TestCase("blurPatchHasRegionSize") { t in
        let region = CGRect(x: 0, y: 0, width: 20, height: 20)
        let patch = Redactor.blur(makeBase(), region: region, radius: 8)
        guard let p = t.unwrap(patch) else { return }
        t.equal(p.width, 20)
        t.equal(p.height, 20)
    },
    TestCase("pixelateDestroysDetail") { t in
        let base = makeStripedBase()
        let region = CGRect(x: 10, y: 10, width: 40, height: 30)
        guard let patch = t.unwrap(Redactor.pixelate(base, region: region, blockSize: 12)),
              let original = t.unwrap(base.cropping(to: region)) else { return }
        let before = highContrastPairCount(original)
        let after = highContrastPairCount(patch)
        t.isTrue(before > 100, "striped source must start with strong edges (got \(before))")
        t.isTrue(after < before / 10, "pixelation left \(after) of \(before) hard edges")
    },
    TestCase("blurDestroysDetail") { t in
        let base = makeStripedBase()
        let region = CGRect(x: 10, y: 10, width: 40, height: 30)
        guard let patch = t.unwrap(Redactor.blur(base, region: region, radius: 12)),
              let original = t.unwrap(base.cropping(to: region)) else { return }
        let before = highContrastPairCount(original)
        let after = highContrastPairCount(patch)
        t.isTrue(before > 100, "striped source must start with strong edges (got \(before))")
        t.isTrue(after < before / 10, "blur left \(after) of \(before) hard edges")
    },
]
