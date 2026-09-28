import CoreGraphics
import CoreText
import Foundation

/// Superscripts and subscripts, recovered from pixels. Vision has no notion
/// of either: `x²` comes back as `x2`, `x'` or `x`, and `a₁` as `a1` or `ay`.
/// Per recognized line this finds the glyphs (clusters of ink) and spots the
/// ones sitting raised or lowered against the glyph they follow. Then, word by
/// word (Vision's words, matched to the glyphs by the widest gaps): where
/// Vision's characters line up one-to-one with the glyphs they are used as is;
/// otherwise the word is re-read from a straightened copy in which the scripts
/// sit on the baseline at full size. Scripts are written with Unicode (`x²`,
/// `aₙ`, `10⁻³`) or `^(…)` / `_(…)` where Unicode has no glyph. Any word whose
/// glyphs and characters can't be matched is left exactly as Vision read it.
///
/// The same glyph map repairs math symbols Vision reads as look-alikes: a
/// radical (one blob enclosing others, read `V`) becomes `√(…)` over what its
/// bar covers, `+` with a bar under it `±`, `‡` becomes `≠` (one blob) or `±`,
/// and an inline stacked fraction (`n` over a short bar over `2`) is read part
/// by part into `n/2`.
enum ScriptRecovery {
    struct Glyph {
        enum Kind { case normal, sup, sub }
        var box: CGRect
        var blobs: [Int]
        var container = false
        var kind = Kind.normal
        /// An inline stacked fraction (`n` over a bar over `2`): the blobs of
        /// its numerator and denominator.
        var fraction: (numerator: [Int], denominator: [Int])? = nil
        /// Not a letter-sized glyph: leave it out of size and baseline estimates.
        var isStructure: Bool { container || fraction != nil }
    }

    /// Line-wide measurements the per-word steps need.
    struct Line {
        var glyphs: [Glyph]
        var blobs: [InkMap.Blob]
        var map: InkMap
        /// Height of capitals and digits; the unit for every threshold.
        var capHeight: CGFloat
        var baseline: CGFloat
    }

    /// `rect` is the line's box in `image` (pixels, top-left origin).
    /// `reread` runs Vision on a synthetic image and returns its text.
    /// `confident`: Vision was sure of its read (confidence ≥ 0.9). Only then
    /// must every full-size glyph keep Vision's character; a shaky read
    /// (`21120` for `2H₂O`, confidence 0.5) may be corrected by the re-read.
    static func recover(_ text: String, rect: CGRect, in image: CGImage, confident: Bool = true,
                        reread: (CGImage) -> String?) -> String? {
        let pad = rect.height * 0.3
        let crop = rect.insetBy(dx: -pad, dy: -pad).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let map = InkMap(image, rect: crop) else { return nil }
        let core = rect.offsetBy(dx: -crop.minX, dy: -crop.minY)
        // Ink of this line only: a descender from the line above or an ascender
        // from the line below pokes into the padded crop but ends outside the box.
        let blobs = map.blobs().filter { blob in
            blob.pixels.count >= 3
                && blob.box.maxY > core.minY + 0.1 * core.height && blob.box.minY < core.maxY - 0.1 * core.height
                && blob.box.minY > core.minY - 0.25 * core.height && blob.box.maxY < core.maxY + 0.25 * core.height
                && blob.box.maxX > core.minX - core.height && blob.box.minX < core.maxX + core.height
        }
        let glyphs = self.glyphs(blobs, lineHeight: core.height)
        guard glyphs.count >= 2, var line = measure(glyphs, blobs: blobs, map: map) else { return nil }
        let hasScripts = classify(&line)
        // Symbols Vision reads as look-alikes: a square root as `V`, `±` as `+`,
        // `≠` and `±` as `‡`.
        let hasSymbols = line.glyphs.contains(where: \.isStructure) || text.contains("‡") || text.contains("+")
        guard hasScripts || hasSymbols else { return nil }

        var words = text.split(whereSeparator: \.isWhitespace).map { Array($0) }
        var spaces: [Set<Int>] = words.map { _ in [] }
        // Touching letters can make one glyph of two, and Vision can drop a
        // small script; more glyphs than that means the words don't line up.
        var groups = segment(line.glyphs, into: words.count) ?? []
        if groups.count != words.count || !zip(groups, words).allSatisfy({ group, word in
            group.count - word.count <= min(1, group.filter {
                line.glyphs[$0].kind != .normal || line.glyphs[$0].fraction != nil
            }.count)
        }) {
            // All or nothing: one group, Vision's spaces kept by position.
            groups = [Array(line.glyphs.indices)]
            words = [Array(text.filter { !$0.isWhitespace })]
            var index = 0, gaps = Set<Int>()
            for c in text.trimmingCharacters(in: .whitespaces) {
                if c.isWhitespace { gaps.insert(index) } else { index += 1 }
            }
            spaces = [gaps]
        }
        let pieces = zip(groups, words).enumerated().map { g, pair in
            glyphTexts(pair.0, read: pair.1, spaces: spaces[g], line, fixCase: hasScripts, confident: confident, reread)
        }
        guard pieces.contains(where: { $0 != nil }) else { return nil }
        let out = assemble(groups, pieces: pieces, words: words, line)
        return out == text ? nil : out
    }

