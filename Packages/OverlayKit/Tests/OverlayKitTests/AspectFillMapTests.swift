import CoreGraphics
import TestKit
@testable import OverlayKit

let aspectFillMapTests: [TestCase] = [
    TestCase("aspectFillMatchingAspectIsPureScale") { t in
        // 2:1 image into a 2:1 card — nothing is cropped, only scaled.
        let r = AspectFillMap.sourceRect(cardSize: CGSize(width: 200, height: 100),
                                         imagePixelSize: CGSize(width: 400, height: 200),
                                         cardRect: CGRect(x: 0, y: 50, width: 200, height: 50))
        t.approxEqual(Double(r.minX), 0, tol: 1e-9)
        t.approxEqual(Double(r.minY), 100, tol: 1e-9)
        t.approxEqual(Double(r.width), 400, tol: 1e-9)
        t.approxEqual(Double(r.height), 100, tol: 1e-9)
    },
    TestCase("aspectFillWideImageCropsSides") { t in
        // 400x100 into a square card: the sides fall outside, full height is visible.
        let r = AspectFillMap.sourceRect(cardSize: CGSize(width: 200, height: 200),
                                         imagePixelSize: CGSize(width: 400, height: 100),
                                         cardRect: CGRect(x: 0, y: 0, width: 200, height: 200))
        t.isTrue(r.minX > 0, "left edge cropped")
        t.approxEqual(Double(r.minX), 150, tol: 1e-9)
        t.approxEqual(Double(r.width), 100, tol: 1e-9)
        t.approxEqual(Double(r.minY), 0, tol: 1e-9)
        t.approxEqual(Double(r.height), 100, tol: 1e-9)
    },
    TestCase("aspectFillTallImageCropsTopAndBottom") { t in
        let r = AspectFillMap.sourceRect(cardSize: CGSize(width: 200, height: 200),
                                         imagePixelSize: CGSize(width: 100, height: 400),
                                         cardRect: CGRect(x: 0, y: 0, width: 200, height: 200))
        t.isTrue(r.minY > 0, "top edge cropped")
        t.approxEqual(Double(r.minY), 150, tol: 1e-9)
        t.approxEqual(Double(r.height), 100, tol: 1e-9)
        t.approxEqual(Double(r.minX), 0, tol: 1e-9)
        t.approxEqual(Double(r.width), 100, tol: 1e-9)
    },
    TestCase("aspectFillBottomBandMapsToBottomOfImage") { t in
        // Both spaces are top-left origin, so the button strip must land at the image's bottom.
        let r = AspectFillMap.sourceRect(cardSize: CGSize(width: 200, height: 200),
                                         imagePixelSize: CGSize(width: 400, height: 400),
                                         cardRect: CGRect(x: 0, y: 170, width: 200, height: 30))
        t.approxEqual(Double(r.minY), 340, tol: 1e-9)
        t.approxEqual(Double(r.maxY), 400, tol: 1e-9)
        t.approxEqual(Double(r.width), 400, tol: 1e-9)
    },
    TestCase("aspectFillClampsRectOutsideTheCard") { t in
        let r = AspectFillMap.sourceRect(cardSize: CGSize(width: 200, height: 200),
                                         imagePixelSize: CGSize(width: 200, height: 200),
                                         cardRect: CGRect(x: -50, y: 150, width: 300, height: 200))
        t.approxEqual(Double(r.minX), 0, tol: 1e-9)
        t.approxEqual(Double(r.maxX), 200, tol: 1e-9)
        t.approxEqual(Double(r.minY), 150, tol: 1e-9)
        t.approxEqual(Double(r.maxY), 200, tol: 1e-9)
    },
    TestCase("aspectFillDegenerateSizesAreZero") { t in
        let unit = CGRect(x: 0, y: 0, width: 10, height: 10)
        t.equal(AspectFillMap.sourceRect(cardSize: .zero,
                                         imagePixelSize: CGSize(width: 100, height: 100),
                                         cardRect: unit), .zero)
        t.equal(AspectFillMap.sourceRect(cardSize: CGSize(width: 100, height: 100),
                                         imagePixelSize: .zero,
                                         cardRect: unit), .zero)
        t.equal(AspectFillMap.sourceRect(cardSize: CGSize(width: 100, height: 100),
                                         imagePixelSize: CGSize(width: 100, height: 100),
                                         cardRect: .zero), .zero)
    },
]
