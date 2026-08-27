import TestKit
@testable import OverlayKit

/// n white pixels followed by n black pixels, RGBA8.
private func halfWhiteHalfBlack(_ n: Int) -> [UInt8] {
    var buf: [UInt8] = []
    for _ in 0..<n { buf += [255, 255, 255, 255] }
    for _ in 0..<n { buf += [0, 0, 0, 255] }
    return buf
}

let bandLuminanceTests: [TestCase] = [
    TestCase("percentileAllWhiteIsOneEverywhere") { t in
        let white = [UInt8](repeating: 255, count: 40)
        for p in [0.0, 0.1, 0.5, 0.9, 1.0] {
            t.approxEqual(BandLuminance.percentile(rgba: white, pixelCount: 10, p: p), 1.0, tol: 1e-9)
        }
    },
    TestCase("percentileAllBlackIsZeroEverywhere") { t in
        var black = [UInt8](repeating: 0, count: 40)
        for i in 0..<10 { black[i*4 + 3] = 255 }
        for p in [0.0, 0.1, 0.5, 0.9, 1.0] {
            t.approxEqual(BandLuminance.percentile(rgba: black, pixelCount: 10, p: p), 0.0, tol: 1e-9)
        }
    },
    TestCase("percentileBimodalSplitsLowAndHigh") { t in
        let buf = halfWhiteHalfBlack(50)
        t.approxEqual(BandLuminance.percentile(rgba: buf, pixelCount: 100, p: 0.10), 0.0, tol: 1e-9)
        t.approxEqual(BandLuminance.percentile(rgba: buf, pixelCount: 100, p: 0.90), 1.0, tol: 1e-9)
    },
    TestCase("percentileEmptyOrShortBufferIsZero") { t in
        t.approxEqual(BandLuminance.percentile(rgba: [], pixelCount: 0, p: 0.5), 0.0, tol: 1e-9)
        // Buffer claims 4 pixels but only holds 2.
        t.approxEqual(BandLuminance.percentile(rgba: [UInt8](repeating: 255, count: 8),
                                               pixelCount: 4, p: 0.5), 0.0, tol: 1e-9)
    },
    TestCase("percentileClampsPOutOfRange") { t in
        let buf = halfWhiteHalfBlack(50)
        t.approxEqual(BandLuminance.percentile(rgba: buf, pixelCount: 100, p: -3), 0.0, tol: 1e-9)
        t.approxEqual(BandLuminance.percentile(rgba: buf, pixelCount: 100, p: 7), 1.0, tol: 1e-9)
    },
    TestCase("extremesOnBimodalBandSeesBothEnds") { t in
        let e = BandLuminance.extremes(rgba: halfWhiteHalfBlack(50), pixelCount: 100)
        t.approxEqual(e.dark, 0.0, tol: 1e-9)
        t.approxEqual(e.bright, 1.0, tol: 1e-9)
    },
]
