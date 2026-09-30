import TestKit
import CoreGraphics
@testable import CaptureKit

private func makeImage(width: Int, height: Int) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

let imageCropperTests: [TestCase] = [
    TestCase("frozenScreenCutsTheSelectionAt2x") { t in
        // A 100 × 50 pt display at (0,0), frozen at 2x. Cocoa global rect (10, 20, 30, 10) is 20 pt below the
        // display's top edge: pixels x 20, y (50 − 30) × 2 = 40, 60 × 20.
        let frozen = FrozenScreen(displayID: 1, image: makeImage(width: 200, height: 100),
                                  displayFrame: CGRect(x: 0, y: 0, width: 100, height: 50))
        guard let c = t.unwrap(frozen.crop(CGRect(x: 10, y: 20, width: 30, height: 10))) else { return }
        t.equal(c.width, 60)
        t.equal(c.height, 20)
        t.isNil(frozen.crop(CGRect(x: 500, y: 500, width: 10, height: 10)), "off the display")
    },
    TestCase("cropsToExactPixelRect") { t in
        let img = makeImage(width: 200, height: 100)
        let cropped = ImageCropper.crop(img, to: CGRect(x: 10, y: 20, width: 50, height: 30))
        guard let c = t.unwrap(cropped) else { return }
        t.equal(c.width, 50)
        t.equal(c.height, 30)
    },
    TestCase("clampsRectToImageBounds") { t in
        let img = makeImage(width: 100, height: 100)
        // Rect partially outside → clamp to 100x100 area, here from (90,90) size 50→ clamps to 10x10
        let cropped = ImageCropper.crop(img, to: CGRect(x: 90, y: 90, width: 50, height: 50))
        guard let c = t.unwrap(cropped) else { return }
        t.equal(c.width, 10)
        t.equal(c.height, 10)
    },
    TestCase("returnsNilForZeroAreaRect") { t in
        let img = makeImage(width: 100, height: 100)
        t.isNil(ImageCropper.crop(img, to: CGRect(x: 0, y: 0, width: 0, height: 0)))
    },
]
