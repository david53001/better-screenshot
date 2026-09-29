import CoreGraphics
import Foundation

/// Rebuilds readable text from the individual visual lines Vision returns.
/// Pure geometry — no Vision dependency — so the rules are unit-testable.
///
/// Vision already hands lines over in reading order (column by column on a
/// two-column page), so that order is kept; what this adds is structure:
///   • fragments of one visual line are glued back together, left to right;
///   • grids — rows of separate cells whose columns line up — become one line
///     per row with tab-separated cells (pastes into a spreadsheet as a grid),
///     and short right-hand annotations (exam marks, page numbers) join their row;
///   • code keeps one line per line, its indentation and its blank lines;
///   • everything else is prose: wrapped lines rejoin into paragraphs, list items
///     keep their nesting, and a paragraph that runs into the next column joins up.
///
/// All geometry is in pixels (`imageSize`): Vision's boxes are normalized
/// separately in x and y, so comparing a width with a height needs the aspect.
public enum TextReflow {
    /// One recognized visual line. `box` is normalized (0…1) with a
    /// **top-left origin**: `minY` is the top edge, `maxY` the bottom.
    public struct Line: Equatable {
        public var text: String
        public var box: CGRect
        /// The same line read with language correction off; used for code,
        /// where correction "fixes" `items.reduce(` into `items. reduce (`.
        public var rawText: String?
        /// The line with super/subscripts and math symbols rebuilt
        /// (ScriptRecovery); what prose and tables show. `text` stays Vision's
        /// own read, which layout decisions and code use.
        public var recovered: String?
        /// Vision's box for each whitespace-separated word of `text`, left to
        /// right (same coordinates as `box`); lets a line that runs across
        /// table cells be cut between them. Nil when unknown.
        public var wordBoxes: [CGRect]?
        public init(text: String, box: CGRect, rawText: String? = nil, recovered: String? = nil,
                    wordBoxes: [CGRect]? = nil) {
            self.text = text
            self.box = box
            self.rawText = rawText
            self.recovered = recovered
            self.wordBoxes = wordBoxes
        }
    }

    /// Vertical gap above which two lines are never one paragraph, as a
    /// multiple of the taller line's height (≈ a blank line between them).
    static let maxGapRatio: CGFloat = 1.0
    /// Line pitch above which a line breaks a paragraph's rhythm, relative to
    /// its median pitch. Measured slide: intra-paragraph jitter ≤ 1.07×,
    /// paragraph break 1.33×.
    static let maxPitchRatio: CGFloat = 1.25
    /// A font-size change needs glyph height *and* character width to jump by
    /// this much — either alone is noise (Vision's box heights vary up to 1.9×
    /// between lines of one paragraph).
    static let fontChangeRatio: CGFloat = 1.4
    /// Same-row fragments closer than this many character widths are one line.
    static let sameRowJoinChars: CGFloat = 1.5
    /// A table's vertical grid line runs past the text beside it: it must be
    /// unbroken over the row's text height plus this much of it above and
    /// below, which no letter's stem is.
    static let ruleReach: CGFloat = 0.2

    /// `ruleLength` (optional) measures the longest horizontal run of ink in a
    /// pixel region; with it, stacked fractions are rebuilt (see MathLayout).
    /// `verticalRules` (optional) gives the x positions of vertical lines that
    /// cross all of a pixel region; with it, a gridded table's cells are
    /// separated by its grid lines (see `splittingAtRules`, `ruledColumns`).
    public static func paragraphs(_ lines: [Line], imageSize: CGSize = CGSize(width: 1, height: 1),
                                  ruleLength: ((CGRect) -> CGFloat)? = nil,
                                  verticalRules: ((CGRect) -> [CGFloat])? = nil) -> [String] {
        joinedAcrossColumns(layout(lines, imageSize: imageSize, ruleLength: ruleLength,
                                   verticalRules: verticalRules)).map(\.text)
    }

    /// True when some block reads as source code; the recognizer then re-reads
    /// the image without language correction to fill in `rawText`.
    public static func containsCode(_ lines: [Line], imageSize: CGSize = CGSize(width: 1, height: 1)) -> Bool {
        layout(lines, imageSize: imageSize).contains { $0.kind == .code }
    }

    // MARK: - Layout

    struct Seg {
        /// Vision's read — geometry and classification go by this.
        var text: String
        /// What prose and table output shows (recovered scripts and symbols).
        var shown: String
        var raw: String?
        var box: CGRect
        /// Vision's order of the first fragment — the reading order.
        var order: Int
        /// Pixel boxes of the words of `text`, when known (see `Line.wordBoxes`).
        var wordBoxes: [CGRect]? = nil
        /// x positions of the table grid lines crossing this fragment's row.
        var rowRules: [CGFloat] = []
        var charWidth: CGFloat { box.width / CGFloat(max(text.count, 1)) }
        var words: Int { text.split(whereSeparator: \.isWhitespace).count }
    }

    struct Piece {
        enum Kind { case prose, code, grid }
        var kind: Kind
        var text: String
        var order: Int
        var box: CGRect
        /// Prose only: the paragraph's first and last line, its column's right
        /// edge, and whether it opens / closes its column run.
        var first: Seg? = nil
        var last: Seg? = nil
        var columnRight: CGFloat = 0
        var opensRun = false
        var closesRun = false
    }

    static func layout(_ lines: [Line], imageSize: CGSize, ruleLength: ((CGRect) -> CGFloat)? = nil,
                       verticalRules: ((CGRect) -> [CGFloat])? = nil) -> [Piece] {
        var segs = segments(columnOrdered(lines), imageSize: imageSize)
        if let ruleLength { segs = stackingFractions(segs, ruleLength: ruleLength) }
        segs = attachingDetachedScripts(segs)
        segs = droppingLineNumbers(segs)
        if let verticalRules { segs = splittingAtRules(segs, imageWidth: imageSize.width, rules: verticalRules) }
        var pieces: [Piece] = []
        var used = Set<Int>()
        for grid in grids(segs) {
            used.formUnion(grid.members)
            pieces.append(Piece(kind: .grid, text: grid.text, order: grid.members.map { segs[$0].order }.min()!,
                                box: grid.members.dropFirst().reduce(segs[grid.members[0]].box) { $0.union(segs[$1].box) }))
        }
        for run in runs(segs, skipping: used) {
            pieces += flow(run.map { segs[$0] })
        }
        return titlesAboveGrids(pieces.sorted { $0.order < $1.order })
    }

