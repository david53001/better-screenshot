import CoreGraphics
import TestKit
@testable import OverlayKit

let overlayLabelTests: [TestCase] = [
    TestCase("selectionChipSitsAboveTheSelectionWhenThereIsRoom") { t in
        let p = OverlayLabelLayout.selectionChipOrigin(
            selection: CGRect(x: 100, y: 100, width: 200, height: 100),
            chipSize: CGSize(width: 80, height: 22),
            bounds: CGRect(x: 0, y: 0, width: 900, height: 600))
        t.equal(p, CGPoint(x: 100, y: 206))   // outside: 6pt above maxY 200
    },
    TestCase("selectionChipGoesBelowNearTheTopEdge") { t in
        // Selection reaches the top of the screen: the chip moves below it, still outside.
        let p = OverlayLabelLayout.selectionChipOrigin(
            selection: CGRect(x: 300, y: 380, width: 400, height: 220),
            chipSize: CGSize(width: 80, height: 22),
            bounds: CGRect(x: 0, y: 0, width: 900, height: 600))
        t.equal(p, CGPoint(x: 300, y: 352))   // 380 - 6 - 22
    },
    TestCase("selectionChipGoesInsideWhenTheSelectionFillsTheHeight") { t in
        let p = OverlayLabelLayout.selectionChipOrigin(
            selection: CGRect(x: 0, y: 0, width: 500, height: 600),
            chipSize: CGSize(width: 80, height: 22),
            bounds: CGRect(x: 0, y: 0, width: 900, height: 600))
        t.equal(p, CGPoint(x: 0, y: 572))     // 600 - 6 - 22, inside the top-left corner
    },
    TestCase("selectionChipStaysOnScreenHorizontally") { t in
        let p = OverlayLabelLayout.selectionChipOrigin(
            selection: CGRect(x: 880, y: 100, width: 20, height: 20),
            chipSize: CGSize(width: 80, height: 22),
            bounds: CGRect(x: 0, y: 0, width: 900, height: 600))
        t.equal(p.x, 820)
    },
    TestCase("selectionChipRespectsANonZeroBoundsOrigin") { t in
        let p = OverlayLabelLayout.selectionChipOrigin(
            selection: CGRect(x: -20, y: 100, width: 50, height: 50),
            chipSize: CGSize(width: 80, height: 22),
            bounds: CGRect(x: 0, y: 0, width: 900, height: 600))
        t.equal(p.x, 0)
    },
    TestCase("titleChipKeepsShortTitlesAtTheirNaturalWidth") { t in
        let r = OverlayLabelLayout.titleChip(window: CGRect(x: 0, y: 0, width: 400, height: 300),
                                             textSize: CGSize(width: 100, height: 16),
                                             padding: 6, margin: 12)!
        t.equal(r.text, CGRect(x: 150, y: 142, width: 100, height: 16))
        t.equal(r.chip, CGRect(x: 144, y: 136, width: 112, height: 28))
    },
    TestCase("titleChipNeverRunsPastTheWindow") { t in
        let win = CGRect(x: 470, y: 40, width: 380, height: 300)
        let r = OverlayLabelLayout.titleChip(window: win, textSize: CGSize(width: 520, height: 16),
                                             padding: 6, margin: 12)!
        t.isTrue(r.chip.minX >= win.minX + 12 - 1e-9, "left edge inside the window margin")
        t.isTrue(r.chip.maxX <= win.maxX - 12 + 1e-9, "right edge inside the window margin")
        t.approxEqual(Double(r.text.width), 380 - 24 - 12)
    },
    TestCase("titleChipOmittedForTinyWindows") { t in
        t.isNil(OverlayLabelLayout.titleChip(window: CGRect(x: 0, y: 0, width: 40, height: 40),
                                             textSize: CGSize(width: 100, height: 16),
                                             padding: 6, margin: 12))
    },
]

let mediaInfoTextTests: [TestCase] = [
    TestCase("durationFormatsMinutesAndHours") { t in
        t.equal(MediaInfoText.duration(0), "0:00")
        t.equal(MediaInfoText.duration(41.6), "0:42")
        t.equal(MediaInfoText.duration(725), "12:05")
        t.equal(MediaInfoText.duration(3723), "1:02:03")
    },
    TestCase("durationRejectsUnreadableLengths") { t in
        t.isNil(MediaInfoText.duration(-1))
        t.isNil(MediaInfoText.duration(.nan))
        t.isNil(MediaInfoText.duration(.infinity))
    },
    TestCase("pixelSizeUsesTheSameTimesSignAsTheSelectionLabel") { t in
        t.equal(MediaInfoText.pixelSize(width: 1600, height: 1000), "1600 × 1000")
    },
    TestCase("recordingBadgeCombinesDurationAndFormat") { t in
        t.equal(MediaInfoText.recordingBadge(seconds: 42, fileExtension: "mp4"), "0:42 · MP4")
        t.equal(MediaInfoText.recordingBadge(seconds: nil, fileExtension: "gif"), "GIF")
        t.equal(MediaInfoText.recordingBadge(seconds: 5, fileExtension: ""), "0:05")
        t.isNil(MediaInfoText.recordingBadge(seconds: .nan, fileExtension: ""))
    },
]