    /// Joins the words back into a line, opening `√(` at a radical and closing
    /// it after the last glyph under its bar.
    private static func assemble(_ groups: [[Int]], pieces: [[String]?], words: [[Character]], _ line: Line) -> String {
        var out = ""
        var openRoots: [CGFloat] = []
        func close(before x: CGFloat) {
            while let right = openRoots.last, x > right { out += ")"; openRoots.removeLast() }
        }
        for (g, group) in groups.enumerated() {
            close(before: line.glyphs[group[0]].box.midX)
            if g > 0 { out += " " }
            guard let piece = pieces[g] else { out += String(words[g]); continue }
            for (k, i) in group.enumerated() {
                let glyph = line.glyphs[i]
                close(before: glyph.box.midX)
                var text = piece[k]
                if glyph.container, let c = text.last, "Vv√/".contains(c) {
                    let under = line.glyphs.filter { !$0.container && $0.box.midX > glyph.box.minX + 0.25 * glyph.box.width
                                                     && $0.box.midX < glyph.box.maxX }.count
                    text = String(text.dropLast()) + (under > 1 ? "√(" : "√")
                    if under > 1 { openRoots.append(glyph.box.maxX) }
                }
                out += text
            }
        }
        close(before: .infinity)
        return out
    }

    // MARK: - Glyphs