    /// Vision reads a left column only down to a gap (a figure) and lists what
    /// is under the gap (its caption) after the whole right column: a line
    /// that follows a stack of three or more lines beside it, and sits under
    /// the line before that stack, goes back into its own column.
    static func columnOrdered(_ input: [Line]) -> [Line] {
        var lines = input
        func overlaps(_ a: CGRect, _ b: CGRect) -> Bool { min(a.maxX, b.maxX) > max(a.minX, b.minX) }
        var i = 1
        while i < lines.count {
            let line = lines[i].box
            // Columns have a gutter; code's closing `}` sits just left of its block.
            let gutter = 2 * line.width / CGFloat(max(lines[i].text.count, 1))
            var start = i
            while start > 0, !overlaps(lines[start - 1].box, line) { start -= 1 }
            let stack = lines[start..<i].map(\.box)
            if start > 0, stack.count >= 3, lines[i].text.count >= 4, stack.allSatisfy({ $0.minX >= line.maxX + gutter }),
               zip(stack, stack.dropFirst()).allSatisfy({ overlaps($0, $1) && $1.minY > $0.minY }),
               stack[0].minY < line.minY, lines[start - 1].box.maxY <= line.minY {
                lines.insert(lines.remove(at: i), at: start)
            }
            i += 1
        }
        return lines
    }

    /// Vision sometimes lists a table's title in the middle of its
    /// column-by-column read; a line sitting right above a grid goes before it.
    private static func titlesAboveGrids(_ pieces: [Piece]) -> [Piece] {
        var pieces = pieces
        for g in pieces.indices where pieces[g].kind == .grid {
            let grid = pieces[g].box
            let titles = pieces.indices.filter { i in
                i > g && pieces[i].kind == .prose && pieces[i].box.maxY <= grid.minY + 0.2 * pieces[i].box.height
                    && pieces[i].box.minY > grid.minY - 3 * pieces[i].box.height
                    && min(pieces[i].box.maxX, grid.maxX) - max(pieces[i].box.minX, grid.minX) > 0
            }
            for i in titles.reversed() {
                let title = pieces.remove(at: i)
                pieces.insert(title, at: g)
            }
        }
        return pieces
    }

    /// Converts to pixels, normalizes text, and glues fragments of one visual
    /// line back together (Vision sometimes splits a line, and not always in
    /// left-to-right order). Result is in Vision's order.
    static func segments(_ lines: [Line], imageSize: CGSize) -> [Seg] {
        var segs: [Seg] = []
        for (index, line) in lines.enumerated() {
            let text = normalize(line.text)
            guard !text.isEmpty else { continue }
            let b = line.box
            func pixels(_ b: CGRect) -> CGRect {
                CGRect(x: b.minX * imageSize.width, y: b.minY * imageSize.height,
                       width: b.width * imageSize.width, height: b.height * imageSize.height)
            }
            var seg = Seg(text: text, shown: line.recovered.map(normalize) ?? text, raw: line.rawText.map(normalize),
                          box: pixels(b), order: index, wordBoxes: line.wordBoxes?.map(pixels))
            while let j = segs.firstIndex(where: { isSameRow($0.box, seg.box) && isAdjacent($0, seg) }) {
                seg = joined(segs.remove(at: j), seg)
            }
            segs.append(seg)
        }
        return segs.sorted { $0.order < $1.order }
    }

    private static func joined(_ a: Seg, _ b: Seg) -> Seg {
        let (l, r) = a.box.minX <= b.box.minX ? (a, b) : (b, a)
        // Touching fragments join without a space only at punctuation
        // (`printf("%d\n"` + `, *p);`); `the 3rd` + `of March.` keeps its space.
        let gap = r.box.minX - l.box.maxX
        let tight = gap < 0.25 * min(l.charWidth, r.charWidth)
            && (r.text.first.map { ",.;:)]}!?%".contains($0) } == true || l.text.last.map { "([{/".contains($0) } == true)
        let sep = tight ? "" : " "
        let raw = (l.raw == nil && r.raw == nil) ? nil : (l.raw ?? l.text) + sep + (r.raw ?? r.text)
        // Each side's word boxes survive the join, so a grid line between the
        // two can still cut them apart (`splittingAtRules`).
        let words = sep.isEmpty ? nil : validWordBoxes(l).flatMap { a in validWordBoxes(r).map { a + $0 } }
        return Seg(text: l.text + sep + r.text, shown: l.shown + sep + r.shown, raw: raw,
                   box: l.box.union(r.box), order: min(l.order, r.order), wordBoxes: words)
    }

    /// A code view's gutter: a left column of consecutive integers (1, 2, 3 …)
    /// next to monospaced lines. Dropped — nobody wants line numbers in pasted
    /// code. A table's rank column sits next to proportional text and stays.
    static func droppingLineNumbers(_ segs: [Seg]) -> [Seg] {
        func rightNeighbour(_ i: Int) -> Seg? {
            segs.filter { isSameRow($0.box, segs[i].box) && $0.box.minX > segs[i].box.maxX }
                .min { $0.box.minX < $1.box.minX }
        }
        let numbers = segs.indices.filter { i in
            segs[i].text.count <= 5 && Int(segs[i].text) != nil
                && !segs.contains { isSameRow($0.box, segs[i].box) && $0.box.maxX <= segs[i].box.minX }
        }.sorted { segs[$0].box.minY < segs[$1].box.minY }
        var best: [Int] = [], current: [Int] = []
        for i in numbers {
            if let last = current.last, Int(segs[i].text) == Int(segs[last].text)! + 1,
               overlapsHorizontally(segs[last].box, segs[i].box) {
                current.append(i)
            } else {
                current = [i]
            }
            if current.count > best.count { best = current }
        }
        guard best.count >= 3 else { return segs }
        let code = best.compactMap(rightNeighbour)
        guard code.count * 3 >= best.count * 2, isMonospace(code) else { return segs }
        let drop = Set(best)
        return segs.indices.filter { !drop.contains($0) }.map { segs[$0] }
    }

    /// Consecutive (in reading order) segments stacked in one column.
    static func runs(_ segs: [Seg], skipping used: Set<Int>) -> [[Int]] {
        var runs: [[Int]] = []
        for i in segs.indices where !used.contains(i) {
            let s = segs[i]
            if let run = runs.last, let p = run.last {
                let prev = segs[p]
                let left = run.map { segs[$0].box.minX }.min()!
                let right = run.map { segs[$0].box.maxX }.max()!
                let overlap = min(right, s.box.maxX) - max(left, s.box.minX)
                // A lone `{` and the keys indented under it share a column too.
                func bracketsOnly(_ x: Seg) -> Bool { x.text.allSatisfy { "{}[]()[],; ".contains($0) } }
                let nearLeft = (bracketsOnly(s) || run.allSatisfy { bracketsOnly(segs[$0]) })
                    && abs(s.box.minX - left) <= 4 * max(s.charWidth, prev.charWidth)
                if overlap > 0.5 * min(s.box.width, right - left) || nearLeft, s.box.minY > prev.box.midY {
                    runs[runs.count - 1].append(i)
                    continue
                }
            }
            runs.append([i])
        }
        return runs
    }

