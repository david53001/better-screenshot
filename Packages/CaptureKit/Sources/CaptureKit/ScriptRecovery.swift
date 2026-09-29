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
        /// A fraction running past the line's box: part of it belongs to a line
        /// Vision boxed separately, so its own read is kept.
        var clipped = false
        /// The two ticks of a `"`: punctuation, never a script.
        var quote = false
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
        /// A trigonometric function is on the line, so `0`/`o` may be `θ`.
        var trig = false
        /// `dx`, `dt`…: a tall stroke may be an integral sign.
        var hasDifferential = false
        /// Both x-height letters and taller ones are on the line, so a letter's
        /// height says whether it has an ascender.
        var hasXHeight = false
    }

    /// `rect` is the line's box in `image` (pixels, top-left origin).
    /// `reread` runs Vision on a synthetic image and returns its text.
    /// `confident`: Vision was sure of its read (confidence ≥ 0.9). Only then
    /// must every full-size glyph keep Vision's character; a shaky read
    /// (`21120` for `2H₂O`, confidence 0.5) may be corrected by the re-read.
    /// `others`: the boxes of other lines, whose ink is left out.
    static func recover(_ text: String, rect: CGRect, in image: CGImage, excluding others: [CGRect] = [],
                        confident: Bool = true, reread: (CGImage) -> String?) -> String? {
        guard var line = lineGlyphs(rect: rect, in: image, excluding: others) else { return nil }
        let hasScripts = classify(&line)
        line.trig = mentionsTrig(text)
        line.hasDifferential = text.range(of: #"(?<![A-Za-z])d[a-zθ](?![a-z])"#, options: .regularExpression) != nil
        // Symbols Vision reads as look-alikes: a square root as `V`, `±` as `+`,
        // `≠` and `±` as `‡`, `θ` as `0`.
        let hasSymbols = line.glyphs.contains(where: \.isStructure) || text.contains("‡") || text.contains("+")
            || line.trig || line.hasDifferential || line.glyphs.indices.contains { shapeCharacter($0, line) != nil }
            || text.contains("A")
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
        let out = repairingLog(assemble(groups, pieces: pieces, words: words, line))
        return out == text ? nil : out
    }

    /// What a glyph Vision didn't read must be, from its shape alone: a small
    /// raised tick right after a letter is a prime, a hairline taller than a
    /// capital is `|`.
    static func shapeCharacter(_ index: Int, _ line: Line) -> Character? {
        let g = line.glyphs[index], cap = line.capHeight
        guard g.kind == .normal, !g.isStructure else { return nil }
        if g.box.height > 1.15 * cap, g.box.width < 0.15 * cap { return "|" }
        guard index > 0, g.box.height >= 0.2 * cap, g.box.height <= 0.6 * cap, g.box.width < 0.35 * cap,
              g.box.height >= 1.6 * g.box.width,
              g.box.maxY < line.baseline - 0.45 * cap else { return nil }
        let previous = line.glyphs[index - 1]
        guard !previous.isStructure, previous.box.height >= 0.6 * cap,
              g.box.minX - previous.box.maxX < 0.3 * cap else { return nil }
        return "′"
    }

    /// A cross with both strokes through the middle: `+`, not `t`.
    static func isPlusShape(_ glyph: Glyph, _ line: Line) -> Bool {
        let box = glyph.box, w = Int(box.width), h = Int(box.height)
        guard glyph.blobs.count == 1, w >= 5, h >= 5, box.width < 1.5 * box.height, box.height < 1.5 * box.width else { return false }
        var ink = Set<Int>()
        for p in line.blobs[glyph.blobs[0]].pixels { ink.insert(p) }
        func at(_ x: Int, _ y: Int) -> Bool { ink.contains((Int(box.minY) + y) * line.map.width + Int(box.minX) + x) }
        // The fullest row and column, and where they are.
        let rows = (0..<h).map { y in (0..<w).filter { at($0, y) }.count }
        let cols = (0..<w).map { x in (0..<h).filter { at(x, $0) }.count }
        guard let row = rows.indices.max(by: { rows[$0] < rows[$1] }),
              let col = cols.indices.max(by: { cols[$0] < cols[$1] }) else { return false }
        return Double(rows[row]) >= 0.8 * Double(w) && Double(cols[col]) >= 0.8 * Double(h)
            && abs(Double(row) / Double(h) - 0.5) < 0.18 && abs(Double(col) / Double(w) - 0.5) < 0.18
    }

    /// `Δ`, read `A`: a triangle closed along its base (an `A` stands on two feet).
    static func isDelta(_ glyph: Glyph, _ line: Line) -> Bool {
        let box = glyph.box, w = Int(box.width), h = Int(box.height)
        guard w >= 5, h >= 5, box.height >= 0.85 * line.capHeight else { return false }
        var ink = Set<Int>()
        for b in glyph.blobs { for p in line.blobs[b].pixels { ink.insert(p) } }
        let y0 = Int(box.minY)
        let bottom = (max(0, h - max(2, h / 10))..<h).map { y in
            (0..<w).filter { ink.contains((y0 + y) * line.map.width + Int(box.minX) + $0) }.count
        }.max() ?? 0
        return Double(bottom) >= 0.8 * Double(w)
    }

    /// A trig name as a word of its own or before its argument (`sin`, `cos2θ`,
    /// `sinx`) — not inside `second`, `since`, `cost` or `tank`.
    static func mentionsTrig(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return trigWord.matches(in: text, range: range).contains { match in
            guard let word = Range(match.range, in: text).map({ String(text[$0]) }),
                  let tail = Range(match.range(at: 1), in: text).map({ text[$0] }) else { return false }
            // `sin`, `cos2θ` and `sinx` are trig; a dictionary word (`cost`, `tank`) isn't.
            return tail.isEmpty || tail.count == 1 && WordList.contains(word) != true
        }
    }

    private static let trigWord = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])(?:sin|cos|tan|sec|csc|cot)([a-z]*)"#)

    /// `π`, which Vision reads as `T`: a bar across the top on two legs.
    static func isPi(_ glyph: Glyph, _ line: Line) -> Bool {
        let box = glyph.box, w = Int(box.width), h = Int(box.height)
        guard w >= 5, h >= 5 else { return false }
        var ink = Set<Int>()
        for b in glyph.blobs { for p in line.blobs[b].pixels { ink.insert(p) } }
        func row(_ y: Int) -> [Bool] { (0..<w).map { ink.contains((Int(box.minY) + y) * line.map.width + Int(box.minX) + $0) } }
        let top = (0..<max(2, h / 6)).map { row($0).filter { $0 }.count }.max() ?? 0
        // Legs: two runs of ink across the lower part, apart by a fifth of the width.
        let y = h - max(2, h / 5)
        let cells = row(y)
        var runs: [Range<Int>] = []
        var start: Int?
        for x in 0...w {
            let on = x < w && cells[x]
            if on, start == nil { start = x }
            if !on, let s = start { runs.append(s..<x); start = nil }
        }
        return Double(top) >= 0.8 * Double(w) && runs.count == 2
            && Double(runs[1].lowerBound - runs[0].upperBound) >= 0.2 * Double(w)
    }

    /// The glyphs of the line boxed at `rect`, measured (cap height, baseline).
    static func lineGlyphs(rect: CGRect, in image: CGImage, excluding others: [CGRect] = []) -> Line? {
        let pad = rect.height * 0.3
        let crop = rect.insetBy(dx: -pad, dy: -pad).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let map = InkMap(image, rect: crop) else { return nil }
        let core = rect.offsetBy(dx: -crop.minX, dy: -crop.minY)
        let neighbours = others.map { $0.offsetBy(dx: -crop.minX, dy: -crop.minY) }
        // Ink of this line only: a descender from the line above or an ascender
        // from the line below pokes into the padded crop but ends outside the box.
        let blobs = map.blobs().filter { blob in
            blob.pixels.count >= 3
                && blob.box.maxY > core.minY + 0.1 * core.height && blob.box.minY < core.maxY - 0.1 * core.height
                && blob.box.minY > core.minY - 0.25 * core.height && blob.box.maxY < core.maxY + 0.25 * core.height
                && blob.box.maxX > core.minX - core.height && blob.box.minX < core.maxX + core.height
                && !neighbours.contains { $0.contains(CGPoint(x: blob.box.midX, y: blob.box.midY)) && !core.contains(CGPoint(x: blob.box.midX, y: blob.box.midY)) }
        }
        var glyphs = self.glyphs(blobs, lineHeight: core.height)
        for i in glyphs.indices where glyphs[i].fraction != nil {
            let box = glyphs[i].box
            glyphs[i].clipped = box.minY < core.minY - 0.1 * core.height || box.maxY > core.maxY + 0.1 * core.height
        }
        guard glyphs.count >= 2 else { return nil }
        var all = blobs
        glyphs = splitRaisedTails(glyphs, blobs: &all, map: map)
        return measure(glyphs, blobs: all, map: map)
    }

    /// At low resolution a script touches its base (`x²` one blob): a run of
    /// columns on the glyph's right whose ink stays well off the baseline and
    /// rises above the rest is cut off as a glyph of its own.
    private static func splitRaisedTails(_ input: [Glyph], blobs: inout [InkMap.Blob], map: InkMap) -> [Glyph] {
        var glyphs = input
        let w = map.width
        guard let rough = measure(glyphs, blobs: blobs, map: map) else { return glyphs }
        for i in glyphs.indices.reversed() {
            let g = glyphs[i]
            guard g.blobs.count == 1, !g.isStructure, !g.quote, g.box.width >= 0.5 * rough.capHeight else { continue }
            // Measured without it: run together, it would pass for the tallest letter.
            var others = glyphs
            others.remove(at: i)
            guard others.count >= 2, let line = measure(others, blobs: blobs, map: map) else { continue }
            let cap = line.capHeight
            guard g.box.width >= 0.8 * cap else { continue }
            let blob = blobs[g.blobs[0]]
            let x0 = Int(g.box.minX), columns = Int(g.box.width)
            var bottom = [Int](repeating: Int.min, count: columns), top = [Int](repeating: Int.max, count: columns)
            for p in blob.pixels {
                let c = p % w - x0, y = p / w
                guard c >= 0, c < columns else { continue }
                bottom[c] = max(bottom[c], y); top[c] = min(top[c], y)
            }
            var cut = columns
            // A script's ink stays half a capital off the baseline (an italic
            // `f`'s hook comes lower, and barely rises above its stem).
            while cut > 0, bottom[cut - 1] != Int.min, CGFloat(bottom[cut - 1]) < line.baseline - 0.5 * cap { cut -= 1 }
            let run = columns - cut
            guard CGFloat(run) >= 0.3 * cap, CGFloat(cut) >= 0.3 * cap,
                  let leftBottom = bottom[..<cut].max(), CGFloat(leftBottom) > line.baseline - 0.1 * cap,
                  // (the columns where they touch may hold both)
                  let runTop = top[cut...].min(), let leftTop = top[..<max(1, cut - 2)].min(),
                  CGFloat(runTop) <= line.baseline - 0.9 * cap, CGFloat(leftTop) >= CGFloat(runTop) + 0.45 * cap
            else { continue }
            let split = x0 + cut
            let left = blob.pixels.filter { $0 % w < split }, right = blob.pixels.filter { $0 % w >= split }
            func box(_ pixels: [Int]) -> CGRect {
                let xs = pixels.map { $0 % w }, ys = pixels.map { $0 / w }
                return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()! + 1, height: ys.max()! - ys.min()! + 1)
            }
            blobs[g.blobs[0]] = InkMap.Blob(box: box(left), pixels: left)
            blobs.append(InkMap.Blob(box: box(right), pixels: right))
            glyphs[i].box = box(left)
            glyphs.insert(Glyph(box: box(right), blobs: [blobs.count - 1]), at: i + 1)
        }
        return glyphs
    }

    /// Vision drops a full stop after a closing quote or a stacked fraction
    /// (`the teachers’.`, `= 7/10.`): a round speck on the baseline right of
    /// the line's last glyph, after text ending in a quote, bracket or digit.
    static func missingFullStop(_ text: String, rect: CGRect, in image: CGImage, excluding others: [CGRect] = []) -> Bool {
        guard let end = text.last, end.isNumber || "'’\")".contains(end), text.contains(where: \.isLetter),
              let line = lineGlyphs(rect: rect, in: image, excluding: others) else { return false }
        let sorted = line.glyphs.sorted { $0.box.maxX < $1.box.maxX }
        guard sorted.count >= 3 else { return false }
        let g = sorted[sorted.count - 1].box, before = sorted[sorted.count - 2].box, cap = line.capHeight
        return g.width < 0.3 * cap && g.height < 0.3 * cap && g.height < 1.6 * g.width && g.width < 1.6 * g.height
            && abs(g.maxY - line.baseline) < 0.15 * cap && g.minX > before.maxX
    }

    /// `≈` and `±` Vision reads as `=`: two strokes, but wavy ones (each spans
    /// far more height than its thickness), or a plus over a bar.
    static func relationSymbols(_ text: String, rect: CGRect, in image: CGImage, excluding others: [CGRect] = []) -> String? {
        guard text.contains("=") else { return nil }
        let chars = Array(text)
        let positions = chars.indices.filter { !chars[$0].isWhitespace }
        let read = positions.map { chars[$0] }
        guard let line = lineGlyphs(rect: rect, in: image, excluding: others),
              let spans = alignment(Array(line.glyphs.indices), read, spaces: spacePositions(text), line) else { return nil }
        var out = chars
        for (k, span) in spans.enumerated() where span.count == 1 && read[span.lowerBound] == "=" {
            let parts = line.glyphs[k].blobs.map { line.blobs[$0] }.sorted { $0.box.minY < $1.box.minY }
            guard parts.count == 2 else { continue }
            let (upper, lower) = (parts[0], parts[1])
            let flat = { (b: InkMap.Blob) in b.box.height <= 1.6 * CGFloat(b.pixels.count) / b.box.width }
            if upper.box.height >= 0.6 * upper.box.width, flat(lower), lower.box.minY >= upper.box.maxY - 1 {
                out[positions[span.lowerBound]] = "±"
            } else if !flat(upper), !flat(lower) {
                out[positions[span.lowerBound]] = "≈"
            }
        }
        let result = String(out)
        return result == text ? nil : result
    }

    /// Dashes and dots Vision flattens, told apart by size: an em dash is
    /// about a capital wide or more, an en dash about three quarters (`14:00–17:00`,
    /// ` – ` between words), a hyphen half; a middle dot `·` is a speck, a
    /// bullet `•` twice that. Math lines are left alone (a minus is en-dash wide).
    static func dashesAndDots(_ text: String, rect: CGRect, in image: CGImage, excluding others: [CGRect] = []) -> String? {
        let separators = text.range(of: #"\d[.,]\d{3}(?!\d)"#, options: .regularExpression) != nil
        let marker = text.range(of: #"^\S "#, options: .regularExpression) != nil
        guard text.contains("-") || text.contains("•") || separators || marker, !TextReflow.isMath(text)
        else { return nil }
        let chars = Array(text)
        let positions = chars.indices.filter { !chars[$0].isWhitespace }
        let read = positions.map { chars[$0] }
        guard let line = lineGlyphs(rect: rect, in: image, excluding: others),
              let spans = alignment(Array(line.glyphs.indices), read, spaces: spacePositions(text), line) else { return nil }
        var out = chars, dropMarker = false
        for (k, span) in spans.enumerated() where span.count == 1 {
            let j = span.lowerBound, i = positions[j], g = line.glyphs[k].box, cap = line.capHeight
            let before: Character? = i > 0 ? chars[i - 1] : nil, after: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if j == 0, marker, isIcon(k, in: line) {
                // An icon Vision read as a character (`•`, `A`): not text.
                dropMarker = true
            } else if read[j] == "-", g.height < 0.3 * cap {
                if g.width >= 0.95 * cap {
                    out[i] = "—"
                } else if g.width >= 0.65 * cap, !text.contains("="), !text.contains("+"),
                          before?.isNumber == true && after?.isNumber == true
                            || j == 0 && after == " " && wordLength(chars, after: i + 1) >= 1
                            || before == " " && after == " " && wordLength(chars, before: i - 1) >= 2
                            && wordLength(chars, after: i + 1) >= 2 {
                    // A range (`14:00–17:00`), a break between words or a list
                    // marker; a minus (`x – 3`) sits among numbers and single letters.
                    out[i] = "–"
                }
            } else if read[j] == "•", j == 0, let box = checkbox(line.glyphs[k], in: line) {
                if let box { out[i] = box } else { dropMarker = true }
            } else if read[j] == "•", j > 0, g.height < 0.2 * cap, g.width < 0.25 * cap {
                out[i] = "·"
            } else if read[j] == "." || read[j] == ",", before?.isNumber == true, after?.isNumber == true {
                // A separator between digits: a comma has a tail, a full stop is
                // round (the baseline is no help with old-style figures).
                if read[j] == ".", g.height > 0.3 * cap, g.height > 1.4 * g.width {
                    out[i] = ","
                } else if read[j] == ",", g.height < 0.25 * cap, g.height < 1.2 * g.width {
                    out[i] = "."
                }
            }
        }
        var result = String(out)
        // An icon or a solid square (a ticked settings checkbox) is not a character.
        if dropMarker { result = String(result.drop { $0 != " " }.drop { $0 == " " }) }
        return result == text ? nil : result
    }

    /// A line's first glyph is an icon when it stands taller than the line's
    /// capitals (measured without it — alone, it would pass for the tallest letter).
    private static func isIcon(_ k: Int, in line: Line) -> Bool {
        var rest = line.glyphs
        rest.remove(at: k)
        guard rest.count >= 3, let text = measure(rest, blobs: line.blobs, map: line.map) else { return false }
        let g = line.glyphs[k].box
        return g.height > 1.25 * text.capHeight || g.width > 1.5 * text.capHeight
    }

    /// What Vision read as a leading `•` when it is a square: `☐` hollow, `☑`
    /// with a tick inside, `.some(nil)` (dropped) when solid. A round bullet
    /// has no ink in its box's corners.
    private static func checkbox(_ glyph: Glyph, in line: Line) -> Character?? {
        let g = glyph.box
        guard g.height >= 0.7 * line.capHeight, abs(g.width - g.height) < 0.2 * max(g.width, g.height) else { return nil }
        let pixels = glyph.blobs.flatMap { line.blobs[$0].pixels }
        let ink = Set(pixels)
        let w = line.map.width
        let reach = max(1, Int(0.12 * g.width))
        func inked(_ cx: Int, _ cy: Int, _ dx: Int, _ dy: Int) -> Bool {
            (0...reach).contains { a in (0...reach).contains { b in ink.contains((cy + b * dy) * w + cx + a * dx) } }
        }
        let x0 = Int(g.minX), y0 = Int(g.minY), x1 = Int(g.maxX) - 1, y1 = Int(g.maxY) - 1
        guard inked(x0, y0, 1, 1), inked(x1, y0, -1, 1), inked(x0, y1, 1, -1), inked(x1, y1, -1, -1) else { return nil }
        let holes = line.map.holes(of: pixels, in: g)
        let open = holes.reduce(0) { $0 + $1.width * $1.height }
        if open < 0.3 * g.width * g.height {
            return Double(pixels.count) > 0.85 * Double(g.width * g.height) ? .some(nil) : nil
        }
        return holes.count >= 2 || glyph.blobs.count >= 2 ? "☑" : "☐"
    }

    /// Letters in the word ending just before `index` (or starting just after).
    private static func wordLength(_ chars: [Character], before index: Int) -> Int {
        guard index >= 0 else { return 0 }
        return chars[..<index].reversed().prefix { $0.isLetter }.count
    }

    private static func wordLength(_ chars: [Character], after index: Int) -> Int {
        guard index < chars.count else { return 0 }
        return chars[(index + 1)...].prefix { $0.isLetter }.count
    }

    /// A monospaced line's spaces, rebuilt from where its glyphs sit: every
    /// character takes one cell, so the gap between two characters says how many
    /// spaces lie between them (`items ()` → `items()`, `$curl-fsSL` →
    /// `$ curl -fsSL`, two spaces before an inline `#` comment). Nil when the
    /// line isn't monospaced or its characters can't be matched to glyphs.
    static func monospaceSpacing(_ text: String, rect: CGRect, in image: CGImage, excluding others: [CGRect] = []) -> String? {
        let lead = text.prefix { $0 == " " }
        let read = Array(text.filter { $0 != " " })
        guard read.count >= 4, let line = lineGlyphs(rect: rect, in: image, excluding: others),
              let spans = alignment(Array(line.glyphs.indices), read, spaces: [], line) else { return nil }
        // Each character's centre: glyphs holding several share their width.
        var centres = [CGFloat](repeating: 0, count: read.count)
        for (k, span) in spans.enumerated() where !span.isEmpty {
            let box = line.glyphs[k].box
            for (m, j) in span.enumerated() {
                centres[j] = box.minX + (CGFloat(m) + 0.5) * box.width / CGFloat(span.count)
            }
        }
        let placed = spans.flatMap { Array($0) }
        // Every glyph read: where Vision dropped one, its cell isn't a space.
        guard placed.count == read.count, !spans.contains(where: \.isEmpty) else { return nil }
        let steps = read.indices.dropFirst().map { centres[$0] - centres[$0 - 1] }
        let sorted = steps.sorted()
        let cell = sorted[sorted.count / 2]
        guard cell > 2 else { return nil }
        // Monospaced: nearly every step is a whole number of cells.
        let whole = steps.filter { abs($0 / cell - ($0 / cell).rounded()) < 0.2 && $0 > 0.5 * cell }.count
        guard Double(whole) >= 0.9 * Double(steps.count) else { return nil }
        var out = String(lead) + String(read[0])
        for (i, step) in steps.enumerated() {
            // Two cells apart is one space; a glyph off-centre in its cell doesn't make one.
            out += String(repeating: " ", count: max(0, Int((step / cell - 0.65).rounded(.down)))) + String(read[i + 1])
        }
        return out == text ? nil : out
    }

    /// `{` or `}` from its outline: a point at mid-height on one side, and the
    /// stems above and below it near the middle (a parenthesis curves smoothly).
    static func brace(_ blob: InkMap.Blob, mapWidth: Int) -> Character? {
        let box = blob.box, w = Int(box.width), h = Int(box.height)
        guard h >= 8, w >= 3, box.height >= 1.8 * box.width else { return nil }
        var left = [Int](repeating: w, count: h), right = [Int](repeating: -1, count: h)
        for p in blob.pixels {
            let x = p % mapWidth - Int(box.minX), y = p / mapWidth - Int(box.minY)
            guard y >= 0, y < h else { continue }
            left[y] = min(left[y], x)
            right[y] = max(right[y], x)
        }
        // The point: the row in the middle band reaching furthest out on one
        // side. A brace's point is far from its stem (the other side of that
        // row); a parenthesis there is one stroke thick.
        let band = Array((h * 2 / 5)...(h * 3 / 5))
        let quarter = [h / 4, h * 3 / 4]
        let step = max(1, w / 6)
        if let row = band.min(by: { left[$0] < left[$1] }), left[row] <= w / 6,
           quarter.allSatisfy({ left[$0] >= left[row] + step }), right[row] - left[row] >= (2 * w) / 5 {
            return "{"
        }
        if let row = band.max(by: { right[$0] < right[$1] }), right[row] >= w - 1 - w / 6,
           quarter.allSatisfy({ right[$0] <= right[row] - step }), right[row] - left[row] >= (2 * w) / 5 {
            return "}"
        }
        return nil
    }

    /// Two holes stacked one above the other in a full-size glyph: `θ` (Vision
    /// reads it `0`, `o` or `A`). A slashed zero's holes sit side by side.
    static func isTheta(_ glyph: Glyph, _ line: Line) -> Bool {
        guard glyph.box.height >= 0.6 * line.capHeight, !glyph.isStructure else { return false }
        let holes = line.map.holes(of: glyph.blobs.flatMap { line.blobs[$0].pixels }, in: glyph.box)
            .sorted { $0.midY < $1.midY }
        guard holes.count == 2 else { return false }
        return abs(holes[0].midX - holes[1].midX) < 0.3 * glyph.box.width && holes[0].maxY <= holes[1].minY + 1
    }

    /// `log` with a subscript base or an argument, whatever look-alikes Vision
    /// read for it (`10g₂8`, `l0gₐx`); `ln` before its argument, which Vision
    /// reads as the word `In` (`In e³ = 3`, `In(x)`).
    static func repairingLog(_ text: String) -> String {
        var log = logLookAlike.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "log")
        // `10g3 (x + 1)`: a base Vision didn't lower is a subscript.
        for match in logWithBase.matches(in: log, range: NSRange(log.startIndex..., in: log)).reversed() {
            guard let range = Range(match.range, in: log), let base = Range(match.range(at: 1), in: log) else { continue }
            log.replaceSubrange(range, with: "log" + script(String(log[base]), superscript: false) + "(")
        }
        return lnLookAlike.stringByReplacingMatches(in: log, range: NSRange(log.startIndex..., in: log), withTemplate: "ln")
    }

    private static let logWithBase = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])[l1I|][o0O]g(\d{1,2}) ?\("#)

    private static let lnLookAlike = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])[I|]n(?=\(|[ ]?[a-zθ](?:[⁰-⁹¹²³]|\s?[=+)])|[ ]?\d+(?:\.\d+)?\s?[/=)×·+\-])"#)

    private static let logLookAlike = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])[l1I|][o0O]g(?=[₀-₉ₐₑₒₓₕₖₗₘₙₚₛₜ(])"#)

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
            // A word that starts with a script belongs to the one before (`Ba` `²⁺`).
            if g > 0 && (line.glyphs[group[0]].kind == .normal || pieces[g] == nil) { out += " " }
            guard let piece = pieces[g] else { out += String(words[g]); continue }
            for (k, i) in group.enumerated() {
                let glyph = line.glyphs[i]
                close(before: glyph.box.midX)
                var text = piece[k]
                // A radical is found from its ink; Vision may have read it as
                // anything or nothing (`|a| = 2² + …` with the root dropped).
                if glyph.container, text.allSatisfy({ !$0.isLetter || "Vvl".contains($0) }), isRadical(glyph, line) {
                    if let c = text.last, "Vv√/\\|1l-".contains(c) { text.removeLast() }
                    let under = line.glyphs.filter { !$0.container && $0.box.midX > glyph.box.minX + 0.25 * glyph.box.width
                                                     && $0.box.midX < glyph.box.maxX }.count
                    text += under > 1 ? "√(" : "√"
                    if under > 1 { openRoots.append(glyph.box.maxX) }
                }
                out += text
            }
        }
        close(before: .infinity)
        return out
    }

    /// A radical's ink: a bar along the top and a tick down at the left — its
    /// bottom row is inked only near the left (a box around text has a floor).
    static func isRadical(_ glyph: Glyph, _ line: Line) -> Bool {
        let box = glyph.box, w = Int(box.width), h = Int(box.height)
        guard w >= 6, h >= 6 else { return false }
        // Something sits under its bar (an `fi` ligature has a hook, not a roof).
        guard line.glyphs.contains(where: { !$0.container && $0.box.midX > box.minX + 0.25 * box.width
                                             && $0.box.midX < box.maxX && $0.box.minY > box.minY }) else { return false }
        let ink = Set(glyph.blobs.flatMap { line.blobs[$0].pixels })
        func row(_ y: Int) -> [Int] { (0..<w).filter { ink.contains((Int(box.minY) + y) * line.map.width + Int(box.minX) + $0) } }
        let top = (0..<max(2, h / 8)).map { row($0).count }.max() ?? 0
        let bottom = (h - max(2, h / 8)..<h).flatMap { row($0) }
        return Double(top) >= 0.6 * Double(w) && !bottom.isEmpty && Double(bottom.max()!) < 0.45 * Double(w)
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
                // Dots stacked in a column (`:`, `;`, `!`) are one glyph too.
                let size = max(g.box.height, box.height, min(g.box.width, box.width), 0.5 * lineHeight)
                return overlap >= 0.6 * min(g.box.width, box.width) && gap <= 0.5 * size
            }) {
                glyphs[j].box = glyphs[j].box.union(box)
                glyphs[j].blobs.append(index)
            } else {
                glyphs.append(Glyph(box: box, blobs: [index], container: encloses))
            }
        }
        // The two ticks of a `"` side by side, small and level, are one glyph.
        var merged: [Glyph] = []
        for g in glyphs.sorted(by: { $0.box.minX < $1.box.minX }) {
            if let last = merged.last, !last.isStructure, !g.isStructure,
               max(last.box.height, g.box.height) < 0.4 * lineHeight, max(last.box.width, g.box.width) < 0.25 * lineHeight,
               g.box.minX - last.box.maxX < 0.12 * lineHeight, abs(g.box.minY - last.box.minY) < 0.08 * lineHeight,
               abs(g.box.height - last.box.height) < 0.15 * lineHeight,
               last.box.height > 1.3 * last.box.width, g.box.height > 1.3 * g.box.width {
                merged[merged.count - 1].box = last.box.union(g.box)
                merged[merged.count - 1].blobs += g.blobs
                merged[merged.count - 1].quote = true
            } else {
                merged.append(g)
            }
        }
        return merged
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
        var line = Line(glyphs: glyphs, blobs: blobs, map: map, capHeight: capHeight, baseline: bottoms[bottoms.count / 2])
        // On the baseline: a raised `²` isn't a tall letter, nor `=` a short one.
        let letters = glyphs.filter { !$0.isStructure && $0.box.width >= 0.4 * $0.box.height && $0.box.height >= 0.45 * capHeight
            && abs($0.box.maxY - line.baseline) < 0.15 * capHeight }
        line.hasXHeight = letters.filter { $0.box.height < 0.8 * capHeight }.count >= 2
            && letters.contains { $0.box.height >= 0.9 * capHeight }
        return line
    }

    /// Marks raised / lowered glyphs, each judged against the full-size glyph
    /// it follows; false when there are none.
    static func classify(_ line: inout Line) -> Bool {
        let cap = line.capHeight
        // The top of x-height letters (`a e o`), when the line has them.
        let xTops = line.glyphs.filter { !$0.isStructure && $0.box.height >= 0.5 * cap && $0.box.height <= 0.85 * cap
            && abs($0.box.maxY - line.baseline) < 0.1 * cap }.map(\.box.minY).sorted()
        let xTop: CGFloat? = xTops.count >= 3 ? xTops[xTops.count / 2] : nil
        var base: Glyph?
        var pendingThin: [Int] = []
        for i in line.glyphs.indices {
            let g = line.glyphs[i]
            defer {
                // Only a full-size glyph can carry scripts (not the dot of an `i`).
                let glyph = line.glyphs[i]
                // …nor an apostrophe, which doesn't sit on the baseline.
                if glyph.kind == .normal && !glyph.isStructure && glyph.box.height >= 0.4 * cap
                    && glyph.box.maxY > line.baseline - 0.3 * cap { base = glyph }
            }
            guard let b = base, !g.isStructure, !g.quote, i > 0,
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
            // A script sits beside its base, not over the glyph after it (the
            // top ring of a `%` overlaps its slash).
            if i + 1 < line.glyphs.count {
                let next = line.glyphs[i + 1].box
                if min(g.box.maxX, next.maxX) - max(g.box.minX, next.minX) > 0.3 * g.box.width { continue }
            }
            if g.box.maxY < refBottom - 0.4 * refHeight, g.box.minY < b.box.minY + 0.2 * b.box.height {
                line.glyphs[i].kind = .sup
            } else if g.box.maxY > refBottom + 0.12 * refHeight, g.box.minY > b.box.minY + 0.25 * b.box.height,
                      g.box.height <= 0.85 * max(b.box.height, cap),
                      // A subscript hangs off the glyph before it; after a word
                      // space it is a descender letter (`organizează pe`, `, p. 42`)…
                      g.box.minX - line.glyphs[i - 1].box.maxX < 0.35 * cap,
                      // …and so is a lowered glyph whose top is at x-height.
                      xTop.map({ g.box.minY > $0 + 0.12 * cap }) ?? true {
                line.glyphs[i].kind = .sub
            }
        }
        func touchesRaised(_ i: Int, _ j: Int) -> Bool {
            guard line.glyphs.indices.contains(j), line.glyphs[j].kind == .sup else { return false }
            let (a, b) = (line.glyphs[min(i, j)].box, line.glyphs[max(i, j)].box)
            return b.minX - a.maxX < 0.25 * cap
        }
        // …or a charge sign alone high after a letter (`OH⁻`).
        func loneRaised(_ i: Int) -> Bool {
            guard i > 0, line.glyphs[i - 1].kind == .normal, !line.glyphs[i - 1].isStructure else { return false }
            let g = line.glyphs[i].box
            return g.minX - line.glyphs[i - 1].box.maxX < 0.25 * cap && g.midY < line.baseline - 0.6 * cap
                && g.width < 0.8 * cap && g.width >= 0.3 * cap && g.width >= 2 * g.height
        }
        for i in pendingThin where touchesRaised(i, i - 1) || touchesRaised(i, i + 1) || loneRaised(i) {
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
    ///
    /// Characters are matched to glyphs by `alignment`, not one-to-one: italic
    /// letters touch (`2x` is one blob), a stacked fraction is one glyph Vision
    /// reads as anything from nothing to a whole numerator, and Vision drops
    /// small scripts. Each character becomes a slot on its glyph; a script or
    /// fraction glyph always has exactly one slot.
    private static func glyphTexts(_ group: [Int], read: [Character], spaces: Set<Int>, _ line: Line,
                                   fixCase: Bool, confident: Bool, _ reread: (CGImage) -> String?) -> [String]? {
        let original = read
        var read = read, spaces = spaces
        if !confident, group.contains(where: { line.glyphs[$0].kind != .normal }),
           let text = rereadGroup(group, kinds: group.map { line.glyphs[$0].kind }, line, reread) {
            // A shaky first read (`21120` for `2H₂O`): a sure re-read of the
            // straightened word replaces it, if it isn't unrecognisably different.
            let fixed = Array(text.filter { !$0.isWhitespace })
            if distance(String(fixed), String(read)) * 2 <= read.count {
                read = fixed
                spaces = spacePositions(text)
            }
        }
        guard let spans = alignment(group, read, spaces: spaces, line) else { return nil }
        var slotGlyph: [Int] = [], slotOf: [Int] = [], chars: [Character] = [], kinds: [Glyph.Kind] = []
        var slotSpaces = Set<Int>()
        var badSpans = Set<Int>(), shaped = Set<Int>()
        // Script-like pieces of a `½` (its low `2`) that the alignment gave no
        // character are part of it, not scripts.
        let vulgarPieces = Set(group.indices.filter { k in
            line.glyphs[group[k]].kind != .normal && spans[k].isEmpty && spans[k].lowerBound > 0
                && vulgarFractions.contains(read[spans[k].lowerBound - 1])
        })
        for (k, index) in group.enumerated() {
            let glyph = line.glyphs[index], span = spans[k]
            let single = glyph.kind != .normal && !vulgarPieces.contains(k) || glyph.fraction != nil
            let positions = single ? [span.lowerBound] : Array(span)
            if single && glyph.fraction == nil && span.count != 1 { badSpans.insert(chars.count) }
            // A glyph Vision skipped whose shape says what it is: a prime after
            // a letter (`f′(x)`), a bar taller than a capital (`P(A|B)`).
            if !single, span.isEmpty, let c = shapeCharacter(index, line) {
                slotGlyph.append(index)
                slotOf.append(k)
                kinds.append(.normal)
                chars.append(c)
                shaped.insert(chars.count - 1)
                continue
            }
            for (n, position) in positions.enumerated() {
                if position > 0 && spaces.contains(position) && (n == 0 || !single) { slotSpaces.insert(chars.count) }
                slotGlyph.append(index)
                slotOf.append(k)
                kinds.append(glyph.kind)
                chars.append(span.count == 0 || !read.indices.contains(position) ? "?" : read[position])
            }
            // Punctuation the alignment skipped (a comma run into the `y`
            // before it) stays where Vision read it.
            var next = span.isEmpty ? nil : span.upperBound
            while let p = next, read.indices.contains(p), !spans.contains(where: { $0.contains(p) }),
                  ".,'`’‘·".contains(read[p]) {
                slotGlyph.append(index)
                slotOf.append(k)
                kinds.append(.normal)
                chars.append(read[p])
                next = p + 1
            }
        }
        var repaired = shaped
        // A thin raised or lowered stroke is a minus, whatever Vision made of it.
        for i in chars.indices where kinds[i] != .normal && "_~—–".contains(chars[i]) && isThin(line.glyphs[slotGlyph[i]], line.capHeight) {
            chars[i] = "-"
        }
        // A symbol that is a superscript already (`™`, `®`, `°`, `²`): keep
        // Vision's character for the run and drop the run's other slots.
        var dropped = Set<Int>()
        for i in chars.indices where kinds[i] != .normal && "™®©°¹²³⁰⁴⁵⁶⁷⁸⁹ⁿ℠".contains(chars[i]) {
            var lo = i, hi = i
            while lo > 0, kinds[lo - 1] == kinds[i] { lo -= 1 }
            while hi + 1 < kinds.count, kinds[hi + 1] == kinds[i] { hi += 1 }
            for j in lo...hi where j != i && chars[j] == "?" { dropped.insert(j); repaired.insert(j) }
            for j in lo...hi { kinds[j] = .normal }
            repaired.insert(i)
        }
        let firstRead = chars
        var spacesOut = slotSpaces
        // A speck on the baseline is a comma or full stop, whatever Vision
        // made of it next to a fraction (`3/10,` read as `To`).
        for i in kinds.indices where kinds[i] == .normal && (chars[i].isLetter || chars[i].isNumber)
            && slotGlyph.filter({ $0 == slotGlyph[i] }).count == 1 {
            let glyph = line.glyphs[slotGlyph[i]]
            guard !glyph.isStructure, glyph.box.height < 0.4 * line.capHeight,
                  glyph.box.minY > line.baseline - 0.5 * line.capHeight else { continue }
            chars[i] = glyph.box.maxY > line.baseline + 0.12 * line.capHeight ? "," : "."
            repaired.insert(i)
        }
        // Punctuation is meant to sit high or low: a narrow comma or dot, a
        // small apostrophe or degree sign. (A digit-sized `'` or `,` is
        // Vision misreading `x²` / `log₂`.)
        for i in kinds.indices where kinds[i] != .normal && line.glyphs[slotGlyph[i]].fraction == nil {
            let box = line.glyphs[slotGlyph[i]].box, cap = line.capHeight
            if ",.;:".contains(chars[i]) && box.height < 0.55 * cap
                || "'’‘\"“”`°*^".contains(chars[i]) && (box.height < 0.45 * cap || box.width < 0.25 * cap) {
                kinds[i] = .normal
            }
        }
        // Vision's character for a script glyph can't be trusted when it is
        // missing, punctuation (`'` / `?` for `²`), a descender letter or `z`
        // for a lowered digit (`a₁` → `ay`, `CO₂` → `COz`), `=` (`s⁻²` →
        // `s=2`), or a lone sign (`sin⁻0` for `sin²θ` would read as an inverse sine).
        func runHasAlphanumeric(_ i: Int) -> Bool {
            var lo = i, hi = i
            while lo > 0, kinds[lo - 1] == kinds[i] { lo -= 1 }
            while hi + 1 < kinds.count, kinds[hi + 1] == kinds[i] { hi += 1 }
            return chars[lo...hi].contains { $0.isLetter || $0.isNumber }
        }
        let misread = badSpans.contains { kinds[$0] != .normal } || kinds.indices.contains { i in
            guard kinds[i] != .normal else { return false }
            return !isScriptable(chars[i]) || kinds[i] == .sub && "gjpqyzZ".contains(chars[i])
                || chars[i] == "=" || "+-−".contains(chars[i]) && !runHasAlphanumeric(i)
        }
        let hasScripts = kinds.contains { $0 != .normal }
        // Per glyph again: a punctuation demotion above is a glyph's kind now.
        let glyphKinds = group.indices.map { k in
            slotOf.firstIndex(of: k).map { kinds[$0] } ?? (vulgarPieces.contains(k) ? .normal : line.glyphs[group[k]].kind)
        }
        let text = misread || hasScripts ? rereadGroup(group, kinds: glyphKinds, line, reread) : nil
        if misread && text == nil { return nil }
        if let text {
            let fixed = Array(text.filter { !$0.isWhitespace })
            var fixedSpaces = spacePositions(text)
            if !misread {
                // The scripts were read fine; the re-read only settles the
                // letter right before them, which Vision reads as a digit when a
                // script crowds it (`3x²` → `322`).
                if fixed.count == chars.count {
                    for i in chars.indices.dropLast() where kinds[i] == .normal && kinds[i + 1] != .normal
                        && chars[i].isNumber && fixed[i].isLetter && fixed[i + 1] == chars[i + 1] {
                        chars[i] = fixed[i]
                        repaired.insert(i)
                    }
                }
            } else if fixed.count == chars.count {
                // A sure first read keeps its full-size glyphs (`π` read `T`,
                // re-read `n`); only the scripts come from the re-read.
                chars = confident ? kinds.indices.map { kinds[$0] == .normal ? chars[$0] : fixed[$0] } : fixed
                if !confident { spacesOut = fixedSpaces }
            } else if let again = alignment(group, fixed, spaces: fixedSpaces, line, kinds: glyphKinds) {
                // The re-read split the glyphs differently: take each script
                // glyph's character from it (and, on a shaky line, whole glyphs
                // whose slots match).
                for i in chars.indices {
                    let span = again[slotOf[i]]
                    let slotsHere = slotOf.filter { $0 == slotOf[i] }.count
                    if kinds[i] != .normal {
                        guard span.count == 1 else { return nil }
                        chars[i] = fixed[span.lowerBound]
                    } else if !confident, span.count == slotsHere {
                        chars[i] = fixed[span.lowerBound + (i - slotOf.firstIndex(of: slotOf[i])!)]
                    }
                }
                fixedSpaces = []
            } else if chars.count == read.count, let aligned = align(fixed, to: chars, kinds: kinds) {
                // The re-read got some other glyph wrong (`π` → `ni`): keep
                // Vision's first read and take only the scripts from it.
                chars = aligned
            } else {
                return nil
            }
        }
        // Ordinals stay on the line: `3rd`, `19th`, raised or not.
        for i in chars.indices where kinds[i] == .sup && (i == 0 || kinds[i - 1] != .sup) && i > 0 && chars[i - 1].isNumber {
            var end = i
            while end + 1 < chars.count, kinds[end + 1] == .sup { end += 1 }
            if ["st", "nd", "rd", "th"].contains(String(chars[i...end]).lowercased()) {
                for j in i...end { kinds[j] = .normal; repaired.insert(j) }
            }
        }
        if fixCase {
            for i in chars.indices where "CKOPSUVWXZ".contains(chars[i]) && kinds[i] == .normal
                && slotGlyph.filter({ $0 == slotGlyph[i] }).count == 1
                && line.glyphs[slotGlyph[i]].box.height < 0.85 * line.capHeight {
                chars[i] = Character(chars[i].lowercased())
            }
            // Only when the line shows both heights: with no capital or digit
            // on the baseline, "cap height" is the x-height (`s = ut + ½at²`).
            for i in chars.indices where line.hasXHeight && "copsuvwxz".contains(chars[i]) && kinds[i] == .normal
                && slotGlyph.filter({ $0 == slotGlyph[i] }).count == 1
                && line.glyphs[slotGlyph[i]].box.height >= 0.92 * line.capHeight
                && line.glyphs[slotGlyph[i]].box.maxY < line.baseline + 0.1 * line.capHeight {
                chars[i] = Character(chars[i].uppercased())
                repaired.insert(i)
            }
        }
        // A shape repair never lands inside an ordinary word: `Add` is not `Δdd`,
        // `Tank` not `πank` — the letter is followed by two more lowercase ones,
        // or sits between letters.
        func insideWord(_ i: Int) -> Bool {
            let after = chars[(i + 1)...].prefix { $0.isLowercase }.count
            let before = i > 0 && chars[i - 1].isLetter
            return after >= 2 || before && after >= 1
        }
        for i in chars.indices where kinds[i] == .normal && slotGlyph.filter({ $0 == slotGlyph[i] }).count == 1 {
            let glyph = line.glyphs[slotGlyph[i]]
            if chars[i] == "‡" { chars[i] = glyph.blobs.count == 1 ? "≠" : "±" }
            if chars[i] == "+", isPlusMinus(glyph, line) { chars[i] = "±" }
            if chars[i] == "A", !insideWord(i), isDelta(glyph, line) {
                chars[i] = "Δ"
                repaired.insert(i)
            }
            if chars[i] == "T", !insideWord(i), isPi(glyph, line) {
                chars[i] = "π"
                repaired.insert(i)
            }
            // An integral sign, read `/` or `J`: a glyph over twice the height
            // of a capital, on a line with a `dx`.
            if "/|JSf(".contains(chars[i]), !insideWord(i), glyph.box.height > 2.2 * line.capHeight, line.hasDifferential {
                chars[i] = "∫"
                repaired.insert(i)
            }
            if line.trig, !"B8g%&θ".contains(chars[i]), !insideWord(i), glyph.fraction == nil, isTheta(glyph, line) {
                chars[i] = "θ"
                repaired.insert(i)
            }
            // Chemistry: a full-size `0` right next to a subscript is the
            // letter O (`C0₂` → `CO₂`, `H₂0` → `H₂O`).
            if chars[i] == "0", i > 0 && kinds[i - 1] == .sub || i + 1 < chars.count && kinds[i + 1] == .sub {
                chars[i] = "O"
            }
        }
        // Vision reads both `π` and an italic `n` as Cyrillic `П`/`п`: the shape
        // decides (a bar across the top on two legs is π).
        for i in chars.indices where "Пп".contains(chars[i]) {
            chars[i] = isPi(line.glyphs[slotGlyph[i]], line) ? "π" : "n"
            repaired.insert(i)
        }
        // A raised plus reads as `t` (`Fe³⁺` → `Fe3t`).
        for i in chars.indices where kinds[i] == .sup && "tT+f".contains(chars[i]) && isPlusShape(line.glyphs[slotGlyph[i]], line) {
            chars[i] = "+"
        }
        for i in chars.indices where kinds[i] != .normal && "_~—–".contains(chars[i]) && isThin(line.glyphs[slotGlyph[i]], line.capHeight) {
            chars[i] = "-"
        }
        let structure = chars.indices.map { line.glyphs[slotGlyph[$0]].isStructure || repaired.contains($0) }
        guard isFaithful(chars, kinds: kinds, structure: structure, to: firstRead, confident: confident) else { return nil }
        var slotOut = [String](repeating: "", count: chars.count)
        for i in chars.indices {
            guard let parts = line.glyphs[slotGlyph[i]].fraction else { continue }
            if line.glyphs[slotGlyph[i]].clipped {
                kinds[i] = .normal
                chars[i] = " "
                slotOut[i] = "\u{0}" + String(read[spans[slotOf[i]]])
                continue
            }
            guard let top = rereadBlobs(parts.numerator, line, reread),
                  let bottom = rereadBlobs(parts.denominator, line, reread) else { return nil }
            kinds[i] = .normal
            chars[i] = " "
            slotOut[i] = "\u{0}" + TextReflow.fractionPart(top) + "/" + TextReflow.fractionPart(bottom)
        }
        // A decimal point inside an exponent (`e^(0.2t)`) belongs to it: a
        // speck between two script glyphs, raised off the baseline with them.
        for i in chars.indices.dropFirst().dropLast() where chars[i] == "." && kinds[i] == .normal
            && kinds[i - 1] != .normal && kinds[i + 1] == kinds[i - 1]
            && line.glyphs[slotGlyph[i]].box.maxY < line.baseline - 0.25 * line.capHeight {
            kinds[i] = kinds[i - 1]
        }
        var i = 0
        while i < chars.count {
            if dropped.contains(i) { i += 1; continue }
            let space = spacesOut.contains(i) && i > 0 && kinds[i] == .normal ? " " : ""
            guard kinds[i] != .normal else {
                slotOut[i] = slotOut[i].hasPrefix("\u{0}") ? space + slotOut[i].dropFirst() : space + String(chars[i])
                i += 1
                continue
            }
            var end = i
            while end + 1 < chars.count, kinds[end + 1] == kinds[i] { end += 1 }
            let run = script(String(chars[i...end]), superscript: kinds[i] == .sup)
            if run.count == end - i + 1 {
                for (j, c) in zip(i...end, run) { slotOut[j] = String(c) }
            } else {
                slotOut[i] = run
            }
            i = end + 1
        }
        var out = [String](repeating: "", count: group.count)
        for (slot, k) in slotOf.enumerated() { out[k] += slotOut[slot] }
        let keepsRadical = group.contains { line.glyphs[$0].container }
        return out.joined() == String(original) && !keepsRadical ? nil : out
    }

    /// Which of `read`'s characters each glyph of `group` accounts for, as
    /// ranges into `read` — the cheapest assignment by dynamic programming.
    /// A full-size glyph normally takes one character, two or three when it is
    /// as wide as that many (touching italics), none when Vision dropped it (a
    /// full stop); a script glyph one; a stacked fraction any number. Shapes
    /// must agree (a bar is `=`/`−`, a speck `.`/`,`), and Vision's spaces must
    /// fall on real gaps. Nil when no assignment is cheap enough.
    private static let vulgarFractions: Set<Character> = ["½", "¼", "¾", "⅓", "⅔", "⅕", "⅛", "⅜", "⅝", "⅞"]

    static func alignment(_ group: [Int], _ read: [Character], spaces: Set<Int>, _ line: Line,
                          kinds: [Glyph.Kind]? = nil) -> [Range<Int>]? {
        let glyphs = group.map { line.glyphs[$0] }
        let kinds = kinds ?? glyphs.map(\.kind)
        let n = glyphs.count, m = read.count
        guard n > 0 else { return nil }
        let cap = line.capHeight
        let widths = zip(glyphs, kinds).filter { $0.1 == .normal && !$0.0.isStructure && $0.0.box.height >= 0.5 * cap }
            .map(\.0.box.width).sorted()
        let charWidth = widths.isEmpty ? 0.6 * cap : widths[widths.count / 2]
        let gaps = glyphs.indices.dropFirst().map { glyphs[$0].box.minX - glyphs[$0 - 1].box.maxX }
        let sortedGaps = gaps.sorted()
        // A third of the way up, not the median: a spaced equation (`v² = u² + 2as`)
        // has as many gaps between words as between letters.
        let letterGap: CGFloat? = sortedGaps.count >= 8 ? sortedGaps[sortedGaps.count / 3] : nil

        func shapeCost(_ g: Glyph, _ c: Character) -> Double {
            let h = g.box.height, w = g.box.width
            let bar = "=-−–—_~".contains(c), speck = ".,·'`’‘•∙°".contains(c)
            if h < 0.45 * cap && w > 1.5 * h { return bar ? 0 : 1.0 }
            if h < 0.4 * cap && w < 0.5 * cap { return speck ? 0 : 0.4 }
            if bar { return 1.0 }
            if speck { return 0.8 }
            // A colon is a narrow stack of dots; a wide letter isn't narrow.
            if ":;".contains(c) { return w < 0.3 * cap ? 0 : 0.8 }
            if w < 0.25 * cap && "mwMWOQDGHN0%@".contains(c) { return 0.8 }
            // Height class: `h` on an x-height glyph, or `e` on a tall one, is
            // the characters sitting on the wrong glyphs. (Digits vary: old-style
            // figures are x-height.)
            var total = 0.0
            let tall = h >= 0.85 * cap, short = h < 0.8 * cap
            if c.isLetter, c.isASCII, line.hasXHeight {
                if (c.isUppercase || "bdfhklt".contains(c)) && short { total += 0.5 }
                if "acemnorsuvwxz".contains(c) && tall && g.box.minY > line.baseline - 1.1 * cap { total += 0.5 }
                let descends = g.box.maxY > line.baseline + 0.15 * cap
                if "gjpqy".contains(c) != descends && !"fQJ".contains(c) { total += 0.3 }
            }
            return total
        }
        func mergeable(_ c: Character) -> Bool { c.isLetter || c.isNumber || "()[]".contains(c) }
        func partOfVulgarFraction(_ j: Int) -> Bool { j > 0 && vulgarFractions.contains(read[j - 1]) }
        /// Cost of glyph `k` taking `read[j..<j+count]`, or nil if it can't.
        func cost(_ k: Int, _ j: Int, _ count: Int) -> Double? {
            let g = glyphs[k], chars = read[j..<(j + count)]
            var total: Double
            if g.fraction != nil {
                total = count == 0 ? 0.5 : 0.15 * Double(count)
            } else if g.container {
                guard count <= 1 else { return nil }
                total = count == 0 ? 0.3 : "Vv√/\\|".contains(chars.first!) ? 0 : 0.6
            } else if kinds[k] != .normal {
                switch count {
                // The low `2` of a `½` passes for a subscript.
                case 0: total = partOfVulgarFraction(j) ? 0.2 : 0.6
                case 1: total = isScriptable(chars.first!) ? 0 : 0.3
                case 2: total = 1.2
                default: return nil
                }
            } else {
                let r = Double(g.box.width / max(charWidth, 1))
                switch count {
                // Vision skips specks and lone strokes (`|`, a prime) most.
                // …and a `½` is two or three pieces of ink for one character.
                case 0: total = partOfVulgarFraction(j) ? 0.2
                    : shapeCost(g, ".") == 0 || shapeCharacter(group[k], line) != nil ? 0.4 : 1.5
                case 1:
                    let c = chars.first!
                    let wide = "mwMW%@—=…".contains(c) || shapeCost(g, c) == 0 && "=-−–—_~".contains(c)
                    total = shapeCost(g, c) + max(0, r - (wide ? 2.6 : 1.8)) * 0.8
                default:
                    guard count <= 3, chars.allSatisfy(mergeable) else { return nil }
                    total = 0.5 * Double(count - 1) + max(0, Double(count) - 0.5 - r) + max(0, r - Double(count) - 1) * 0.5
                }
            }
            // Vision's spaces must fall on word gaps: one inside a word means
            // the characters after it sit on the wrong glyphs.
            if count > 0, k > 0, spaces.contains(j), let letterGap, gaps[k - 1] < letterGap + 0.1 * cap { total += 0.7 }
            // A script hangs on its base: no space between them.
            if count > 0, kinds[k] != .normal, spaces.contains(j) { total += 1.5 }
            if g.fraction == nil, count > 1, (j + 1..<(j + count)).contains(where: spaces.contains) { total += 2 }
            return total
        }

        let inf = Double.infinity
        var dp = [[Double]](repeating: [Double](repeating: inf, count: m + 1), count: n + 1)
        var back = [[Int]](repeating: [Int](repeating: -1, count: m + 1), count: n + 1) // chars taken; -2 = skipped
        dp[0][0] = 0
        for k in 0...n {
            for j in 0...m where dp[k][j] < inf {
                // Punctuation Vision made up from noise.
                if j < m, ".,'`’‘·".contains(read[j]), dp[k][j] + 1.0 < dp[k][j + 1] {
                    dp[k][j + 1] = dp[k][j] + 1.0
                    back[k][j + 1] = -2
                }
                guard k < n else { continue }
                let most = glyphs[k].fraction != nil ? min(12, m - j) : min(3, m - j)
                for count in 0...most {
                    guard let c = cost(k, j, count), dp[k][j] + c < dp[k + 1][j + count] else { continue }
                    dp[k + 1][j + count] = dp[k][j] + c
                    back[k + 1][j + count] = count
                }
            }
        }
        guard dp[n][m] <= 0.3 * Double(n) + 1.0 else { return nil }
        var spans = [Range<Int>](repeating: 0..<0, count: n)
        var k = n, j = m
        while k > 0 || j > 0 {
            let taken = back[k][j]
            if taken == -2 { j -= 1; continue }
            guard taken >= 0 else { return nil }
            spans[k - 1] = (j - taken)..<j
            j -= taken
            k -= 1
        }
        return spans
    }

    /// Reads a few blobs on their own (a fraction's numerator or denominator),
    /// scaled up to text size. Vision won't read a lone glyph, so the image
    /// starts with a typeset `a = ` for context, stripped from the result.
    private static func rereadBlobs(_ members: [Int], _ line: Line, _ reread: (CGImage) -> String?) -> String? {
        readInk(members.map { line.blobs[$0] }, width: line.map.width, capHeight: line.capHeight, reread)
    }

    /// Reads loose ink (pixel indices into a map `width` wide) the same way:
    /// scaled to text size behind a typeset `a = `. Given the `baseline` of the
    /// text it came from (and that text's cap height), it keeps its size and
    /// place instead, so an `x` isn't blown up into an `X`.
    static func readInk(_ blobs: [InkMap.Blob], width mapWidth: Int, capHeight: CGFloat, baseline: CGFloat? = nil,
                        _ reread: (CGImage) -> String?) -> String? {
        guard let first = blobs.first else { return nil }
        let box = blobs.dropFirst().reduce(first.box) { $0.union($1.box) }
        let base = baseline ?? box.maxY
        let scale = baseline == nil ? max(1, min(3, capHeight / max(box.height, 1))) : max(1, min(3, 30 / max(capHeight, 1)))
        let cap = baseline == nil ? capHeight : capHeight * scale
        let margin = max(16, Int(cap))
        let font = CTFontCreateWithName("Helvetica" as CFString, cap / 0.72, nil)
        let prefix = CTLineCreateWithAttributedString(NSAttributedString(
            string: "a = ", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        let prefixWidth = CTLineGetTypographicBounds(prefix, nil, nil, nil)
        let below = max(0, box.maxY - base) * scale
        let above = baseline == nil ? box.height * scale : max(cap, (base - box.minY) * scale)
        let width = Int((box.width * scale + prefixWidth).rounded(.up)) + 2 * margin
        let height = Int((above + below).rounded(.up)) + 2 * margin
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(gray: 0, alpha: 1)
        // Sit the prefix on the part's baseline (its bottom edge by default).
        let baseY = CGFloat(margin) + below
        ctx.textPosition = CGPoint(x: CGFloat(margin), y: baseY)
        CTLineDraw(prefix, ctx)
        let left = CGFloat(margin) + prefixWidth
        for blob in blobs {
            for p in blob.pixels {
                let x = (CGFloat(p % mapWidth) - box.minX) * scale + left
                let y = baseY + (base - CGFloat(p / mapWidth) - 1) * scale
                ctx.fill(CGRect(x: x, y: y, width: scale, height: scale))
            }
        }
        guard let text = ctx.makeImage().flatMap(reread), let equals = text.firstIndex(of: "=") else { return nil }
        let value = text[text.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// A rewrite may only add scripts and known symbol repairs: every full-size
    /// glyph must still read as Vision read it (case, `0`/`O` and `+`/`±`/`‡`/`≠`
    /// aside), and a script digit inside a number is never followed by a
    /// full-size digit (`5,¹40` is Georgia's old-style `1`, not an exponent;
    /// `log₂8` hangs off a letter and is fine). Anything else —
    /// a `%` taken apart into `⁰/o`, a whole line re-read into `/1_Of` — is
    /// worse than Vision's own read, which is then kept.
    static func isFaithful(_ chars: [Character], kinds: [Glyph.Kind], structure: [Bool], to read: [Character],
                           confident: Bool = true) -> Bool {
        for i in chars.indices.dropLast() where kinds[i] != .normal && chars[i].isNumber
            && kinds[i + 1] == .normal && !structure[i + 1] && chars[i + 1].isNumber {
            var start = i
            while start > 0, kinds[start - 1] == kinds[i] { start -= 1 }
            if start == 0 || !chars[start - 1].isLetter { return false }
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
