import TestKit
import CoreGraphics
@testable import RecordingKit

let recordingPillLayoutTests: [TestCase] = [
    TestCase("confirmPairFitsTheWiderLabel") { t in
        // "Restart?" 66pt, "Discard?" 68pt, 2pt between → each icon button 33pt, slot 68pt.
        let w = RecordingPillLayout.confirmPairButtonWidth(confirmWidths: [66, 68], spacing: 2, minimum: 28)
        t.equal(w, 33)
        t.equal(RecordingPillLayout.confirmSlotWidth(buttonWidth: w, spacing: 2), 68)
    },
    TestCase("confirmPairNeverShrinksBelowTheIconButton") { t in
        t.equal(RecordingPillLayout.confirmPairButtonWidth(confirmWidths: [40, 30], spacing: 2, minimum: 28), 28)
        t.equal(RecordingPillLayout.confirmPairButtonWidth(confirmWidths: [], spacing: 2, minimum: 28), 28)
    },
    TestCase("confirmPairRoundsUp") { t in
        // (69 − 2) / 2 = 33.5 → 34, so the slot (70) still holds the 69pt label.
        let w = RecordingPillLayout.confirmPairButtonWidth(confirmWidths: [69], spacing: 2, minimum: 28)
        t.equal(w, 34)
        t.isTrue(RecordingPillLayout.confirmSlotWidth(buttonWidth: w, spacing: 2) >= 69)
    },
    TestCase("hintSitsCentredAboveThePill") { t in
        let pill = CGRect(x: 400, y: 100, width: 600, height: 40)
        let visible = CGRect(x: 0, y: 0, width: 1470, height: 900)
        let r = RecordingPillLayout.hintFrame(size: CGSize(width: 200, height: 24), anchorX: 700,
                                              pill: pill, visible: visible, gap: 6, margin: 8)
        t.equal(r, CGRect(x: 600, y: 146, width: 200, height: 24))
    },
    TestCase("hintGoesBelowWhenThePillIsAtTheTop") { t in
        let visible = CGRect(x: 0, y: 0, width: 1470, height: 900)
        let pill = CGRect(x: 400, y: 850, width: 600, height: 40)   // 890 + 6 + 24 > 900
        let r = RecordingPillLayout.hintFrame(size: CGSize(width: 200, height: 24), anchorX: 700,
                                              pill: pill, visible: visible, gap: 6, margin: 8)
        t.equal(r.minY, 820, "850 − 6 − 24")
        t.equal(r.minX, 600)
    },
    TestCase("hintStaysOnScreenAtTheEdges") { t in
        let visible = CGRect(x: 0, y: 0, width: 1470, height: 900)
        let left = RecordingPillLayout.hintFrame(size: CGSize(width: 200, height: 24), anchorX: 20,
                                                 pill: CGRect(x: 8, y: 100, width: 180, height: 40),
                                                 visible: visible, gap: 6, margin: 8)
        t.equal(left.minX, 8)
        let right = RecordingPillLayout.hintFrame(size: CGSize(width: 200, height: 24), anchorX: 1460,
                                                  pill: CGRect(x: 1280, y: 100, width: 182, height: 40),
                                                  visible: visible, gap: 6, margin: 8)
        t.equal(right.maxX, 1462)
    },
    TestCase("hintNarrowsToTheScreen") { t in
        let visible = CGRect(x: 100, y: 0, width: 300, height: 900)
        let r = RecordingPillLayout.hintFrame(size: CGSize(width: 500, height: 24), anchorX: 250,
                                              pill: CGRect(x: 120, y: 100, width: 200, height: 40),
                                              visible: visible, gap: 6, margin: 8)
        t.equal(r.width, 284)
        t.equal(r.minX, 108)
    },
]