    // MARK: - Grids

    struct Grid {
        var members: [Int]
        var text: String
    }

    /// Visual rows, top to bottom, each left to right.
    static func rows(_ segs: [Seg], skipping skipped: Set<Int> = []) -> [[Int]] {
        var rows: [[Int]] = []
        for i in segs.indices.filter({ !skipped.contains($0) }).sorted(by: { segs[$0].box.midY < segs[$1].box.midY }) {
            if let last = rows.last, last.contains(where: { isSameRow(segs[$0].box, segs[i].box) }) {
                rows[rows.count - 1].append(i)
            } else {
                rows.append([i])
            }
        }
        return rows.map { $0.sorted { segs[$0].box.minX < segs[$1].box.minX } }
    }

    /// A table's grid lines are cell boundaries. Every fragment learns its
    /// row's vertical grid lines (`rowRules`), and one that runs across a grid
    /// line — Vision read two cells as one line (`1200 48`), or `segments`
    /// joined a narrow cell to its neighbour (`Paper 2` + `IA`) — is cut there,
    /// between words. A line counts only if another row has one at the same x:
    /// that is a table, not a stray vertical stroke.
    static func splittingAtRules(_ segs: [Seg], imageWidth: CGFloat, rules: (CGRect) -> [CGFloat]) -> [Seg] {
        let rows = rows(segs)
        guard rows.filter({ $0.count >= 2 }).count >= 2 else { return segs }
        var found = rows.map { row -> [CGFloat] in
            let tops = row.map { segs[$0].box.minY }.sorted(), bottoms = row.map { segs[$0].box.maxY }.sorted()
            let top = tops[tops.count / 2], bottom = bottoms[bottoms.count / 2]
            let reach = ruleReach * (bottom - top)
            return rules(CGRect(x: 0, y: top - reach, width: imageWidth, height: bottom - top + 2 * reach))
        }
        let tolerance = ruleTolerance(segs.indices, segs)
        found = found.indices.map { r in
            found[r].filter { x in found.indices.contains { $0 != r && found[$0].contains { abs($0 - x) <= tolerance } } }
        }
        guard found.contains(where: { !$0.isEmpty }) else { return segs }
        var rowOf: [Int: Int] = [:]
        for (r, row) in rows.enumerated() { for i in row { rowOf[i] = r } }
        var out: [Seg] = []
        for i in segs.indices {
            var seg = segs[i]
            seg.rowRules = found[rowOf[i]!]
            var cuts = Set<Int>()
            if let boxes = validWordBoxes(seg) {
                for x in seg.rowRules where x > seg.box.minX && x < seg.box.maxX {
                    // The word gap nearest the line, if the line lies in it.
                    func distance(_ k: Int) -> CGFloat { abs(x - (boxes[k - 1].maxX + boxes[k].minX) / 2) }
                    let gaps = boxes.indices.dropFirst().filter { boxes[$0 - 1].midX < x && x < boxes[$0].midX }
                    if let k = gaps.min(by: { distance($0) < distance($1) }) { cuts.insert(k) }
                }
            }
            out += split(seg, at: cuts.sorted()) ?? [seg]
        }
        return out
    }

    /// How far apart two sightings of one grid line may be.
    private static func ruleTolerance<S: Sequence>(_ indices: S, _ segs: [Seg]) -> CGFloat where S.Element == Int {
        let heights = indices.map { segs[$0].box.height }.sorted()
        return heights.isEmpty ? 0 : 0.3 * heights[heights.count / 2]
    }

    /// A fragment's word boxes when they still line up with its words; a
    /// one-word fragment's box is its word's.
    static func validWordBoxes(_ seg: Seg) -> [CGRect]? {
        if let boxes = seg.wordBoxes, boxes.count == seg.words { return boxes }
        return seg.words == 1 ? [seg.box] : nil
    }

    /// `seg` cut into pieces before each word index in `cuts`. Nil when the
    /// shown text no longer lines up word for word with Vision's (a rebuilt
    /// formula), which then stays whole.
    static func split(_ seg: Seg, at cuts: [Int]) -> [Seg]? {
        guard !cuts.isEmpty, let boxes = validWordBoxes(seg) else { return nil }
        let text = seg.text.split(whereSeparator: \.isWhitespace)
        let shown = seg.shown.split(whereSeparator: \.isWhitespace)
        let raw = seg.raw?.split(whereSeparator: \.isWhitespace)
        guard shown.count == text.count, cuts.allSatisfy({ $0 > 0 && $0 < text.count }) else { return nil }
        let bounds = [0] + cuts + [text.count]
        return zip(bounds, bounds.dropFirst()).map { a, b in
            let left = boxes[a..<b].map(\.minX).min()!, right = boxes[a..<b].map(\.maxX).max()!
            return Seg(text: text[a..<b].joined(separator: " "), shown: shown[a..<b].joined(separator: " "),
                       raw: raw.flatMap { $0.count == text.count ? $0[a..<b].joined(separator: " ") : nil },
                       box: CGRect(x: left, y: seg.box.minY, width: right - left, height: seg.box.height),
                       order: seg.order, wordBoxes: Array(boxes[a..<b]), rowRules: seg.rowRules)
        }
    }

    /// A sidebar beside a table (Settings' General · Appearance · Wi-Fi): a
    /// column of short items at the layout's left or right edge, most of which
    /// line up with no row of what is beside it. It is never part of a grid.
    static func sidebar(_ segs: [Seg]) -> Set<Int> {
        guard segs.count >= 6 else { return [] }
        let left = segs.map(\.box.minX).min()!, right = segs.map(\.box.maxX).max()!
        for edge in [true, false] {
            let column = segs.indices.filter { i in
                let b = segs[i].box, c = segs[i].charWidth
                return edge ? b.minX - left < 1.5 * c : right - b.maxX < 1.5 * c
            }
            guard column.count >= 3, column.allSatisfy({ segs[$0].words <= 3 }) else { continue }
            let boxes = column.map { segs[$0].box }
            let inner = boxes.map(\.maxX).max()!, outer = boxes.map(\.minX).min()!
            let beside = segs.indices.filter { i in
                !column.contains(i) && (edge ? segs[i].box.minX > inner + 2 * segs[i].charWidth
                                             : segs[i].box.maxX < outer - 2 * segs[i].charWidth)
            }
            guard beside.count >= 3, beside.count + column.count == segs.count else { continue }
            let aligned = column.filter { i in
                beside.contains { j in
                    abs(segs[i].box.midY - segs[j].box.midY) < 0.25 * min(segs[i].box.height, segs[j].box.height)
                }
            }
            if 2 * aligned.count < column.count { return Set(column) }
        }
        return []
    }