    /// Blobs merged into glyphs: pieces stacked in one column (the dot of an
    /// `i`, the bars of `=`, the parts of `÷`) are one glyph. An underline-like
    /// rule is ignored; a blob that encloses others (the radical of a square
    /// root, with its bar) stays a glyph of its own.
    static func glyphs(_ blobs: [InkMap.Blob], lineHeight: CGFloat) -> [Glyph] {
        var glyphs: [Glyph] = []
        var consumed = Set<Int>()
        // Inline fractions first: a short bar with glyph-sized ink right above
        // and below it (not `=`, whose second bar is thin, nor `÷`, whose dots are tiny).
        for (index, bar) in blobs.enumerated() where !consumed.contains(index)
            && bar.box.width >= 2.5 * bar.box.height && bar.box.height <= 0.12 * lineHeight
            && bar.box.width < 2 * lineHeight {
            func part(_ above: Bool) -> [Int] {
                blobs.indices.filter { j in
                    let b = blobs[j].box
                    return j != index && !consumed.contains(j) && b.height >= max(3 * bar.box.height, 0.15 * lineHeight)
                        && b.midX > bar.box.minX - 0.1 * bar.box.width && b.midX < bar.box.maxX + 0.1 * bar.box.width
                        && (above ? b.maxY <= bar.box.minY + 1 && bar.box.minY - b.maxY < 0.5 * lineHeight
                                  : b.minY >= bar.box.maxY - 1 && b.minY - bar.box.maxY < 0.5 * lineHeight)
                }
            }
            let numerator = part(true), denominator = part(false)
            guard !numerator.isEmpty, !denominator.isEmpty else { continue }
            let members = [index] + numerator + denominator
            consumed.formUnion(members)
            let box = members.dropFirst().reduce(bar.box) { $0.union(blobs[$1].box) }
            glyphs.append(Glyph(box: box, blobs: members, fraction: (numerator, denominator)))
        }
        for (index, blob) in blobs.enumerated() where !consumed.contains(index) {
            let box = blob.box
            if box.width >= 2 * lineHeight, box.height <= 0.1 * lineHeight { continue }
            let encloses = blobs.contains { other in
                other.box != box && box.contains(CGPoint(x: other.box.midX, y: other.box.midY))
                    && other.box.width < 0.5 * box.width
            }
            if !encloses, let j = glyphs.indices.suffix(3).last(where: { j in
                let g = glyphs[j]
                guard !g.isStructure else { return false }
                let overlap = min(g.box.maxX, box.maxX) - max(g.box.minX, box.minX)
                let gap = max(g.box.minY, box.minY) - min(g.box.maxY, box.maxY)
                let size = max(g.box.height, box.height, min(g.box.width, box.width))
                return overlap >= 0.6 * min(g.box.width, box.width) && gap <= 0.5 * size
            }) {
                glyphs[j].box = glyphs[j].box.union(box)
                glyphs[j].blobs.append(index)
            } else {
                glyphs.append(Glyph(box: box, blobs: [index], container: encloses))
            }
        }
        return glyphs.sorted { $0.box.minX < $1.box.minX }
    }

    private static func measure(_ glyphs: [Glyph], blobs: [InkMap.Blob], map: InkMap) -> Line? {
        // Parentheses, brackets and bars run taller than capitals; leave them out.
        let heights = glyphs.filter { !$0.isStructure && $0.box.width >= 0.4 * $0.box.height }
            .map(\.box.height).sorted()
        guard let tallest = heights.last else { return nil }
        // Capitals, digits and ascenders — not the x-height letters.
        let full = heights.filter { $0 >= 0.8 * tallest }
        let capHeight = full[full.count / 2]
        // Baseline from full-size glyphs only — in `2ⁿ⁺¹` the scripts outnumber them.
        let bottoms = glyphs.filter { !$0.isStructure && $0.box.height >= 0.75 * capHeight
                                      && $0.box.width >= 0.4 * $0.box.height }.map(\.box.maxY).sorted()
        guard !bottoms.isEmpty else { return nil }
        return Line(glyphs: glyphs, blobs: blobs, map: map, capHeight: capHeight, baseline: bottoms[bottoms.count / 2])
    }

