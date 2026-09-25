import CoreGraphics
import TestKit
@testable import CaptureKit

// A 1440×900 laptop screen: menu bar 25pt on top, Dock 70pt at the bottom (AppKit's y goes up).
private let laptop = CGRect(x: 0, y: 70, width: 1440, height: 805)
// An external screen to the right of it.
private let external = CGRect(x: 1440, y: 0, width: 2560, height: 1415)

let windowPlacementTests: [TestCase] = [
    TestCase("centresExactlyInTheVisibleScreen") { t in
        let f = WindowPlacement.centred(CGSize(width: 1000, height: 600), in: laptop)
        t.equal(f, CGRect(x: 220, y: 173, width: 1000, height: 600))
        t.equal(f.midX, laptop.midX)
        t.approxEqual(Double(f.midY), Double(laptop.midY), tol: 0.5)
    },
    TestCase("centresOnAScreenThatIsNotAtTheOrigin") { t in
        let f = WindowPlacement.centred(CGSize(width: 960, height: 720), in: external)
        t.equal(f.midX, external.midX)
        t.isTrue(external.contains(f))
    },
    TestCase("aWindowBiggerThanTheScreenShrinksToIt") { t in
        let f = WindowPlacement.centred(CGSize(width: 3000, height: 2000), in: laptop)
        t.equal(f, laptop)
    },
    TestCase("firstOpenUsesTheDefaultSize") { t in
        let o = WindowPlacement.opening(remembered: nil, defaultSize: CGSize(width: 900, height: 700),
                                        minSize: CGSize(width: 600, height: 400), visible: laptop)
        t.equal(o.frame.size, CGSize(width: 900, height: 700))
        t.isFalse(o.enterFullScreen)
    },
    TestCase("reopensAtTheRememberedSizeCentred") { t in
        let memo = WindowPlacement.Memo(width: 1200, height: 760, mode: .normal)
        let o = WindowPlacement.opening(remembered: memo, defaultSize: CGSize(width: 900, height: 700),
                                        minSize: .zero, visible: laptop)
        t.equal(o.frame, WindowPlacement.centred(CGSize(width: 1200, height: 760), in: laptop))
        t.isFalse(o.enterFullScreen)
    },
    TestCase("aRememberedSizeNeverGoesBelowTheMinimum") { t in
        let memo = WindowPlacement.Memo(width: 500, height: 300, mode: .normal)
        let o = WindowPlacement.opening(remembered: memo, defaultSize: .zero,
                                        minSize: CGSize(width: 884, height: 440), visible: laptop)
        t.equal(o.frame.size, CGSize(width: 884, height: 440))
    },
    TestCase("aFilledWindowReopensCoveringTheWholeScreen") { t in
        // Remembered on a big external screen, reopened on the laptop: it fills the laptop.
        let memo = WindowPlacement.Memo(width: 2560, height: 1415, mode: .fill)
        let o = WindowPlacement.opening(remembered: memo, defaultSize: CGSize(width: 900, height: 700),
                                        minSize: .zero, visible: laptop)
        t.equal(o.frame, laptop)
        t.isFalse(o.enterFullScreen)
    },
    TestCase("aFullScreenWindowReopensInFullScreenWithItsNormalFrameCentred") { t in
        let memo = WindowPlacement.Memo(width: 1000, height: 700, mode: .fullScreen)
        let o = WindowPlacement.opening(remembered: memo, defaultSize: CGSize(width: 900, height: 600),
                                        minSize: .zero, visible: laptop)
        t.isTrue(o.enterFullScreen)
        t.equal(o.frame, WindowPlacement.centred(CGSize(width: 1000, height: 700), in: laptop))
    },
    TestCase("aBrokenMemoFallsBackToTheDefault") { t in
        let memo = WindowPlacement.Memo(width: 0, height: 0, mode: .fullScreen)
        let o = WindowPlacement.opening(remembered: memo, defaultSize: CGSize(width: 900, height: 600),
                                        minSize: .zero, visible: laptop)
        t.equal(o.frame.size, CGSize(width: 900, height: 600))
        t.isFalse(o.enterFullScreen)
    },
    TestCase("closingInFullScreenRemembersTheSizeFromBeforeIt") { t in
        let m = WindowPlacement.memo(frameSize: CGSize(width: 1440, height: 900),
                                     normalSize: CGSize(width: 1000, height: 700),
                                     isFullScreen: true, visible: laptop)
        t.equal(m, WindowPlacement.Memo(width: 1000, height: 700, mode: .fullScreen))
    },
    TestCase("closingAWindowThatCoversTheScreenRemembersFill") { t in
        let m = WindowPlacement.memo(frameSize: CGSize(width: 1440, height: 800), normalSize: nil,
                                     isFullScreen: false, visible: laptop)
        t.equal(m.mode, .fill)
    },
    TestCase("closingAnOrdinaryWindowRemembersItsSize") { t in
        let m = WindowPlacement.memo(frameSize: CGSize(width: 1100, height: 760), normalSize: nil,
                                     isFullScreen: false, visible: laptop)
        t.equal(m, WindowPlacement.Memo(width: 1100, height: 760, mode: .normal))
    },
    TestCase("aWindowOnlyAsWideAsTheScreenIsNotFill") { t in
        let m = WindowPlacement.memo(frameSize: CGSize(width: 1440, height: 600), normalSize: nil,
                                     isFullScreen: false, visible: laptop)
        t.equal(m.mode, .normal)
    },
]