    static func grids(_ segs: [Seg]) -> [Grid] {
        let rows = rows(segs, skipping: sidebar(segs))
        var grids: [Grid] = []
        var i = 0
        while i < rows.count {
            guard rows[i].count >= 2 else { i += 1; continue }
            var end = i, lastMulti = i
            var j = i + 1
            while j < rows.count {
                if rows[j].count >= 2 {
                    end = j; lastMulti = j; j += 1
                    continue
                }
                // A one-cell row stays in the grid when it doesn't span columns
                // and either another multi-cell row follows or it is the next
                // line of a wrapped cell.
                let seg = rows[j][0]
                let spans = rows[lastMulti].filter { overlapWidth(segs[$0].box, segs[seg].box) > 0 }.count >= 2
                let multiFollows = j + 1 < rows.count && rows[j + 1].count >= 2
                if !spans, multiFollows || continuesCell(seg, above: rows[j - 1], segs) {
                    end = j; j += 1
                    continue
                }
                break
            }
            if let grid = grid(Array(rows[i...end]), segs) { grids.append(grid) }
            i = end + 1
        }
        return grids
    }

    private static func grid(_ run: [[Int]], _ segs: [Seg]) -> Grid? {
        let members = run.flatMap { $0 }
        var multi = run.filter { $0.count >= 2 }
        if multi.count == 1 {
            // One isolated row of short pieces: a running header and its page
            // number, a label and its value, a row of buttons.
            guard run.count == 1, run[0].allSatisfy({ segs[$0].words <= 6 }) else { return nil }
            return Grid(members: run[0], text: run[0].map { segs[$0].shown }.joined(separator: "\t"))
        }
        var run = run, segs = segs
        let ruled = ruledColumns(run, segs)
        if ruled == nil {
            (run, segs) = splittingAcrossBands(run, segs)
            multi = run.filter { $0.count >= 2 }
        }
        let bands = ruled == nil ? columnBands(multi, segs) : []
        let bandCount = ruled?.count ?? bands.count
        guard bandCount >= 2 else { return nil }
        func band(_ i: Int) -> Int {
            if let ruled { return ruled.column[i]! }
            let box = segs[i].box
            return bands.indices.max { a, b in
                score(bands[a], box) < score(bands[b], box)
            }!
        }
        func score(_ band: ClosedRange<CGFloat>, _ box: CGRect) -> CGFloat {
            let overlap = min(band.upperBound, box.maxX) - max(band.lowerBound, box.minX)
            return overlap > 0 ? overlap : -abs(box.midX - (band.lowerBound + band.upperBound) / 2)
        }
        var byBand = [[Int]](repeating: [], count: bandCount)
        for row in run { for i in row { byBand[band(i)].append(i) } }
        let flowing = byBand.map { isFlowingText($0.map { segs[$0] }) }

        let isTable = !flowing.contains(true)
        if !isTable {
            // Prose on the left with short tags on the right (IB marks "[2]",
            // prices, page numbers): each tag joins its row. Anything else is
            // side-by-side text columns, which the reading order already handles.
            guard let firstTag = flowing.firstIndex(of: false),
                  !flowing[firstTag...].contains(true),
                  byBand[firstTag...].joined().allSatisfy({ segs[$0].words <= 3 && segs[$0].text.count <= 12 })
            else { return nil }
        }

        var lines: [String] = []
        var cells: [Int: [Int]] = [:]
        var previous: [Int] = []
        func flush() {
            guard !cells.isEmpty else { return }
            lines.append(rowText(cells, byBand: byBand, table: isTable, segs))
            cells = [:]
        }
        for row in run {
            // The next line of wrapped cells: every text piece sits just under a
            // cell of the row above (tags may ride along, e.g. a bottom-aligned
            // "[3]"). In a table the row-label column rarely wraps together with
            // others, so a row that fills it is a new row unless it's alone.
            let content = row.filter { flowing[band($0)] || isTable }
            let continuation = !previous.isEmpty && !content.isEmpty
                && content.allSatisfy { continuesCell($0, above: previous, segs) }
                && (!isTable || row.count == 1 || !row.contains { band($0) == 0 })
            if !continuation { flush() }
            for i in row { cells[band(i), default: []].append(i) }
            previous = row
        }
        flush()
        return Grid(members: members, text: lines.joined(separator: "\n"))
    }

    /// Columns from a table's vertical grid lines, when it has them. Each cell
    /// goes to the column that starts at the nearest grid line left of it *on
    /// its own row*, so a merged cell (Lunch across Mon–Wed) lands in the first
    /// column it spans, like a spreadsheet's merged range, and a narrow column
    /// can't be swallowed by a wide neighbour. Nil — use the text's own column
    /// bands — unless grid lines seen on two or more rows split the cells into
    /// two or more columns with no two cells of a row in one column (a lone
    /// divider beside a gridless table is not its grid).
    private static func ruledColumns(_ run: [[Int]], _ segs: [Seg]) -> (count: Int, column: [Int: Int])? {
        let tolerance = ruleTolerance(run.joined(), segs)
        var sightings: [(x: CGFloat, row: Int)] = []
        for (r, row) in run.enumerated() {
            for x in Set(row.flatMap { segs[$0].rowRules }) { sightings.append((x, r)) }
        }
        sightings.sort { $0.x < $1.x }
        var groups: [[(x: CGFloat, row: Int)]] = []
        for s in sightings {
            if let last = groups.last?.last, s.x - last.x <= tolerance { groups[groups.count - 1].append(s) }
            else { groups.append([s]) }
        }
        let rules = groups.filter { Set($0.map(\.row)).count >= 2 }.map { $0.map(\.x).reduce(0, +) / CGFloat($0.count) }
        guard !rules.isEmpty else { return nil }
        var column: [Int: Int] = [:]
        for row in run {
            let own = rules.indices.filter { j in row.contains { segs[$0].rowRules.contains { abs($0 - rules[j]) <= tolerance } } }
            let present = own.isEmpty ? Array(rules.indices) : own
            for i in row {
                column[i] = present.last { rules[$0] < segs[i].box.midX }.map { $0 + 1 } ?? 0
            }
            guard Set(row.map { column[$0]! }).count == row.count else { return nil }
        }
        let used = Set(column.values).sorted()
        guard used.count >= 2 else { return nil }
        let index = Dictionary(uniqueKeysWithValues: used.enumerated().map { ($1, $0) })
        return (used.count, column.mapValues { index[$0]! })
    }