    /// Marks raised / lowered glyphs, each judged against the full-size glyph
    /// it follows; false when there are none.
    static func classify(_ line: inout Line) -> Bool {
        let cap = line.capHeight
        var base: Glyph?
        var pendingThin: [Int] = []
        for i in line.glyphs.indices {
            let g = line.glyphs[i]
            defer {
                // Only a full-size glyph can carry scripts (not the dot of an `i`).
                let glyph = line.glyphs[i]
                if glyph.kind == .normal && !glyph.isStructure && glyph.box.height >= 0.4 * cap { base = glyph }
            }
            guard let b = base, !g.isStructure, i > 0,
                  g.box.minX - line.glyphs[i - 1].box.maxX < 0.6 * cap else { continue }
            let refBottom = min(b.box.maxY, line.baseline + 0.1 * cap)
            let refHeight = min(b.box.height, cap)
            if isThin(g, cap) {
                // `⁻` in `10⁻³` sits well above a minus sign's height, and
                // counts only right next to a raised glyph (below).
                if g.box.midY < line.baseline - 0.55 * cap { pendingThin.append(i) }
                continue
            }
            // Commas, apostrophes and dots are smaller than any script digit.
            guard g.box.height >= 0.45 * cap else { continue }
            if g.box.maxY < refBottom - 0.4 * refHeight, g.box.minY < b.box.minY + 0.2 * b.box.height {
                line.glyphs[i].kind = .sup
            } else if g.box.maxY > refBottom + 0.12 * refHeight, g.box.minY > b.box.minY + 0.25 * b.box.height,
                      g.box.height <= 0.85 * max(b.box.height, cap) {
                line.glyphs[i].kind = .sub
            }
        }
        func touchesRaised(_ i: Int, _ j: Int) -> Bool {
            guard line.glyphs.indices.contains(j), line.glyphs[j].kind == .sup else { return false }
            let (a, b) = (line.glyphs[min(i, j)].box, line.glyphs[max(i, j)].box)
            return b.minX - a.maxX < 0.25 * cap
        }
        for i in pendingThin where touchesRaised(i, i - 1) || touchesRaised(i, i + 1) {
            line.glyphs[i].kind = .sup
        }
        return line.glyphs.contains { $0.kind != .normal }
    }

    private static func isThin(_ g: Glyph, _ cap: CGFloat) -> Bool {
        g.box.height < 0.3 * cap && g.box.width > g.box.height
    }

    /// Splits the glyphs into `count` words at the widest gaps.
    static func segment(_ glyphs: [Glyph], into count: Int) -> [[Int]]? {
        guard count >= 1, count <= glyphs.count else { return nil }
        let gaps = glyphs.indices.dropFirst().map { i in (index: i, width: glyphs[i].box.minX - glyphs[i - 1].box.maxX) }
        let cuts = Set(gaps.sorted { $0.width > $1.width }.prefix(count - 1).map { $0.index })
        var groups: [[Int]] = [[]]
        for i in glyphs.indices {
            if cuts.contains(i) { groups.append([]) }
            groups[groups.count - 1].append(i)
        }
        return groups
    }

    // MARK: - Words

