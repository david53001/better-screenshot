import TestKit
import CoreGraphics
@testable import CaptureKit

// Geometry is Vision-style normalized (0…1), but with a top-left origin:
// `top` grows downward. Character width ≈ (right - left) / text.count, so the
// fixtures pick widths that make the "does the next word fit?" arithmetic
// unambiguous.
private func line(_ text: String, top: CGFloat, left: CGFloat, right: CGFloat,
                  height: CGFloat = 0.05) -> TextReflow.Line {
    TextReflow.Line(text: text, box: CGRect(x: left, y: top, width: right - left, height: height))
}

/// A line with Vision's per-word boxes, given as (left, right) per word.
private func words(_ text: String, top: CGFloat, _ spans: [(CGFloat, CGFloat)], height: CGFloat = 0.05) -> TextReflow.Line {
    let boxes = spans.map { CGRect(x: $0.0, y: top, width: $0.1 - $0.0, height: height) }
    return TextReflow.Line(text: text, box: boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }, wordBoxes: boxes)
}

let textReflowTests: [TestCase] = [
    TestCase("emptyInputIsEmpty") { t in
        t.equal(TextReflow.paragraphs([]), [])
    },
    TestCase("wrappedLinesJoinIntoOneParagraph") { t in
        // "over" (≈0.1 wide) would not fit after "jumps" at the column edge 0.6.
        let lines = [
            line("The quick brown fox jumps", top: 0.10, left: 0.1, right: 0.6),
            line("over the lazy dog", top: 0.16, left: 0.1, right: 0.44),
        ]
        t.equal(TextReflow.paragraphs(lines), ["The quick brown fox jumps over the lazy dog"])
    },
    TestCase("shortLineEndsParagraph") { t in
        // Code-style: each short line leaves room for the next word, so none wrapped.
        let lines = [
            line("let x = 1", top: 0.10, left: 0.1, right: 0.28),
            line("let y = 2", top: 0.16, left: 0.1, right: 0.28),
            line("return veryLongExpression(with: lots, of: arguments)", top: 0.22, left: 0.1, right: 1.0),
        ]
        t.equal(TextReflow.paragraphs(lines).joined(separator: "\n"),
                "let x = 1\nlet y = 2\nreturn veryLongExpression(with: lots, of: arguments)")
    },
    TestCase("bulletMarkerStartsNewParagraph") { t in
        let lines = [
            line("• The Boston Consulting Group", top: 0.10, left: 0.1, right: 0.7),
            line("matrix is a planning tool.", top: 0.16, left: 0.14, right: 0.66),
            line("• It looks at market growth", top: 0.24, left: 0.1, right: 0.64),
            line("and market share.", top: 0.30, left: 0.14, right: 0.48),
        ]
        t.equal(TextReflow.paragraphs(lines), [
            "• The Boston Consulting Group matrix is a planning tool.",
            "• It looks at market growth and market share.",
        ])
    },
    TestCase("checkboxMarkerStartsNewParagraph") { t in
        let lines = [
            line("☐ Finish the history essay draft and", top: 0.10, left: 0.1, right: 0.9),
            line("hand it in", top: 0.16, left: 0.14, right: 0.4),
            line("☑ Call the dentist", top: 0.22, left: 0.1, right: 0.5),
        ]
        t.equal(TextReflow.paragraphs(lines), [
            "☐ Finish the history essay draft and hand it in",
            "☑ Call the dentist",
        ])
    },
    TestCase("twoLinesPastDoubleSpacingAreTwoParagraphs") { t in
        // Character width 0.016; "Then" would not fit after the first line.
        func pair(pitch: CGFloat) -> [TextReflow.Line] {
            [line("It rained all day in the town, so we stayed in.", top: 0.1, left: 0.1, right: 0.852, height: 0.06),
             line("Then the sun came out and we went for a long walk.", top: 0.1 + pitch, left: 0.1, right: 0.9,
                  height: 0.06)]
        }
        // Double spaced (4 character widths): still one paragraph.
        t.equal(TextReflow.paragraphs(pair(pitch: 0.064)).count, 1)
        // Six character widths apart: a gap between paragraphs.
        t.equal(TextReflow.paragraphs(pair(pitch: 0.096)).count, 2)
    },
    TestCase("aCaptionUnderAFigureStaysInItsColumn") { t in
        // Vision's order: the left column down to the figure, the whole right
        // column, then the caption under the figure.
        let lines = [
            line("Left column text.", top: 0.10, left: 0.05, right: 0.45),
            line("Right column starts here", top: 0.10, left: 0.55, right: 0.95),
            line("and runs on down the", top: 0.18, left: 0.55, right: 0.95),
            line("page past the figure.", top: 0.26, left: 0.55, right: 0.90),
            line("Figure 1. A caption.", top: 0.80, left: 0.05, right: 0.40),
        ]
        t.equal(TextReflow.columnOrdered(lines).map(\.text),
                ["Left column text.", "Figure 1. A caption.", "Right column starts here", "and runs on down the",
                 "page past the figure."])
        // A table read row by row has no stack beside a cell: order kept.
        let table = [
            line("Name", top: 0.1, left: 0.05, right: 0.2), line("Score", top: 0.1, left: 0.6, right: 0.8),
            line("Ana", top: 0.2, left: 0.05, right: 0.15), line("84", top: 0.2, left: 0.6, right: 0.66),
        ]
        t.equal(TextReflow.columnOrdered(table).map(\.text), ["Name", "Score", "Ana", "84"])
    },
    TestCase("aSidebarBesideATableIsAListOfItsOwn") { t in
        // Settings: a sidebar whose items fall between the table's rows.
        let lines = [
            line("General", top: 0.10, left: 0.03, right: 0.10, height: 0.055),
            line("Appearance", top: 0.23, left: 0.03, right: 0.14, height: 0.055),
            line("Wi-Fi", top: 0.35, left: 0.03, right: 0.08, height: 0.055),
            line("Bluetooth", top: 0.47, left: 0.03, right: 0.12, height: 0.055),
            line("Appearance", top: 0.31, left: 0.35, right: 0.46, height: 0.055),
            line("Accent colour", top: 0.44, left: 0.35, right: 0.49, height: 0.055),
            line("Auto", top: 0.31, left: 0.90, right: 0.95, height: 0.055),
            line("Multicolour", top: 0.44, left: 0.84, right: 0.95, height: 0.055),
        ]
        t.equal(TextReflow.paragraphs(lines).joined(separator: "\n"),
                "General\nAppearance\nWi-Fi\nBluetooth\nAppearance\tAuto\nAccent colour\tMulticolour")
    },
    TestCase("numberedMarkerStartsNewParagraph") { t in
        let lines = [
            line("1. First item that wraps onto", top: 0.10, left: 0.1, right: 0.7),
            line("a second line", top: 0.16, left: 0.14, right: 0.4),
            line("2. Second item", top: 0.22, left: 0.1, right: 0.38),
        ]
        t.equal(TextReflow.paragraphs(lines), ["1. First item that wraps onto a second line", "2. Second item"])
    },
    TestCase("largeGapStartsNewParagraph") { t in
        // Full-width line, so the fit test alone would merge; the gap (1.2× line height) must not.
        let lines = [
            line("A full width line of prose that reaches", top: 0.10, left: 0.1, right: 0.9),
            line("Next paragraph here", top: 0.21, left: 0.1, right: 0.5),
        ]
        t.equal(TextReflow.paragraphs(lines), ["A full width line of prose that reaches", "Next paragraph here"])
    },
    TestCase("pitchJumpStartsNewParagraph") { t in
        // Three lines at a 0.06 pitch, then one at 0.09 (gap only 0.8× height, so the
        // absolute gap rule stays quiet — the block's own rhythm has to catch it).
        let lines = [
            line("first line of the block here", top: 0.10, left: 0.1, right: 0.66),
            line("second line of the block too", top: 0.16, left: 0.1, right: 0.66),
            line("third line of the block ends", top: 0.22, left: 0.1, right: 0.66),
            line("fourth line after a paragraph", top: 0.31, left: 0.1, right: 0.68),
        ]
        t.equal(TextReflow.paragraphs(lines), [
            "first line of the block here second line of the block too third line of the block ends",
            "fourth line after a paragraph",
        ])
    },
    TestCase("fontSizeChangeStartsNewParagraph") { t in
        let lines = [
            line("Big heading here", top: 0.10, left: 0.1, right: 0.6, height: 0.08),
            line("body text that is long enough", top: 0.19, left: 0.1, right: 0.6, height: 0.04),
        ]
        t.equal(TextReflow.paragraphs(lines), ["Big heading here", "body text that is long enough"])
    },
    TestCase("columnsStaySeparate") { t in
        // Two columns of prose, handed over column by column (Vision's reading
        // order) even though their lines share rows.
        let lines = [
            line("Water evaporates from oceans and rivers", top: 0.10, left: 0.05, right: 0.45),
            line("when it is heated by the Sun.", top: 0.16, left: 0.05, right: 0.38),
            line("Some of this water flows over the land", top: 0.10, left: 0.55, right: 0.95),
            line("and then returns to the sea.", top: 0.16, left: 0.55, right: 0.85),
        ]
        t.equal(TextReflow.paragraphs(lines), [
            "Water evaporates from oceans and rivers when it is heated by the Sun.",
            "Some of this water flows over the land and then returns to the sea.",
        ])
    },
    TestCase("sameRowFragmentsJoinWhenAdjacent") { t in
        let lines = [
            line("Hello", top: 0.10, left: 0.10, right: 0.20),
            line("world", top: 0.10, left: 0.21, right: 0.31),
        ]
        t.equal(TextReflow.paragraphs(lines), ["Hello world"])
    },
    TestCase("sameRowDistantShortPiecesJoinWithTab") { t in
        // A label and its value, a running header and its page number.
        let lines = [
            line("Name", top: 0.10, left: 0.1, right: 0.2),
            line("Value", top: 0.10, left: 0.6, right: 0.7),
        ]
        t.equal(TextReflow.paragraphs(lines), ["Name\tValue"])
    },
    TestCase("visionColumnOrderIsKept") { t in
        // Vision reads a two-column slide column by column; sorting its lines
        // top to bottom used to put "Disadvantages" above the first bullet.
        let lines = [
            line("Advantages", top: 0.10, left: 0.05, right: 0.35),
            line("• Low carbon emissions", top: 0.16, left: 0.05, right: 0.40),
            line("Disadvantages", top: 0.10, left: 0.55, right: 0.90),
            line("• Radioactive waste", top: 0.16, left: 0.55, right: 0.85),
        ]
        t.equal(TextReflow.paragraphs(lines),
                ["Advantages", "• Low carbon emissions", "Disadvantages", "• Radioactive waste"])
    },
    TestCase("hyphenatedBreakJoinsWithoutSpace") { t in
        let lines = [
            line("a tool for product portfo-", top: 0.10, left: 0.1, right: 0.62),
            line("lio analysis", top: 0.16, left: 0.1, right: 0.34),
        ]
        t.equal(TextReflow.paragraphs(lines), ["a tool for product portfolio analysis"])
    },
    TestCase("aCompoundBrokenAtItsHyphenKeepsIt") { t in
        // `lightdependent` isn't a word, so the hyphen was the compound's.
        let lines = [
            line("the light-", top: 0.10, left: 0.1, right: 0.3),
            line("dependent reactions", top: 0.16, left: 0.1, right: 0.48),
        ]
        t.equal(TextReflow.paragraphs(lines), ["the light-dependent reactions"])
        t.equal(WordList.contains("reactions"), true)
        t.equal(WordList.contains("running"), true)
        t.equal(WordList.contains("lightdependent"), false)
    },
    TestCase("bulletGlyphsNormalizeAndWhitespaceTrims") { t in
        let lines = [
            line("  · first thing ", top: 0.10, left: 0.1, right: 0.4),
            line("● second thing", top: 0.18, left: 0.1, right: 0.4),
        ]
        t.equal(TextReflow.paragraphs(lines), ["• first thing", "• second thing"])
    },
    TestCase("tableRowsBecomeTabSeparated") { t in
        // Vision reads a table column by column; the cells come out row by row.
        let lines = [
            line("Country", top: 0.10, left: 0.05, right: 0.19),
            line("Romania", top: 0.20, left: 0.05, right: 0.19),
            line("Total", top: 0.30, left: 0.05, right: 0.12),
            line("Capital", top: 0.10, left: 0.35, right: 0.47),
            line("Bucharest", top: 0.20, left: 0.35, right: 0.50),
            line("Pop", top: 0.10, left: 0.65, right: 0.70),
            line("19.0", top: 0.20, left: 0.65, right: 0.72),
            line("19.0", top: 0.30, left: 0.65, right: 0.72),
        ]
        // The empty middle cell keeps its tab so the row still lines up.
        t.equal(TextReflow.paragraphs(lines), ["Country\tCapital\tPop\nRomania\tBucharest\t19.0\nTotal\t\t19.0"])
    },
    TestCase("gridLineSeparatesNarrowCellFromItsNeighbour") { t in
        // A 1× sheet: "IA" and "18" sit closer to their left neighbours than
        // the same-row join distance; the grid line at 0.45 is the boundary.
        let lines = [
            line("Name", top: 0.10, left: 0.05, right: 0.15),
            line("Ana", top: 0.20, left: 0.05, right: 0.10),
            line("Dan", top: 0.30, left: 0.05, right: 0.10),
            words("Paper 2", top: 0.10, [(0.32, 0.40), (0.41, 0.44)]),
            line("41", top: 0.20, left: 0.41, right: 0.44),
            line("45", top: 0.30, left: 0.41, right: 0.44),
            line("IA", top: 0.10, left: 0.455, right: 0.48),
            line("18", top: 0.20, left: 0.455, right: 0.48),
            line("22", top: 0.30, left: 0.455, right: 0.48),
        ]
        t.equal(TextReflow.paragraphs(lines, verticalRules: { _ in [0.25, 0.45] }),
                ["Name\tPaper 2\tIA\nAna\t41\t18\nDan\t45\t22"])
    },
    TestCase("visionLineAcrossGridLineIsCutBetweenWords") { t in
        let lines = [
            line("Item", top: 0.10, left: 0.05, right: 0.12),
            words("Budget %", top: 0.10, [(0.30, 0.39), (0.41, 0.48)]),
            line("Rent", top: 0.20, left: 0.05, right: 0.12),
            words("1200 48", top: 0.20, [(0.30, 0.39), (0.40, 0.48)]),
            line("Food", top: 0.30, left: 0.05, right: 0.12),
            line("450", top: 0.30, left: 0.33, right: 0.39),
        ]
        t.equal(TextReflow.paragraphs(lines, verticalRules: { _ in [0.2, 0.40] }),
                ["Item\tBudget\t%\nRent\t1200\t48\nFood\t450"])
    },
    TestCase("mergedCellGoesToFirstColumnItSpans") { t in
        // "Lunch" is centred under Tue, but its row has no grid lines between
        // Mon, Tue and Wed: it is one cell starting at Mon.
        let lines = [
            line("Day", top: 0.10, left: 0.05, right: 0.12), line("Mon", top: 0.10, left: 0.25, right: 0.32),
            line("Tue", top: 0.10, left: 0.45, right: 0.52), line("Wed", top: 0.10, left: 0.65, right: 0.72),
            line("1", top: 0.20, left: 0.05, right: 0.07), line("Maths", top: 0.20, left: 0.25, right: 0.35),
            line("English", top: 0.20, left: 0.45, right: 0.57), line("Physics", top: 0.20, left: 0.65, right: 0.77),
            line("L", top: 0.30, left: 0.05, right: 0.07), line("Lunch", top: 0.30, left: 0.44, right: 0.54),
            line("2", top: 0.40, left: 0.05, right: 0.07), line("Art", top: 0.40, left: 0.25, right: 0.30),
            line("Free", top: 0.40, left: 0.45, right: 0.52), line("TOK", top: 0.40, left: 0.65, right: 0.71),
        ]
        let rules: (CGRect) -> [CGFloat] = { $0.midY > 0.3 && $0.midY < 0.35 ? [0.2] : [0.2, 0.4, 0.6] }
        t.equal(TextReflow.paragraphs(lines, verticalRules: rules),
                ["Day\tMon\tTue\tWed\n1\tMaths\tEnglish\tPhysics\nL\tLunch\n2\tArt\tFree\tTOK"])
    },
    TestCase("strayVerticalStrokeOnOneRowCutsNothing") { t in
        let lines = [
            line("Subject", top: 0.10, left: 0.05, right: 0.20), line("Level", top: 0.10, left: 0.30, right: 0.40),
            line("Maths", top: 0.20, left: 0.05, right: 0.15), words("Maths HL", top: 0.20, [(0.30, 0.40), (0.41, 0.45)]),
            line("Physics", top: 0.30, left: 0.05, right: 0.17), words("Physics SL", top: 0.30, [(0.30, 0.42), (0.43, 0.47)]),
        ]
        let rules: (CGRect) -> [CGFloat] = { $0.midY > 0.2 && $0.midY < 0.25 ? [0.405] : [] }
        t.equal(TextReflow.paragraphs(lines, verticalRules: rules),
                ["Subject\tLevel\nMaths\tMaths HL\nPhysics\tPhysics SL"])
    },
    TestCase("dividerBesideGridlessTableIsNotItsGrid") { t in
        // A line between the first column and the rest would put Capital and
        // Pop in one column: the text's own columns win.
        let lines = [
            line("Country", top: 0.10, left: 0.05, right: 0.19), line("Romania", top: 0.20, left: 0.05, right: 0.19),
            line("Capital", top: 0.10, left: 0.35, right: 0.47), line("Bucharest", top: 0.20, left: 0.35, right: 0.50),
            line("Pop", top: 0.10, left: 0.65, right: 0.70), line("19.0", top: 0.20, left: 0.65, right: 0.72),
        ]
        t.equal(TextReflow.paragraphs(lines, verticalRules: { _ in [0.3] }),
                ["Country\tCapital\tPop\nRomania\tBucharest\t19.0"])
    },
    TestCase("gridlessRowReadAsOneLineIsCutByTheOtherRowsColumns") { t in
        // Vision read the header cells "Gold" and "Silver" as one line.
        let lines = [
            line("Country", top: 0.10, left: 0.05, right: 0.20), words("Gold Silver", top: 0.10, [(0.30, 0.44), (0.45, 0.60)]),
            line("Norway", top: 0.20, left: 0.05, right: 0.18), line("16", top: 0.20, left: 0.38, right: 0.42),
            line("8", top: 0.20, left: 0.54, right: 0.56),
            line("Canada", top: 0.30, left: 0.05, right: 0.18), line("11", top: 0.30, left: 0.38, right: 0.42),
            line("10", top: 0.30, left: 0.52, right: 0.56),
        ]
        t.equal(TextReflow.paragraphs(lines), ["Country\tGold\tSilver\nNorway\t16\t8\nCanada\t11\t10"])
    },
    TestCase("wrappedTableCellStaysInItsRow") { t in
        let lines = [
            line("Feature", top: 0.10, left: 0.05, right: 0.15, height: 0.03),
            line("Divisions", top: 0.20, left: 0.05, right: 0.18, height: 0.03),
            line("Genetic variation", top: 0.30, left: 0.05, right: 0.30, height: 0.03),
            line("Meiosis", top: 0.10, left: 0.40, right: 0.52, height: 0.03),
            line("Two", top: 0.20, left: 0.40, right: 0.45, height: 0.03),
            line("Crossing over and", top: 0.30, left: 0.40, right: 0.65, height: 0.03),
            line("independent assortment", top: 0.335, left: 0.40, right: 0.70, height: 0.03),
        ]
        t.equal(TextReflow.paragraphs(lines),
                ["Feature\tMeiosis\nDivisions\tTwo\nGenetic variation\tCrossing over and independent assortment"])
    },
    TestCase("marksAtTheRightJoinTheirQuestion") { t in
        let lines = [
            line("3. A survey asked 120 students how they travel to school.", top: 0.05, left: 0.05, right: 0.80),
            line("(a) Write down the number of students who walk to school.", top: 0.15, left: 0.05, right: 0.75),
            line("[1]", top: 0.15, left: 0.90, right: 0.95),
            line("(b) Find the probability that a randomly chosen student travels by bus.", top: 0.25, left: 0.05, right: 0.85),
            line("[2]", top: 0.25, left: 0.90, right: 0.95),
        ]
        t.equal(TextReflow.paragraphs(lines).joined(separator: "\n"), """
            3. A survey asked 120 students how they travel to school.
            (a) Write down the number of students who walk to school.\t[1]
            (b) Find the probability that a randomly chosen student travels by bus.\t[2]
            """)
    },
    TestCase("cellsOfAWideImageDoNotGlueTogether") { t in
        // Gaps are compared with character widths in pixels: normalized x and
        // y differ by the aspect ratio (here 4.4×).
        let lines = [
            line("Ana Ionescu", top: 0.40, left: 0.03, right: 0.20, height: 0.08),
            line("78", top: 0.40, left: 0.40, right: 0.43, height: 0.08),
            line("85", top: 0.40, left: 0.55, right: 0.58, height: 0.08),
        ]
        t.equal(TextReflow.paragraphs(lines, imageSize: CGSize(width: 1240, height: 282)), ["Ana Ionescu\t78\t85"])
    },
    TestCase("rowFragmentsJoinLeftToRight") { t in
        // Vision split one code line and handed the right half over first.
        let lines = [
            line(", *p);", top: 0.099, left: 0.40, right: 0.55),
            line(#"printf("%d\n""#, top: 0.10, left: 0.10, right: 0.40),
        ]
        t.equal(TextReflow.paragraphs(lines), [#"printf("%d\n", *p);"#])
    },
    TestCase("codeKeepsIndentationAndBlankLines") { t in
        // Monospaced: every character is 0.01 wide, so indentation reads off the
        // left edges; the gap of two line pitches is one blank line.
        let lines = [
            line("def grade(score):", top: 0.10, left: 0.05, right: 0.22, height: 0.04),
            line("if score >= 80:", top: 0.16, left: 0.09, right: 0.24, height: 0.04),
            line(#"return "7""#, top: 0.22, left: 0.13, right: 0.23, height: 0.04),
            line("print(grade(90))", top: 0.34, left: 0.05, right: 0.21, height: 0.04),
        ]
        t.equal(TextReflow.paragraphs(lines),
                ["def grade(score):\n    if score >= 80:\n        return \"7\"\n\nprint(grade(90))"])
    },
    TestCase("bracketOnlyLinesSetTheBlocksIndentation") { t in
        // A JSON object: the braces (recovered from the pixels) sit two cells
        // left of the keys. Pixels of a 560 × 430 capture.
        let w: CGFloat = 560, h: CGFloat = 430
        func px(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat) -> TextReflow.Line {
            TextReflow.Line(text: text, box: CGRect(x: x / w, y: y / h, width: width / w, height: 27 / h))
        }
        let lines = [
            px("{", 37, 32, 15),
            px(#""name": "ocr-bench","#, 66, 70, 312),
            px(#""scripts": {"#, 63, 175, 190),
            px(#""test": "node --test","#, 98, 213, 342),
            px("},", 69, 284, 31),
            px(#""timeout": 0.75"#, 66, 357, 236),
            px("}", 37, 391, 15),
        ]
        t.equal(TextReflow.paragraphs(lines, imageSize: CGSize(width: w, height: h)).joined(separator: "\n"),
                "{\n  \"name\": \"ocr-bench\",\n  \"scripts\": {\n    \"test\": \"node --test\",\n  },\n  \"timeout\": 0.75\n}")
    },
    TestCase("oneLookAlikeSwapBalancesACodeLinesBrackets") { t in
        t.equal(TextReflow.withBalancedBrackets("on: Lpush, pull_request]"), "on: [push, pull_request]")
        t.equal(TextReflow.withBalancedBrackets("guard ok else i return 0 }"), "guard ok else { return 0 }")
        t.equal(TextReflow.withBalancedBrackets("print(mean([3, 4, 51))"), "print(mean([3, 4, 5]))")
        // Nothing unmatched, or nothing to swap: unchanged.
        t.equal(TextReflow.withBalancedBrackets("} else {"), "} else {")
        t.equal(TextReflow.withBalancedBrackets("    return i }"), "    return i }")
        t.equal(TextReflow.withBalancedBrackets("f(x) = [1, 2]"), "f(x) = [1, 2]")
    },
    TestCase("codeCleanupFixesFileNamesHashesAndDocstrings") { t in
        t.equal(TextReflow.cleanedCode("$ python3 main-py"), "$ python3 main.py")
        t.equal(TextReflow.cleanedCode("run: swift test --parallel"), "run: swift test --parallel")
        t.equal(TextReflow.withHexDigits("alb2c3d Fix off-by-one"), "a1b2c3d Fix off-by-one")
        t.equal(TextReflow.withHexDigits("allowed deadbeef"), "allowed deadbeef")
        t.equal(TextReflow.withTripleQuotes(#"''"Return the mean.''''"#), #""""Return the mean.""""#)
        t.equal(TextReflow.withTripleQuotes("'''raw'''"), "'''raw'''")
    },
    TestCase("codeUsesTheUncorrectedRead") { t in
        let lines = [
            TextReflow.Line(text: "const total = items. reduce (sum) = 0;",
                            box: CGRect(x: 0.05, y: 0.1, width: 0.37, height: 0.04),
                            rawText: "const total = items.reduce(sum) => 0;"),
            TextReflow.Line(text: "console. log (total);", box: CGRect(x: 0.05, y: 0.16, width: 0.21, height: 0.04),
                            rawText: "console. log(total);"),
        ]
        t.isTrue(TextReflow.containsCode(lines))
        t.equal(TextReflow.paragraphs(lines), ["const total = items.reduce(sum) => 0;\nconsole.log(total);"])
    },
    TestCase("lineNumberGutterIsDropped") { t in
        let lines = [
            line("1", top: 0.10, left: 0.02, right: 0.03, height: 0.04),
            line("fn main() {", top: 0.10, left: 0.08, right: 0.19, height: 0.04),
            line("2", top: 0.16, left: 0.02, right: 0.03, height: 0.04),
            line("let x = 1;", top: 0.16, left: 0.12, right: 0.22, height: 0.04),
            line("3", top: 0.22, left: 0.02, right: 0.03, height: 0.04),
            line("}", top: 0.22, left: 0.08, right: 0.09, height: 0.04),
        ]
        t.equal(TextReflow.paragraphs(lines), ["fn main() {\n    let x = 1;\n}"])
    },
    TestCase("nestedListItemsIndentByLevel") { t in
        let lines = [
            line("• Fruit basket", top: 0.10, left: 0.05, right: 0.25, height: 0.04),
            line("• Apples and pears", top: 0.16, left: 0.10, right: 0.30, height: 0.04),
            line("• Conference", top: 0.22, left: 0.15, right: 0.30, height: 0.04),
            line("• Vegetables", top: 0.28, left: 0.05, right: 0.20, height: 0.04),
        ]
        t.equal(TextReflow.paragraphs(lines),
                ["• Fruit basket", "\t• Apples and pears", "\t\t• Conference", "• Vegetables"])
    },
    TestCase("paragraphContinuesIntoTheNextColumn") { t in
        let lines = [
            line("As the warm, moist air rises it cools, and the", top: 0.10, left: 0.05, right: 0.45),
            line("vapour condenses into tiny droplets that form", top: 0.16, left: 0.05, right: 0.44),
            line("clouds. When the droplets combine and grow", top: 0.22, left: 0.05, right: 0.43),
            line("heavy enough, they fall back to the ground as", top: 0.10, left: 0.55, right: 0.94),
            line("precipitation.", top: 0.16, left: 0.55, right: 0.67),
        ]
        t.equal(TextReflow.paragraphs(lines), ["As the warm, moist air rises it cools, and the vapour condenses into "
            + "tiny droplets that form clouds. When the droplets combine and grow heavy enough, they fall back to "
            + "the ground as precipitation."])
    },
    TestCase("longestLineEndingASentenceKeepsTheNextApart") { t in
        let lines = [
            line("Der Bär läuft über die Brücke.", top: 0.10, left: 0.05, right: 0.35),
            line("Le garçon a mangé une crème brûlée.", top: 0.16, left: 0.05, right: 0.40),
            line("El niño tiene cinco años.", top: 0.22, left: 0.05, right: 0.30),
        ]
        t.equal(TextReflow.paragraphs(lines),
                ["Der Bär läuft über die Brücke.", "Le garçon a mangé une crème brûlée.", "El niño tiene cinco años."])
    },
    TestCase("boxHeightJitterDoesNotSplitAParagraph") { t in
        // Vision boxed "years." 0.6× as tall as its line; the characters are the same size.
        let lines = [
            line("Rivers carry these dissolved salts to the sea, where they accumulate over millions of",
                 top: 0.10, left: 0.05, right: 0.90, height: 0.069),
            line("years.", top: 0.17, left: 0.05, right: 0.11, height: 0.043),
        ]
        t.equal(TextReflow.paragraphs(lines),
                ["Rivers carry these dissolved salts to the sea, where they accumulate over millions of years."])
    },
    TestCase("displayEquationsStayOnTheirOwnLines") { t in
        let lines = [
            line("2H₂ + O₂ → 2H₂O", top: 0.10, left: 0.05, right: 0.40),
            line("CO₂ + H₂O → H₂CO₃", top: 0.18, left: 0.05, right: 0.45),
        ]
        t.equal(TextReflow.paragraphs(lines), ["2H₂ + O₂ → 2H₂O", "CO₂ + H₂O → H₂CO₃"])
    },
    TestCase("codeCleanupFixesVisionMisreads") { t in
        t.equal(TextReflow.cleanedCode("return ø;"), "return 0;")
        t.equal(TextReflow.cleanedCode(#"File "main.py", in ‹module›"#), #"File "main.py", in <module>"#)
        t.equal(TextReflow.cleanedCode("console. log(label);"), "console.log(label);")
        t.equal(TextReflow.cleanedCode("# Done. Then run it"), "# Done. Then run it")
    },
    TestCase("codeSignalsIgnoreProseAndMath") { t in
        t.isTrue(TextReflow.looksLikeCode("if (total === 0) {"))
        t.isTrue(TextReflow.looksLikeCode("runs-on: macos-15"))
        t.isTrue(TextReflow.looksLikeCode("$ python3 main.py"))
        t.isFalse(TextReflow.looksLikeCode("For example, a student who spends the evening"))
        t.isFalse(TextReflow.looksLikeCode("f(x) = x² + 1 and sin(x) = 0"))
    },
]