    /// A gridless table's cells that Vision read as one line (`Gold Silver`
    /// under the Gold and Silver columns) are cut where the *other* rows'
    /// columns say: only a short line whose every word overlaps exactly one of
    /// those columns, left to right, into pieces of at most three words.
    private static func splittingAcrossBands(_ run: [[Int]], _ segs: [Seg]) -> ([[Int]], [Seg]) {
        var run = run, segs = segs
        for r in run.indices {
            for i in run[r] where (2...maxSplitWords).contains(segs[i].words) {
                guard let boxes = validWordBoxes(segs[i]) else { continue }
                let others = run.indices.map { $0 == r ? run[$0].filter { $0 != i } : run[$0] }.filter { $0.count >= 2 }
                let bands = columnBands(others, segs)
                let hits = boxes.map { w in
                    bands.indices.filter { min(bands[$0].upperBound, w.maxX) > max(bands[$0].lowerBound, w.minX) }
                }
                guard hits.allSatisfy({ $0.count == 1 }) else { continue }
                let columns = hits.map { $0[0] }
                guard zip(columns, columns.dropFirst()).allSatisfy({ $0 <= $1 }) else { continue }
                let cuts = columns.indices.dropFirst().filter { columns[$0] != columns[$0 - 1] }
                let bounds = [0] + cuts + [columns.count]
                guard zip(bounds, bounds.dropFirst()).allSatisfy({ $1 - $0 <= 3 }),
                      let pieces = split(segs[i], at: cuts) else { continue }
                segs[i] = pieces[0]
                var ids = [i]
                for piece in pieces.dropFirst() { segs.append(piece); ids.append(segs.count - 1) }
                run[r] = run[r].flatMap { $0 == i ? ids : [$0] }
            }
        }
        return (run, segs)
    }

    /// Longest line `splittingAcrossBands` will cut: a row of short cells, not prose.
    private static let maxSplitWords = 8