    /// One word: its glyphs and Vision's characters for it (`spaces[i]`: a
    /// space before character `i`). Returns the text for each glyph, or nil to
    /// keep Vision's word as it is.
    private static func glyphTexts(_ group: [Int], read: [Character], spaces: Set<Int>, _ line: Line,
                                   fixCase: Bool, confident: Bool, _ reread: (CGImage) -> String?) -> [String]? {
        var kinds = group.map { line.glyphs[$0].kind }
        var chars = read
        var specks = Set<Int>()
        var spaces = spaces
        if read.count == group.count {
            // Vision's spaces must fall on word gaps. One inside a word means a
            // merged glyph and a dropped one cancelled out, and every character
            // after it sits on the wrong glyph (`is 1 − 3/10` → `is 13/10…`).
            let gaps = group.indices.dropFirst().map { line.glyphs[group[$0]].box.minX - line.glyphs[group[$0 - 1]].box.maxX }
            let letterGaps = gaps.indices.filter { !spaces.contains($0 + 1) }.map { gaps[$0] }.sorted()
            let letterGap = letterGaps.isEmpty ? 0 : letterGaps[letterGaps.count / 2]
            guard letterGaps.count < 8 // too few to know a letter gap (`x² − 9`)
                    || spaces.allSatisfy({ $0 < 1 || $0 >= group.count || gaps[$0 - 1] > letterGap + 0.1 * line.capHeight })
            else { return nil }
            // A speck on the baseline is a comma or full stop, whatever Vision
            // made of it next to a fraction (`3/10,` read as `To`).
            for i in kinds.indices where kinds[i] == .normal && (read[i].isLetter || read[i].isNumber) {
                let glyph = line.glyphs[group[i]]
                guard !glyph.isStructure, glyph.box.height < 0.4 * line.capHeight,
                      glyph.box.minY > line.baseline - 0.5 * line.capHeight else { continue }
                chars[i] = glyph.box.maxY > line.baseline + 0.12 * line.capHeight ? "," : "."
                specks.insert(i)
            }
            // Punctuation is meant to sit high or low: a narrow comma or dot, a
            // small apostrophe or degree sign. (A digit-sized `'` or `,` is
            // Vision misreading `x²` / `log₂`.)
            for i in kinds.indices where kinds[i] != .normal {
                let box = line.glyphs[group[i]].box, cap = line.capHeight
                if ",.;:".contains(read[i]) && box.height < 0.55 * cap
                    || "'’‘\"“”`°*^".contains(read[i]) && (box.height < 0.45 * cap || box.width < 0.25 * cap) {
                    kinds[i] = .normal
                }
            }
            // Vision's character for a script glyph can't be trusted when it is
            // punctuation (`'` / `?` for `²`), a descender letter or `z` for a
            // lowered digit (`a₁` → `ay`, `CO₂` → `COz`), or a lone sign
            // (`sin⁻0` for `sin²θ` would read as an inverse sine).
            func runHasAlphanumeric(_ i: Int) -> Bool {
                var lo = i, hi = i
                while lo > 0, kinds[lo - 1] == kinds[i] { lo -= 1 }
                while hi + 1 < kinds.count, kinds[hi + 1] == kinds[i] { hi += 1 }
                return read[lo...hi].contains { $0.isLetter || $0.isNumber }
            }
            let misread = kinds.indices.contains { i in
                guard kinds[i] != .normal else { return false }
                return !isScriptable(read[i]) || kinds[i] == .sub && "gjpqyzZ".contains(read[i])
                    || read[i] == "=" || "+-−".contains(read[i]) && !runHasAlphanumeric(i)
            }
            if misread {
                guard let text = rereadGroup(group, kinds: kinds, line, reread) else { return nil }
                let fixed = Array(text.filter { !$0.isWhitespace })
                if fixed.count == group.count {
                    // A sure first read keeps its full-size glyphs (`π` read
                    // `T`, re-read `n`); only the scripts come from the re-read.
                    chars = confident ? kinds.indices.map { kinds[$0] == .normal ? read[$0] : fixed[$0] } : fixed
                    spaces = confident ? spaces : spacePositions(text)
                } else if let aligned = align(fixed, to: read, kinds: kinds) {
                    // The re-read got some other glyph wrong (`π` → `ni`): keep
                    // Vision's first read and take only the scripts from it.
                    chars = aligned
                } else {
                    return nil
                }
            }
        } else {
            // Vision dropped or merged glyphs (`E = mc` for `E = mc²`).
            guard kinds.contains(where: { $0 != .normal }),
                  let text = rereadGroup(group, kinds: kinds, line, reread) else { return nil }
            chars = Array(text.filter { !$0.isWhitespace })
            guard chars.count == group.count else { return nil }
            spaces = spacePositions(text)
        }
        if fixCase { chars = lowercasingSmallCapitals(chars, kinds, group, line) }
        for i in chars.indices where kinds[i] == .normal {
            let glyph = line.glyphs[group[i]]
            if chars[i] == "‡" { chars[i] = glyph.blobs.count == 1 ? "≠" : "±" }
            if chars[i] == "+", isPlusMinus(glyph, line) { chars[i] = "±" }
            // Chemistry: a full-size `0` right next to a subscript is the
            // letter O (`C0₂` → `CO₂`, `H₂0` → `H₂O`).
            if chars[i] == "0", i > 0 && kinds[i - 1] == .sub || i + 1 < chars.count && kinds[i + 1] == .sub {
                chars[i] = "O"
            }
        }
        let structure = group.indices.map { line.glyphs[group[$0]].isStructure || specks.contains($0) }
        guard isFaithful(chars, kinds: kinds, structure: structure, to: read, confident: confident) else { return nil }
        var out = [String](repeating: "", count: chars.count)
        for (k, index) in group.enumerated() {
            guard let parts = line.glyphs[index].fraction else { continue }
            guard let top = rereadBlobs(parts.numerator, line, reread),
                  let bottom = rereadBlobs(parts.denominator, line, reread) else { return nil }
            kinds[k] = .normal
            chars[k] = " "
            out[k] = "\u{0}" + TextReflow.fractionPart(top) + "/" + TextReflow.fractionPart(bottom)
        }
        var i = 0
        while i < chars.count {
            let space = spaces.contains(i) && i > 0 && kinds[i] == .normal ? " " : ""
            guard kinds[i] != .normal else {
                out[i] = out[i].hasPrefix("\u{0}") ? space + out[i].dropFirst() : space + String(chars[i])
                i += 1
                continue
            }
            var end = i
            while end + 1 < chars.count, kinds[end + 1] == kinds[i] { end += 1 }
            let run = script(String(chars[i...end]), superscript: kinds[i] == .sup)
            if run.count == end - i + 1 {
                for (j, c) in zip(i...end, run) { out[j] = String(c) }
            } else {
                out[i] = run
            }
            i = end + 1
        }
        let keepsRadical = group.contains { line.glyphs[$0].container }
        return out.joined() == String(read) && !keepsRadical ? nil : out
    }

