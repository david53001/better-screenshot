import CoreGraphics
import Foundation

/// Rebuilds paragraphs from the individual visual lines Vision returns, so a
/// bullet that wraps over five lines on a slide comes out as one line of text.
/// Pure geometry — no Vision dependency — so the rules are unit-testable.
///
/// A line continues the block above it only when all of these hold:
///   1. it sits in the same column (its x-range overlaps the block's),
///   2. the vertical spacing matches the block's rhythm (no blank-line gap,
///      no pitch jump, no font-size change),
///   3. it does not start with a list marker (`•`, `-`, `1.`, `a)` …),
///   4. the previous line actually wrapped: its width plus the next line's
///      first word would overflow the column's right edge. This is what keeps
///      short code lines apart — a line that stops well short of the column
///      edge had room for the next word and therefore ended on purpose.
///
/// Known limit: two consecutive lines of similar length with nothing longer
/// in the same column look wrapped (the longest line always "overflows"), so
/// the longest line of a code block merges with its follower.
public enum TextReflow {
    /// One recognized visual line. `box` is normalized (0…1) with a
    /// **top-left origin**: `minY` is the top edge, `maxY` the bottom.
    public struct Line: Equatable {
        public var text: String
        public var box: CGRect
        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }
    }

    /// Vertical gap above which two lines are never one paragraph, as a
    /// multiple of the taller line's height (≈ a blank line between them).
    static let maxGapRatio: CGFloat = 1.0
    /// Baseline pitch above which a line breaks a block's rhythm, relative to
    /// the block's median pitch. Measured slide: intra-paragraph jitter ≤ 1.07×,
    /// paragraph break 1.33×.
    static let maxPitchRatio: CGFloat = 1.25
    /// Height ratio between adjacent lines that reads as a font-size change.
    static let maxHeightRatio: CGFloat = 1.5
    /// Same-row fragments closer than this many character widths join with a space.
    static let sameRowJoinChars: CGFloat = 2

    private static let listMarker = try! NSRegularExpression(
        pattern: #"^(?:[•\-–—*]|\(?\d{1,3}[.)]|\(?[a-zA-Z][.)])\s"#)
    private static let bulletLookalikes: Set<Character> = ["·", "●", "◦", "▪", "‣"]

    public static func paragraphs(_ lines: [Line]) -> [String] {
        let cleaned = lines.compactMap { line -> Line? in
            let text = normalize(line.text)
            return text.isEmpty ? nil : Line(text: text, box: line.box)
        }.sorted { a, b in
            a.box.minY == b.box.minY ? a.box.minX < b.box.minX : a.box.minY < b.box.minY
        }

        var blocks: [Block] = []
        for line in cleaned {
            let columnRight = cleaned.filter { overlapsHorizontally($0.box, line.box) }
                .map(\.box.maxX).max() ?? line.box.maxX
            // Vision sometimes splits one visual row into fragments; glue those
            // back together before anything else, and never treat a row-mate as
            // a wrapped continuation.
            if let index = blocks.lastIndex(where: {
                isSameRow($0.last.box, line.box) && isAdjacent($0.last.box, line.box)
            }) {
                blocks[index].appendToLastLine(line)
                continue
            }
            if let index = blocks.lastIndex(where: { overlapsHorizontally($0.xRange, line.box) }),
               !isSameRow(blocks[index].last.box, line.box),
               continues(blocks[index], with: line, columnRight: columnRight) {
                blocks[index].append(line)
                continue
            }
            blocks.append(Block(line))
        }
        return blocks.sorted { a, b in
            a.top == b.top ? a.xRange.minX < b.xRange.minX : a.top < b.top
        }.map(\.text)
    }

    // MARK: - Rules

    private static func continues(_ block: Block, with line: Line, columnRight: CGFloat) -> Bool {
        let prev = block.last.box
        let tallest = max(prev.height, line.box.height)
        let gap = line.box.minY - prev.maxY
        if gap > maxGapRatio * tallest { return false }
        if tallest / max(min(prev.height, line.box.height), 1e-6) > maxHeightRatio { return false }
        if let pitch = block.medianPitch, line.box.minY - prev.minY > maxPitchRatio * pitch { return false }
        if startsWithListMarker(line.text) { return false }
        return wrapped(block.last, before: line, columnRight: columnRight)
    }

    /// Would the next line's first word have fit on the previous line?
    private static func wrapped(_ prev: Line, before next: Line, columnRight: CGFloat) -> Bool {
        let charWidth = prev.box.width / CGFloat(max(prev.text.count, 1))
        let firstWord = next.text.prefix { !$0.isWhitespace }
        let needed = CGFloat(firstWord.count + 1) * charWidth
        return prev.box.maxX + needed > columnRight - 0.5 * charWidth
    }

    static func startsWithListMarker(_ text: String) -> Bool {
        listMarker.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func overlapsHorizontally(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        return overlap > 0.5 * min(a.width, b.width)
    }

    private static func isSameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap > 0.5 * min(a.height, b.height)
    }

    private static func isAdjacent(_ a: CGRect, _ b: CGRect) -> Bool {
        let charWidth = min(a.height, b.height) * 0.6
        let gap = max(a.minX, b.minX) - min(a.maxX, b.maxX)
        return gap < sameRowJoinChars * charWidth
    }

    private static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.first, bulletLookalikes.contains(first) {
            text = "•" + text.dropFirst()
        }
        return text
    }

    // MARK: - Block

    private struct Block {
        private(set) var lines: [Line]
        private(set) var xRange: CGRect
        var top: CGFloat { lines[0].box.minY }
        var last: Line { lines[lines.count - 1] }

        init(_ line: Line) {
            lines = [line]
            xRange = line.box
        }

        mutating func append(_ line: Line) {
            lines.append(line)
            xRange = xRange.union(line.box)
        }

        /// Two fragments of one visual row (Vision split them) become one line.
        mutating func appendToLastLine(_ fragment: Line) {
            var merged = lines[lines.count - 1]
            merged.text += " " + fragment.text
            merged.box = merged.box.union(fragment.box)
            lines[lines.count - 1] = merged
            xRange = xRange.union(fragment.box)
        }

        var medianPitch: CGFloat? {
            guard lines.count >= 2 else { return nil }
            let pitches = zip(lines, lines.dropFirst()).map { $1.box.minY - $0.box.minY }.sorted()
            let mid = pitches.count / 2
            return pitches.count % 2 == 0 ? (pitches[mid - 1] + pitches[mid]) / 2 : pitches[mid]
        }

        var text: String {
            lines.dropFirst().reduce(lines[0].text) { acc, line in
                if acc.hasSuffix("-"), !acc.hasSuffix("--"), let c = line.text.first, c.isLowercase {
                    return String(acc.dropLast()) + line.text
                }
                return acc + " " + line.text
            }
        }
    }
}
