import TestKit
import CoreGraphics
@testable import CaptureKit

private func grayImage(width: Int, height: Int, background: CGFloat, ink: CGFloat, rects: [CGRect]) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: background, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setFillColor(gray: ink, alpha: 1)
    // Rects are given top-left; CG draws bottom-left.
    for r in rects { ctx.fill(CGRect(x: r.minX, y: CGFloat(height) - r.maxY, width: r.width, height: r.height)) }
    return ctx.makeImage()!
}

let inkMapTests: [TestCase] = [
    TestCase("otsuSplitsTwoTones") { t in
        let threshold = InkMap.otsu([20, 20, 20, 230, 230, 230, 230])
        t.isTrue(threshold > 20 && threshold <= 230, "threshold \(threshold)")
    },
    TestCase("blobsAreEightConnectedLeftToRight") { t in
        // A diagonal pair touches corner to corner (one blob); a separate dot.
        var ink = [Bool](repeating: false, count: 6 * 3)
        ink[0 * 6 + 0] = true; ink[1 * 6 + 1] = true   // diagonal
        ink[1 * 6 + 4] = true                          // dot
        let blobs = InkMap(width: 6, height: 3, ink: ink).blobs()
        t.equal(blobs.count, 2)
        t.equal(blobs.map { $0.box }, [CGRect(x: 0, y: 0, width: 2, height: 2), CGRect(x: 4, y: 1, width: 1, height: 1)])
    },
    TestCase("longestRunFindsABar") { t in
        var ink = [Bool](repeating: false, count: 10 * 3)
        for x in 1..<8 { ink[1 * 10 + x] = true }
        t.equal(InkMap(width: 10, height: 3, ink: ink).longestRun(), 7)
    },
    TestCase("cropsTopLeftAndFindsInkOnEitherBackground") { t in
        let bar = CGRect(x: 10, y: 4, width: 20, height: 3)
        for (background, ink) in [(CGFloat(1), CGFloat(0)), (0, 1)] {
            let image = grayImage(width: 40, height: 20, background: background, ink: ink, rects: [bar])
            guard let map = InkMap(image, rect: CGRect(x: 5, y: 0, width: 30, height: 12)) else {
                t.fail("no map"); continue
            }
            // In the crop the bar starts 5 px in.
            t.equal(map.blobs().map { $0.box }, [CGRect(x: 5, y: 4, width: 20, height: 3)])
        }
    },
    TestCase("holesAreTheBackgroundInkWallsOff") { t in
        // A ring (`o`) has one hole; a ring with a bar across the middle (`θ`)
        // two; a C-shape none.
        func map(_ rows: [String]) -> (InkMap, [Int], CGRect) {
            let w = rows[0].count, h = rows.count
            let ink = rows.flatMap { $0.map { $0 == "#" } }
            return (InkMap(width: w, height: h, ink: ink), ink.indices.filter { ink[$0] }, CGRect(x: 0, y: 0, width: w, height: h))
        }
        let ring = map(["#####", "#...#", "#...#", "#...#", "#####"])
        t.equal(ring.0.holes(of: ring.1, in: ring.2).count, 1)
        let theta = map(["#####", "#...#", "#####", "#...#", "#####"])
        t.equal(theta.0.holes(of: theta.1, in: theta.2).count, 2)
        let c = map(["#####", "#....", "#....", "#....", "#####"])
        t.equal(c.0.holes(of: c.1, in: c.2).count, 0)
    },
]
