import TestKit
import CoreGraphics
@testable import CaptureKit

/// A grey buffer: `background` everywhere, `columns` painted `(x, top, bottom, level)`.
private func grid(width: Int = 40, height: Int = 20, background: UInt8,
                  _ columns: [(x: Int, top: Int, bottom: Int, level: UInt8)]) -> GridLines {
    var gray = [UInt8](repeating: background, count: width * height)
    for c in columns { for y in c.top..<c.bottom { gray[y * width + c.x] = c.level } }
    return GridLines(width: width, height: height, gray: gray)
}

let gridLinesTests: [TestCase] = [
    TestCase("faintSpreadsheetLineIsFound") { t in
        // #e2e2e2 on white: far too light for a text threshold.
        let lines = grid(background: 255, [(x: 20, top: 0, bottom: 20, level: 226)])
        t.equal(lines.vertical(in: CGRect(x: 0, y: 2, width: 40, height: 16)), [20.5])
    },
    TestCase("lighterLineOnDarkThemeIsFound") { t in
        let lines = grid(background: 30, [(x: 12, top: 0, bottom: 20, level: 60)])
        t.equal(lines.vertical(in: CGRect(x: 0, y: 0, width: 40, height: 20)), [12.5])
    },
    TestCase("letterStemShorterThanTheRowIsNot") { t in
        // A stem covering the text but not the reach above and below it.
        let lines = grid(background: 255, [(x: 10, top: 5, bottom: 15, level: 0)])
        t.equal(lines.vertical(in: CGRect(x: 0, y: 2, width: 40, height: 16)), [])
    },
    TestCase("shadedCellEdgeIsNotALine") { t in
        // A step from white to a grey cell background has one side, not two.
        var gray = [UInt8](repeating: 255, count: 40 * 20)
        for y in 0..<20 { for x in 20..<40 { gray[y * 40 + x] = 230 } }
        t.equal(GridLines(width: 40, height: 20, gray: gray).vertical(in: CGRect(x: 0, y: 0, width: 40, height: 20)), [])
    },
]
