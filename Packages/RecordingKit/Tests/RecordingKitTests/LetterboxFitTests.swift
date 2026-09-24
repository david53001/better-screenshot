import TestKit
import CoreGraphics
@testable import RecordingKit

let letterboxFitTests: [TestCase] = [
    TestCase("sameAspectFillsTheOutput") { t in
        t.equal(LetterboxFit.rect(content: CGSize(width: 640, height: 400),
                                  output: CGSize(width: 1280, height: 800)),
                CGRect(x: 0, y: 0, width: 1280, height: 800))
    },
    TestCase("tallerContentIsPillarboxedAndCentred") { t in
        // 300×520 into 1280×800 → height-bound: 461.5… wide, centred.
        let r = LetterboxFit.rect(content: CGSize(width: 300, height: 520),
                                  output: CGSize(width: 1280, height: 800))
        t.equal(r.height, 800)
        t.equal(r.width, 462)
        t.equal(r.minX, 409, "(1280 − 462) / 2")
        t.equal(r.minY, 0)
    },
    TestCase("widerContentIsLetterboxedAndCentred") { t in
        let r = LetterboxFit.rect(content: CGSize(width: 1600, height: 400),
                                  output: CGSize(width: 800, height: 600))
        t.equal(r, CGRect(x: 0, y: 200, width: 800, height: 200))
    },
    TestCase("smallContentScalesUp") { t in
        t.equal(LetterboxFit.rect(content: CGSize(width: 100, height: 50),
                                  output: CGSize(width: 1000, height: 500)),
                CGRect(x: 0, y: 0, width: 1000, height: 500))
    },
    TestCase("degenerateContentFallsBackToTheWholeOutput") { t in
        let out = CGSize(width: 1280, height: 800)
        t.equal(LetterboxFit.rect(content: .zero, output: out), CGRect(origin: .zero, size: out))
        t.equal(LetterboxFit.rect(content: CGSize(width: 10, height: 0), output: out),
                CGRect(origin: .zero, size: out))
    },
]
