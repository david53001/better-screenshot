import TestKit
import CoreGraphics
@testable import EditorKit

let textHandlesTests: [TestCase] = [
    TestCase("textCornersSitOutsideTheBoxAndSidesClearThem") { t in
        let box = CGRect(x: 100, y: 100, width: 200, height: 40)
        let r = TextHandles.rects(for: box)
        t.equal(Set(r.keys), [0, 2, 3, 4, 5, 7])
        // Corners: centred 4pt outside each corner, reaching at most 0.5pt into the box.
        t.approxEqual(Double(r[0]!.midX), 96); t.approxEqual(Double(r[0]!.midY), 96)
        t.approxEqual(Double(r[7]!.midX), 304); t.approxEqual(Double(r[7]!.midY), 144)
        t.isTrue(r[0]!.maxX <= box.minX + 0.5 && r[0]!.maxY <= box.minY + 0.5, "top-left barely touches the box")
        t.isTrue(r[7]!.minX >= box.maxX - 0.5 && r[7]!.minY >= box.maxY - 0.5, "bottom-right barely touches the box")
        // Sides: bars outside the left/right edges, centred vertically, capped at 16pt, clear of the corners.
        t.isTrue(r[3]!.maxX <= box.minX && r[4]!.minX >= box.maxX, "side bars are outside the box")
        t.approxEqual(Double(r[3]!.height), 16)
        t.approxEqual(Double(r[4]!.midY), Double(box.midY))
        for s in [3, 4] { for c in [0, 2, 5, 7] { t.isFalse(r[s]!.intersects(r[c]!), "side \(s) clears corner \(c)") } }
    },
    TestCase("sideBarsShrinkThenDisappearOnShortTexts") { t in
        // A one-line text at Fit (~17pt): bars shrink to fit between the corners.
        let line = TextHandles.rects(for: CGRect(x: 0, y: 0, width: 300, height: 17))
        t.approxEqual(Double(line[3]!.height), 12)
        for c in [0, 5] { t.isFalse(line[3]!.intersects(line[c]!)) }
        // Zoomed far out (6pt tall): only the four corners, so nothing crowds the letters.
        let tiny = TextHandles.rects(for: CGRect(x: 0, y: 0, width: 120, height: 6))
        t.equal(Set(tiny.keys), [0, 2, 5, 7])
    },
]