    /// Reads a few blobs on their own (a fraction's numerator or denominator),
    /// scaled up to text size. Vision won't read a lone glyph, so the image
    /// starts with a typeset `a = ` for context, stripped from the result.
    private static func rereadBlobs(_ members: [Int], _ line: Line, _ reread: (CGImage) -> String?) -> String? {
        let box = members.dropFirst().reduce(line.blobs[members[0]].box) { $0.union(line.blobs[$1].box) }
        let scale = max(1, min(3, line.capHeight / max(box.height, 1)))
        let margin = max(16, Int(line.capHeight))
        let font = CTFontCreateWithName("Helvetica" as CFString, line.capHeight / 0.72, nil)
        let prefix = CTLineCreateWithAttributedString(NSAttributedString(
            string: "a = ", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        let prefixWidth = CTLineGetTypographicBounds(prefix, nil, nil, nil)
        let width = Int((box.width * scale + prefixWidth).rounded(.up)) + 2 * margin
        let height = Int((box.height * scale).rounded(.up)) + 2 * margin
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(gray: 0, alpha: 1)
        // Sit the prefix on the part's baseline (its bottom edge).
        ctx.textPosition = CGPoint(x: CGFloat(margin), y: CGFloat(margin))
        CTLineDraw(prefix, ctx)
        let left = CGFloat(margin) + prefixWidth
        for m in members {
            for p in line.blobs[m].pixels {
                let x = (CGFloat(p % line.map.width) - box.minX) * scale + left
                let y = (CGFloat(p / line.map.width) - box.minY) * scale + CGFloat(margin)
                ctx.fill(CGRect(x: x, y: CGFloat(height) - y - scale, width: scale, height: scale))
            }
        }
        guard let text = ctx.makeImage().flatMap(reread), let equals = text.firstIndex(of: "=") else { return nil }
        let value = text[text.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// A rewrite may only add scripts and known symbol repairs: every full-size
    /// glyph must still read as Vision read it (case, `0`/`O` and `+`/`±`/`‡`/`≠`
    /// aside), and a script digit is never followed by a full-size digit
    /// (`5,¹40` is Georgia's old-style `1`, not an exponent). Anything else —
    /// a `%` taken apart into `⁰/o`, a whole line re-read into `/1_Of` — is
    /// worse than Vision's own read, which is then kept.
    static func isFaithful(_ chars: [Character], kinds: [Glyph.Kind], structure: [Bool], to read: [Character],
                           confident: Bool = true) -> Bool {
        for i in chars.indices.dropLast() where kinds[i] != .normal && chars[i].isNumber
            && kinds[i + 1] == .normal && !structure[i + 1] && chars[i + 1].isNumber {
            return false
        }
        let normal = chars.indices.filter { kinds[$0] == .normal && !structure[$0] }
        if !confident {
            // A shaky first read: the full-size glyphs may differ from it, but
            // not beyond recognition.
            let plain = String(normal.map { chars[$0] })
            return distance(plain, String(read)) * 4 <= read.count * 3
        }
        if read.count == chars.count {
            return normal.allSatisfy { same(chars[$0], read[$0]) }
        }
        // Different counts: Vision's read, minus what it made of the scripts,
        // must spell the full-size glyphs in order.
        var j = 0, skipped: [Character] = []
        for c in normal.map({ chars[$0] }) {
            while j < read.count, !same(c, read[j]) { skipped.append(read[j]); j += 1 }
            guard j < read.count else { return false }
            j += 1
        }
        skipped += read[j...]
        return skipped.count <= chars.count - normal.count && !skipped.contains { "=<>≤≥".contains($0) }
    }

    /// `out` is what a rewrite shows where Vision read `read`: the same
    /// character, or one of the deliberate repairs (lowercasing an x-height
    /// capital, `0` → `O` in chemistry, `+`/`‡` → `±`/`≠`).
    private static func same(_ out: Character, _ read: Character) -> Bool {
        out == read || "CKOPSUVWXZ".contains(read) && out == Character(read.lowercased())
            || read == "0" && out == "O" || "+‡".contains(read) && "±≠".contains(out)
    }

    /// Levenshtein distance.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return a.isEmpty ? b.count : row[b.count]
    }

    private static func spacePositions(_ text: String) -> Set<Int> {
        var index = 0, spaces = Set<Int>()
        for c in text {
            if c.isWhitespace { spaces.insert(index) } else { index += 1 }
        }
        return spaces
    }

    /// `±`: a plus with a separate bar under it.
    private static func isPlusMinus(_ glyph: Glyph, _ line: Line) -> Bool {
        let parts = glyph.blobs.map { line.blobs[$0].box }
        guard parts.count >= 2, let bottom = parts.max(by: { $0.maxY < $1.maxY }) else { return false }
        return bottom.width >= 2 * bottom.height && parts.allSatisfy { $0 == bottom || $0.maxY <= bottom.minY + 1 }
    }

    /// Vision guesses the case of letters whose capital has the same shape
    /// (`cOS`, `X₂`); one only x-height tall is lower case.
    private static func lowercasingSmallCapitals(_ chars: [Character], _ kinds: [Glyph.Kind], _ group: [Int],
                                                 _ line: Line) -> [Character] {
        var chars = chars
        for i in chars.indices where "CKOPSUVWXZ".contains(chars[i]) && kinds[i] == .normal
            && line.glyphs[group[i]].box.height < 0.85 * line.capHeight {
            chars[i] = Character(chars[i].lowercased())
        }
        return chars
    }

    /// Lines the re-read up with the first read from the left or the right —
    /// whichever agrees on every full-size glyph it covers — and returns the
    /// first read with the script characters replaced.
    static func align(_ reread: [Character], to read: [Character], kinds: [Glyph.Kind]) -> [Character]? {
        let offset = reread.count - read.count
        for fromRight in [false, true] {
            var out = read, ok = true, covered = false, agreed = 0
            for i in read.indices {
                let j = fromRight ? i + offset : i
                guard reread.indices.contains(j) else {
                    if kinds[i] != .normal { ok = false }
                    continue
                }
                if kinds[i] == .normal {
                    // Only the side the alignment is anchored on has to agree:
                    // before the scripts from the left, after them from the right.
                    let anchored = fromRight ? kinds[..<i].contains { $0 != .normal }
                                             : kinds[(i + 1)...].contains { $0 != .normal }
                    if anchored { if reread[j] == read[i] { agreed += 1 } else { ok = false } }
                } else {
                    out[i] = reread[j]
                    covered = true
                }
            }
            if ok && covered && agreed > 0 { return out }
        }
        return nil
    }

    /// Draws the word with every script glyph scaled up and dropped onto the
    /// baseline, and reads it with Vision.
    private static func rereadGroup(_ group: [Int], kinds: [Glyph.Kind], _ line: Line,
                                    _ reread: (CGImage) -> String?) -> String? {
        let glyphs = zip(group, kinds).map { index, kind -> Glyph in
            var glyph = line.glyphs[index]
            glyph.kind = kind
            return glyph
        }
        let scale: CGFloat = 1.45
        let margin = max(16, Int(line.capHeight))
        let originX = glyphs[0].box.minX
        var placements: [(blob: Int, origin: CGPoint, scale: CGFloat)] = []
        var shift: CGFloat = 0
        var i = 0
        while i < glyphs.count {
            let g = glyphs[i]
            guard g.kind != .normal else {
                for b in g.blobs {
                    let box = line.blobs[b].box
                    placements.append((b, CGPoint(x: box.minX - originX + shift, y: box.minY), 1))
                }
                i += 1
                continue
            }
            // A run of same-kind scripts moves as one piece.
            var end = i
            while end + 1 < glyphs.count, glyphs[end + 1].kind == g.kind { end += 1 }
            let run = glyphs[i...end]
            let runBox = run.dropFirst().reduce(run.first!.box) { $0.union($1.box) }
            let runBottom = run.filter { !isThin($0, line.capHeight) }.map(\.box.maxY).max() ?? runBox.maxY
            let gap = 0.15 * runBox.height
            shift += gap
            for glyph in run {
                for b in glyph.blobs {
                    let box = line.blobs[b].box
                    placements.append((b, CGPoint(x: runBox.minX - originX + (box.minX - runBox.minX) * scale + shift,
                                                  y: line.baseline - (runBottom - box.minY) * scale), scale))
                }
            }
            shift += runBox.width * (scale - 1) + gap
            i = end + 1
        }
        let top = placements.map(\.origin.y).min() ?? 0
        let bottom = placements.map { $0.origin.y + line.blobs[$0.blob].box.height * $0.scale }.max() ?? 0
        let right = placements.map { $0.origin.x + line.blobs[$0.blob].box.width * $0.scale }.max() ?? 0
        let width = Int(right.rounded(.up)) + 2 * margin
        let height = Int((bottom - top).rounded(.up)) + 2 * margin
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(gray: 0, alpha: 1)
        for placement in placements {
            let blob = line.blobs[placement.blob]
            for p in blob.pixels {
                let x = CGFloat(p % line.map.width) - blob.box.minX, y = CGFloat(p / line.map.width) - blob.box.minY
                let px = CGFloat(margin) + placement.origin.x + x * placement.scale
                let py = CGFloat(margin) + placement.origin.y - top + y * placement.scale
                ctx.fill(CGRect(x: px, y: CGFloat(height) - py - placement.scale,
                                width: placement.scale, height: placement.scale))
            }
        }
        return ctx.makeImage().flatMap(reread)
    }

    // MARK: - Output

    static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "−": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "i": "ⁱ", "j": "ʲ",
        "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "n": "ⁿ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ",
        "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
    ]
    static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "−": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
        "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ",
    ]

    /// `2` → `²`; `n+1` → `ⁿ⁺¹`; `iπ` (no Unicode superscript π) → `^(iπ)`.
    static func script(_ run: String, superscript: Bool) -> String {
        let table = superscript ? superscripts : subscripts
        if run.allSatisfy({ table[$0] != nil }) { return String(run.map { table[$0]! }) }
        let mark = superscript ? "^" : "_"
        return run.count == 1 ? mark + run : mark + "(" + run + ")"
    }

    private static func isPunctuation(_ c: Character) -> Bool {
        "'’‘\"“”`°*^,.·:;?".contains(c)
    }

    private static func isScriptable(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || "+-−=()".contains(c)
    }
}