    /// One output line for a grid row. Within a cell, stacked lines (a wrapped
    /// cell) join with a space and side-by-side pieces with a tab. In a table,
    /// empty columns keep their tab so the row still lines up in a spreadsheet.
    private static func rowText(_ cells: [Int: [Int]], byBand: [[Int]], table: Bool,
                                _ segs: [Seg]) -> String {
        func cellText(_ members: [Int]) -> String {
            let sorted = members.sorted {
                isSameRow(segs[$0].box, segs[$1].box) ? segs[$0].box.minX < segs[$1].box.minX
                                                      : segs[$0].box.minY < segs[$1].box.minY
            }
            var text = segs[sorted[0]].shown
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                text = isSameRow(segs[a].box, segs[b].box) ? text + "\t" + segs[b].shown
                                                          : joinWrapped(text, segs[b].shown)
            }
            return text
        }
        let filled = cells.keys.sorted()
        if filled.count == 1 && cells[filled[0]]!.count == 1 { return cellText(cells[filled[0]]!) }
        guard table else { return filled.map { cellText(cells[$0]!) }.joined(separator: "\t") }
        // A row that doesn't start in the table's first column keeps its leading
        // empty cells only if it actually lines up with a column (not a button
        // row sitting under the grid).
        let firstBand = filled[0]
        let first = cells[firstBand]!.min { segs[$0].box.minX < segs[$1].box.minX }!
        let start = isAligned(first, withOthersIn: byBand[firstBand], segs) ? 0 : firstBand
        return (start...filled.last!).map { cells[$0].map(cellText) ?? "" }.joined(separator: "\t")
    }

    /// Left-, right- or centre-aligned with another cell of its column.
    private static func isAligned(_ i: Int, withOthersIn column: [Int], _ segs: [Seg]) -> Bool {
        let box = segs[i].box
        return column.contains { j in
            let other = segs[j].box
            return j != i && !isSameRow(other, box)
                && (abs(other.minX - box.minX) < box.height || abs(other.maxX - box.maxX) < box.height
                    || abs(other.midX - box.midX) < box.height)
        }
    }

    /// Column bands from the x-extents of multi-cell rows: x positions covered by
    /// more than one in five rows' cells (so a single spanning cell doesn't fuse
    /// two columns in a larger grid).
    private static func columnBands(_ rows: [[Int]], _ segs: [Seg]) -> [ClosedRange<CGFloat>] {
        var edges: [(x: CGFloat, delta: Int)] = []
        for row in rows {
            for i in row {
                edges.append((segs[i].box.minX, 1))
                edges.append((segs[i].box.maxX, -1))
            }
        }
        edges.sort { $0.x == $1.x ? $0.delta < $1.delta : $0.x < $1.x }
        let threshold = rows.count / 5
        var bands: [ClosedRange<CGFloat>] = []
        var depth = 0
        var start: CGFloat = 0
        for edge in edges {
            let before = depth
            depth += edge.delta
            if before <= threshold && depth > threshold { start = edge.x }
            if before > threshold && depth <= threshold { bands.append(start...edge.x) }
        }
        return bands
    }

    /// Long lines or list items: the column is running text, not table cells.
    private static func isFlowingText(_ column: [Seg]) -> Bool {
        guard column.count >= 2 else { return false }
        let words = column.map(\.words).sorted()
        let markers = column.filter { startsWithListMarker($0.text) }.count
        return words[words.count / 2] >= 5 || markers * 2 >= column.count
    }

    /// Is `i` the next line of a wrapped cell in the row above (same column,
    /// ordinary line spacing, not a new list item)?
    private static func continuesCell(_ i: Int, above row: [Int], _ segs: [Seg]) -> Bool {
        let s = segs[i]
        return row.contains { q in
            let above = segs[q]
            return overlapsHorizontally(above.box, s.box) && s.box.minY > above.box.midY
                && s.box.minY - above.box.maxY <= 0.7 * max(above.box.height, s.box.height)
        } && !startsWithListMarker(s.text)
    }

    // MARK: - Flow (prose and code)

    private static func flow(_ run: [Seg]) -> [Piece] {
        // Split where a paragraph gap could be, classify each block, then merge
        // neighbouring code blocks (their gaps are the code's blank lines).
        var blocks: [[Seg]] = []
        for s in run {
            if let prev = blocks.last?.last,
               s.box.minY - prev.box.maxY <= maxGapRatio * max(prev.box.height, s.box.height) {
                blocks[blocks.count - 1].append(s)
            } else {
                blocks.append([s])
            }
        }
        var kinds = blocks.map(isCode)
        // A short plain block next to code in the same monospaced font
        // (`import Foundation`, a lone `}` or program output) is part of it.
        if kinds.contains(true) {
            let codeWidths = zip(blocks, kinds).filter(\.1).flatMap(\.0).filter { $0.text.count >= 4 }
                .map(\.charWidth).sorted()
            if !codeWidths.isEmpty {
                let median = codeWidths[codeWidths.count / 2]
                for i in blocks.indices where !kinds[i]
                    && ((i > 0 && kinds[i - 1]) || (i + 1 < blocks.count && kinds[i + 1]))
                    && blocks[i].allSatisfy({ $0.words <= 8 && ratio($0.charWidth, median) <= 1.12 }) {
                    kinds[i] = true
                }
            }
        }
        var groups: [(code: Bool, lines: [Seg])] = []
        for (block, code) in zip(blocks, kinds) {
            if let last = groups.last, last.code == code {
                groups[groups.count - 1].lines += block
            } else {
                groups.append((code, block))
            }
        }
        var pieces: [Piece] = []
        for group in groups {
            if group.code {
                pieces.append(Piece(kind: .code, text: codeText(group.lines), order: group.lines[0].order,
                                    box: group.lines.dropFirst().reduce(group.lines[0].box) { $0.union($1.box) }))
            } else {
                pieces += prose(group.lines)
            }
        }
        if let i = pieces.firstIndex(where: { $0.kind == .prose }), i == 0 { pieces[i].opensRun = true }
        if let i = pieces.lastIndex(where: { $0.kind == .prose }), i == pieces.count - 1 { pieces[i].closesRun = true }
        return pieces
    }

    // MARK: Code

    /// Signals only code carries: statement ends, closers, prompts,
    /// preprocessor lines, keyword + punctuation, JSON keys, code operators.
    private static let strongCodeSignals = try! NSRegularExpression(pattern: [
        #"[;{}]\s*$"#,
        #"^\s*[}\])]"#,
        // `$ `, `% `, `>>> `, `~/ib-ia $ `, `user@host:~$ `, `PS C:\> `
        #"^(?:\$|%|>>>|[\w.-]+@[\w.-]+[:\w~/.-]*\s?[$%#]|[\w/.~-]+ \$|PS [^>]*>) "#,
        #"^\s*(#include|#import|#!|// |/\*)"#,
        #"^\s*(def|class|import|from|return|if|elif|else|for|while|func|let|var|const|function|struct|enum|public|private|static|void|int|fn|pub|use|try|catch|except|switch|case|package|using|val|lambda|async|await)\b.*[(){}:;=\[\]]"#,
        #"^\s*"[^"]+"\s*:"#,
        #"(=>|===|!==|!=|&&|\|\||::)"#,
    ].map { "(?:\($0))" }.joined(separator: "|"))

    /// Signals prose, math and chemistry share now and then (`loga(`, `iron(III)`,
    /// `example.com`): they count only in a monospaced block or next to strong ones.
    private static let weakCodeSignals = try! NSRegularExpression(pattern: [
        #"\b(?!(?:sin|cos|tan|cot|sec|csc|log|ln|lg|exp|lim|max|min|det|gcd|lcm|arc)\w*\()[A-Za-z_]\w{2,}\("#,
        #"\b[A-Za-z_]\w+\.[A-Za-z_]\w+"#,                // item.price, console.log, main.py
        #"[a-z0-9]_[a-z]"#,                              // snake_case
        #"^\s*-?\s*[a-z][\w-]*:(\s|$)"#,                 // YAML `key: value`
    ].map { "(?:\($0))" }.joined(separator: "|"))

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func looksLikeCode(_ text: String) -> Bool {
        matches(strongCodeSignals, text) || matches(weakCodeSignals, text)
    }

    /// Character width (box width ÷ characters) constant across lines within
    /// 10% — only a monospaced font does that over short and long lines alike.
    static func isMonospace(_ lines: [Seg]) -> Bool {
        let widths = lines.filter { $0.text.count >= 4 }.map(\.charWidth)
        guard widths.count >= 2, let lo = widths.min(), let hi = widths.max(), lo > 0 else { return false }
        return hi / lo <= 1.1
    }

    private static func isCode(_ lines: [Seg]) -> Bool {
        let strong = lines.filter { matches(strongCodeSignals, $0.raw ?? $0.text) }.count
        let hits = lines.filter { looksLikeCode($0.raw ?? $0.text) }.count
        if lines.count == 1 { return strong == 1 && lines[0].words >= 2 }
        let monospace = isMonospace(lines)
        // A terminal session: one prompt line makes the monospaced output code too.
        return strong >= 1 && (hits * 2 >= lines.count || monospace) || monospace && hits * 3 >= lines.count
    }

    /// One line per line, indentation rebuilt from each line's left edge on the
    /// character grid, blank lines from gaps of a whole line pitch or more.
    private static func codeText(_ lines: [Seg]) -> String {
        let widths = lines.filter { $0.text.count >= 3 }.map(\.charWidth).sorted()
        let charWidth = widths.isEmpty ? lines[0].charWidth : widths[widths.count / 2]
        let left = lines.map(\.box.minX).min()!
        let pitches = zip(lines, lines.dropFirst()).map { $1.box.midY - $0.box.midY }.sorted()
        let pitch = pitches.isEmpty ? 0 : pitches[pitches.count / 2]
        var out: [String] = []
        for (index, line) in lines.enumerated() {
            if index > 0, pitch > 0 {
                let steps = Int(((line.box.midY - lines[index - 1].box.midY) / pitch).rounded())
                out += Array(repeating: "", count: min(max(steps - 1, 0), 2))
            }
            let indent = max(0, Int(((line.box.minX - left) / charWidth).rounded()))
            out.append(String(repeating: " ", count: indent) + cleanedCode(line.raw ?? line.text))
        }
        return out.joined(separator: "\n")
    }

    private static let spacedMemberAccess = try! NSRegularExpression(pattern: #"(?<=[A-Za-z0-9_)\]])\. (?=[a-z_])"#)

    /// Vision's usual misreads in code fonts: the slashed zero as `ø`, angle
    /// brackets as guillemets, and a space after a member-access dot.
    static func cleanedCode(_ line: String) -> String {
        var text = line.replacingOccurrences(of: "ø", with: "0").replacingOccurrences(of: "Ø", with: "0")
            .replacingOccurrences(of: "‹", with: "<").replacingOccurrences(of: "›", with: ">")
        text = spacedMemberAccess.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                           withTemplate: ".")
        text = dashedExtension.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                        withTemplate: ".$1")
        text = withHexDigits(text)
        text = withTripleQuotes(text)
        return withBalancedBrackets(text)
    }

    /// `main-py` → `main.py`: Vision reads a file name's dot as a hyphen.
    private static let dashedExtension = try! NSRegularExpression(
        pattern: #"(?<=[A-Za-z0-9_])-(py|js|jsx|ts|tsx|swift|txt|md|json|sh|c|h|cpp|java|rb|go|rs|html|css|log|csv|yml|yaml|toml|xml|sql)\b(?![-/])"#)

    /// A commit hash or hex id (`alb2c3d`): `l` is `1` and `O`/`o` is `0`.
    static func withHexDigits(_ line: String) -> String {
        var words = line.components(separatedBy: " ")
        for (i, word) in words.enumerated() where (7...40).contains(word.count)
            && word.allSatisfy({ $0.isHexDigit || "lOo".contains($0) }) && word.filter(\.isNumber).count >= 2
            && word.contains(where: { "lOo".contains($0) }) {
            words[i] = String(word.map { $0 == "l" ? "1" : "Oo".contains($0) ? "0" : $0 })
        }
        return words.joined(separator: " ")
    }

    /// Vision reads a triple double quote as a mix of single and double quotes
    /// (three or four marks): a line whose quote runs include a double quote
    /// gets three double quotes for each of them.
    static func withTripleQuotes(_ line: String) -> String {
        let runs = tripleQuote.matches(in: line, range: NSRange(line.startIndex..., in: line))
        let double = runs.contains { Range($0.range, in: line).map { line[$0].contains { "\"“”".contains($0) } } ?? false }
        guard double else { return line }
        return tripleQuote.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line),
                                                    withTemplate: "\"\"\"")
    }

    private static let tripleQuote = try! NSRegularExpression(pattern: #"['"‘’“”]{3,5}"#)

    /// One look-alike swap that balances a line's brackets: `Lpush, pull]` →
    /// `[push, pull]`, `else i return 0 }` → `else { return 0 }`,
    /// `[3, 4, 51):` → `[3, 4, 5]):`. Nothing changes unless exactly one
    /// candidate is found and it balances the line.
    static func withBalancedBrackets(_ line: String) -> String {
        let chars = Array(line)
        let openerOf: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        /// The first closer that doesn't fit: its index and the opener it met (nil: nothing open).
        func firstProblem(_ c: [Character]) -> (index: Int, open: Int?)? {
            var stack: [Int] = []
            var quote: Character?
            for (i, ch) in c.enumerated() {
                if let q = quote { if ch == q { quote = nil }; continue }
                if ch == "\"" || ch == "'" || ch == "`" { quote = ch; continue }
                if "([{".contains(ch) { stack.append(i); continue }
                guard let opener = openerOf[ch] else { continue }
                if let top = stack.last {
                    if c[top] == opener { stack.removeLast() } else { return (i, top) }
                } else if c[..<i].contains(where: { !$0.isWhitespace && !"})]".contains($0) }) {
                    return (i, nil) // a closer mid-line with nothing open
                }
            }
            return nil
        }
        guard let problem = firstProblem(chars) else { return line }
        var candidate: (Int, Character)?
        if let open = problem.open {
            // `[3, 4, 51)`: the glyph right before is the missing closer.
            let wanted: Character = chars[open] == "[" ? "]" : chars[open] == "{" ? "}" : ")"
            let before = problem.index - 1
            if before > open, "1lIJ|)".contains(chars[before]) { candidate = (before, wanted) }
        } else if let wanted = openerOf[chars[problem.index]] {
            for i in stride(from: problem.index - 1, through: 0, by: -1) {
                let startsToken = i == 0 || " (=:,".contains(chars[i - 1])
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                if wanted == "[", startsToken, "LlI1".contains(chars[i]),
                   let n = next, n.isLetter || n.isNumber || "\"'".contains(n) {
                    candidate = (i, "["); break
                }
                if wanted == "{", startsToken, "il(".contains(chars[i]), next == " ", i + 2 < problem.index,
                   chars[(i + 2)..<problem.index].contains(where: { $0.isLetter || $0.isNumber }) {
                    candidate = (i, "{"); break
                }
            }
        }
        guard let (index, bracket) = candidate else { return line }
        var fixed = chars
        fixed[index] = bracket
        return firstProblem(fixed) == nil ? String(fixed) : line
    }

    // MARK: Prose

    private static func prose(_ lines: [Seg]) -> [Piece] {
        var paragraphs: [[Seg]] = []
        for line in lines {
            if let para = paragraphs.last, continues(para, with: line, column: lines) {
                paragraphs[paragraphs.count - 1].append(line)
            } else {
                paragraphs.append([line])
            }
        }
        let levels = listLevels(paragraphs)
        let right = lines.map(\.box.maxX).max()!
        return paragraphs.enumerated().map { index, para in
            var text = para.dropFirst().reduce(para[0].shown) { joinWrapped($0, $1.shown) }
            if isMath(text) { text = spacedOperators(repairedMathSymbols(text)) }
            return Piece(kind: .prose, text: String(repeating: "\t", count: levels[index]) + text,
                         order: para[0].order, box: para.dropFirst().reduce(para[0].box) { $0.union($1.box) },
                         first: para[0], last: para[para.count - 1], columnRight: right)
        }
    }

    private static func continues(_ para: [Seg], with line: Seg, column: [Seg]) -> Bool {
        let prev = para[para.count - 1]
        let tallest = max(prev.box.height, line.box.height)
        if line.box.minY - prev.box.maxY > maxGapRatio * tallest { return false }
        if para.count >= 2 {
            let pitches = zip(para, para.dropFirst()).map { $1.box.midY - $0.box.midY }.sorted()
            if line.box.midY - prev.box.midY > maxPitchRatio * pitches[pitches.count / 2] { return false }
        } else if endsSentence(prev.text) {
            // A one-line paragraph has no rhythm of its own: compare with the
            // column's usual line pitch — a sentence end plus extra space is a break.
            let pitches = zip(column, column.dropFirst()).map { $1.box.midY - $0.box.midY }.filter { $0 > 0 }.sorted()
            if pitches.count >= 2, line.box.midY - prev.box.midY > 1.12 * pitches[pitches.count / 2] { return false }
            // Two lines alone: past double spacing (≈ 4.4 character widths) is
            // a gap between paragraphs.
            if pitches.count < 2, line.box.midY - prev.box.midY > 4.8 * min(prev.charWidth, line.charWidth) { return false }
        }
        if isFontChange(prev, line) { return false }
        if startsWithListMarker(line.text) { return false }
        // A first-line indent starts a paragraph — unless this is a list item's
        // hanging indent or centred text.
        let charWidth = prev.charWidth
        if line.box.minX > prev.box.minX + 1.5 * charWidth, !startsWithListMarker(para[0].text),
           abs(line.box.midX - prev.box.midX) > 1.5 * charWidth { return false }
        return wrapped(prev, before: line, column: column)
    }

    /// Heading → body and similar. Character width is reliable once both lines
    /// have ten characters; below that, glyph height has to agree.
    private static func isFontChange(_ a: Seg, _ b: Seg) -> Bool {
        let widthRatio = ratio(a.charWidth, b.charWidth)
        if a.text.count >= 10, b.text.count >= 10, widthRatio > 1.3 { return true }
        return widthRatio > fontChangeRatio && ratio(a.box.height, b.box.height) > fontChangeRatio
    }

    /// Did `prev` end because the next word didn't fit?
    private static func wrapped(_ prev: Seg, before next: Seg, column: [Seg]) -> Bool {
        // Display equations stand alone; they don't wrap into each other.
        if isMath(prev.shown) && isMath(next.shown) { return false }
        // A row of bare numbers (a matrix row, a score) isn't a sentence.
        guard prev.text.contains(where: \.isLetter) else { return false }
        let charWidth = prev.charWidth
        let widest = column.filter { overlapsHorizontally($0.box, prev.box) }.max { $0.box.maxX < $1.box.maxX }
        let right = widest?.box.maxX ?? prev.box.maxX
        // A column no wider than two words is a list of labels (a sidebar's
        // General · Appearance · Wi-Fi), not wrapped text.
        if (widest ?? prev).words <= 2, next.text.first?.isUppercase == true { return false }
        if prev.box.maxX < right - charWidth {
            let firstWord = next.text.prefix { !$0.isWhitespace }
            return prev.box.maxX + CGFloat(firstWord.count + 1) * charWidth > right - 0.5 * charWidth
        }
        // `prev` is the column's longest line, so there's no edge to test
        // against: go by the text instead.
        if let c = next.text.first, c.isLowercase { return true }
        return !endsSentence(prev.text)
    }

    /// Nesting level per paragraph: list items' left edges clustered into levels.
    private static func listLevels(_ paragraphs: [[Seg]]) -> [Int] {
        let items = paragraphs.filter { startsWithListMarker($0[0].text) }.map { $0[0] }
        guard items.count >= 2 else { return paragraphs.map { _ in 0 } }
        let widths = items.map(\.charWidth).sorted()
        let tolerance = 1.5 * widths[widths.count / 2]
        var stops: [CGFloat] = []
        for x in items.map(\.box.minX).sorted() where stops.last.map({ x - $0 > tolerance }) ?? true {
            stops.append(x)
        }
        guard stops.count >= 2 else { return paragraphs.map { _ in 0 } }
        return paragraphs.map { para in
            guard startsWithListMarker(para[0].text) else { return 0 }
            return stops.lastIndex { $0 <= para[0].box.minX + tolerance } ?? 0
        }
    }

    /// A paragraph cut by a column break: the left column's last line runs to
    /// its edge mid-sentence and the next column starts in lower case.
    private static func joinedAcrossColumns(_ pieces: [Piece]) -> [Piece] {
        var out: [Piece] = []
        for piece in pieces {
            if let prev = out.last, prev.kind == .prose, piece.kind == .prose, prev.closesRun, piece.opensRun,
               let last = prev.last, let first = piece.first,
               first.box.minX > prev.columnRight - last.charWidth, first.box.minY < last.box.minY,
               last.text.count >= 15, !isMath(last.shown), !isMath(first.shown),
               !endsSentence(last.text), first.text.first?.isLowercase == true,
               last.box.maxX + CGFloat(first.text.prefix { !$0.isWhitespace }.count + 1) * last.charWidth
                   > prev.columnRight - 0.5 * last.charWidth {
                out[out.count - 1].text = joinWrapped(prev.text, piece.text)
                out[out.count - 1].closesRun = piece.closesRun
                out[out.count - 1].last = piece.last
                out[out.count - 1].columnRight = piece.columnRight
                continue
            }
            out.append(piece)
        }
        return out
    }

    // MARK: - Text helpers

    private static let listMarker = try! NSRegularExpression(
        pattern: #"^(?:[•\-–—*☐☑☒]|\(?\d{1,3}[.)]|\(?[a-zA-Z][.)]|\(?(?:[ivx]{2,4}|[IVX]{2,4})[.)])\s"#)
    private static let bulletLookalikes: Set<Character> = ["·", "●", "◦", "▪", "‣"]

    static func startsWithListMarker(_ text: String) -> Bool {
        listMarker.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func endsSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)]»"))
        return trimmed.last.map { ".!?:;".contains($0) } ?? false
    }

    /// Joins a wrapped line onto its paragraph; a soft hyphen glued to a word
    /// before a lower-case continuation is removed (`portfo-` + `lio`), a
    /// spaced dash (`money —`, `money -`) is not.
    /// A word broken across lines rejoins: `infor-` + `mation` → `information`.
    /// A compound keeps its hyphen (`light-` + `dependent`): the joined word
    /// isn't in the system word list.
    private static func joinWrapped(_ text: String, _ next: String) -> String {
        if text.hasSuffix("-"), text.dropLast().last?.isLetter == true, let c = next.first, c.isLowercase {
            let left = text.dropLast().reversed().prefix { $0.isLetter }.reversed()
            let right = next.prefix { $0.isLetter }
            return (WordList.contains(String(left) + right) == false ? text : String(text.dropLast())) + next
        }
        return text + " " + next
    }

    private static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.first, bulletLookalikes.contains(first) {
            text = "•" + text.dropFirst()
        }
        return text
    }

    // MARK: - Geometry helpers

    private static func overlapWidth(_ a: CGRect, _ b: CGRect) -> CGFloat {
        min(a.maxX, b.maxX) - max(a.minX, b.minX)
    }

    private static func overlapsHorizontally(_ a: CGRect, _ b: CGRect) -> Bool {
        overlapWidth(a, b) > 0.5 * min(a.width, b.width)
    }

    private static func isSameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap > 0.5 * min(a.height, b.height)
    }

    private static func isAdjacent(_ a: Seg, _ b: Seg) -> Bool {
        let gap = max(a.box.minX, b.box.minX) - min(a.box.maxX, b.box.maxX)
        return gap < sameRowJoinChars * max(a.charWidth, b.charWidth)
    }

    private static func ratio(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        max(a, b) / max(min(a, b), 1e-6)
    }
}
