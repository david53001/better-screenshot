import CoreGraphics
import CoreText
import Foundation

/// Display equations rebuilt from their pixels. Vision boxes a displayed
/// formula in pieces that don't follow its structure: `lim` in one box, the
/// limit `x→0` merged with a denominator in another, a numerator glued to the
/// `tan θ =` beside it. Here the ink of such a cluster is laid out again:
///
/// - The equation's axis is the middle of its `=` (or of its fraction bar).
///   Ink crossing the axis is the main row, cut into atoms left to right;
///   ink above or below it hangs on the atom it sits over.
/// - An atom that is a bar with ink above and below is a fraction; a tall
///   `∫` or `∑` (told by shape) is an operator with its limits; a word with
///   wide ink under it that reads `lim` (or max, min) takes that as its limit.
/// - Everything else is text: runs of atoms re-read by Vision on their own,
///   with their scripts recovered.
///
/// Output is linear Unicode math: `(sin θ)/(cos θ)`, `∑ᵢ₌₁ⁿ`, `∫₀¹`,
/// `lim_(x→0)`. When there's no such structure, or a piece can't be read, the
/// lines are left as they were.
enum DisplayMath {
    indirect enum Node {
        case text(String)
        case fraction(Node, Node)
        case op(String, lower: Node?, upper: Node?)
        case row([Node])

        var linear: String {
            switch self {
            case .text(let s): return tidied(s)
            case .fraction(let n, let d):
                return TextReflow.fractionPart(n.linear) + "/" + TextReflow.fractionPart(d.linear)
            case .op(let symbol, let lower, let upper):
                // `x→o` is `x→0`, `n→oo` is `n→∞`.
                let limit = lower.map { compact($0.linear).replacingOccurrences(of: "→oo", with: "→∞")
                    .replacingOccurrences(of: "→o", with: "→0").replacingOccurrences(of: "→O", with: "→0") }
                let sub = limit.map { ScriptRecovery.script($0, superscript: false) } ?? ""
                let sup = upper.map { ScriptRecovery.script(compact($0.linear), superscript: true) } ?? ""
                return symbol + sub + sup
            case .row(let nodes): return nodes.map(\.linear).joined(separator: " ")
            }
        }

        var hasStructure: Bool {
            switch self {
            case .text: return false
            case .fraction, .op: return true
            case .row(let nodes): return nodes.contains(where: \.hasStructure)
            }
        }
    }

    /// Replaces the lines of each displayed equation Vision boxed in pieces
    /// with one line holding its linear form.
    static func rebuilding(_ lines: [TextReflow.Line], in image: CGImage,
                           reread: (CGImage) -> String?) -> [TextReflow.Line] {
        let size = CGSize(width: image.width, height: image.height)
        func pixels(_ b: CGRect) -> CGRect {
            CGRect(x: b.minX * size.width, y: b.minY * size.height, width: b.width * size.width, height: b.height * size.height)
        }
        let boxes = lines.map { pixels($0.box) }
        // Clusters: short math lines close to one another.
        var parent = Array(lines.indices)
        func root(_ i: Int) -> Int { var i = i; while parent[i] != i { i = parent[i] }; return i }
        let mathy = lines.map { isMathy($0.recovered ?? $0.text) }
        for i in lines.indices where mathy[i] {
            for j in lines.indices where j > i && mathy[j] {
                let a = boxes[i], b = boxes[j], h = max(a.height, b.height)
                let dy = max(a.minY, b.minY) - min(a.maxY, b.maxY), dx = max(a.minX, b.minX) - min(a.maxX, b.maxX)
                if dy < 1.3 * h, dx < 1.0 * h { parent[root(j)] = root(i) }
            }
        }
        var clusters: [Int: [Int]] = [:]
        for i in lines.indices where mathy[i] { clusters[root(i), default: []].append(i) }
        var out = lines
        var removed = Set<Int>()
        for members in clusters.values.sorted(by: { $0[0] < $1[0] }) where members.count >= 2 {
            let region = members.dropFirst().reduce(boxes[members[0]]) { $0.union(boxes[$1]) }
            let others = lines.indices.filter { !members.contains($0) }.map { boxes[$0] }
            for (rowBox, text) in rebuild(region, in: image, lines: members.map { boxes[$0] }, excluding: others,
                                          reread: reread) {
                // The lines of this equation: their middles lie in its row.
                let inRow = members.filter { rowBox.contains(CGPoint(x: boxes[$0].midX, y: boxes[$0].midY)) }
                guard inRow.count >= 2, let first = inRow.min() else { continue }
                out[first] = TextReflow.Line(text: text, box: inRow.dropFirst().reduce(lines[first].box) { $0.union(lines[$1].box) },
                                             recovered: text)
                removed.formUnion(inRow.filter { $0 != first })
            }
        }
        return out.indices.filter { !removed.contains($0) }.map { out[$0] }
    }

    /// Math, not prose: at most one ordinary word of four or more letters.
    static func isMathy(_ text: String) -> Bool {
        let functions: Set<String> = ["lim", "sin", "cos", "tan", "log", "exp", "max", "min", "det", "arcsin", "arccos", "arctan"]
        let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
            .filter { $0.count >= 4 && !functions.contains($0.lowercased()) }
        return words.count <= 1 && text.count <= 60
    }

    // MARK: - Layout

    /// Each equation row inked in `rect` that has two-dimensional structure:
    /// its box (image pixels) and linear form.
    /// `lines`: Vision's boxes for this region (pixels). A plain stacked
    /// fraction Vision boxed part by part is `MathLayout`'s; this steps in for
    /// operators, limits, and a numerator Vision boxed with what's beside it.
    static func rebuild(_ rect: CGRect, in image: CGImage, lines: [CGRect] = [], excluding others: [CGRect] = [],
                        reread: (CGImage) -> String?) -> [(CGRect, String)] {
        // Vision often leaves a big operator out of every box: look a line
        // height to either side.
        let height = lines.map(\.height).sorted().dropFirst(lines.count / 2).first ?? rect.height
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var crop = rect.insetBy(dx: -2 * height, dy: -height).integral.intersection(bounds)
        var map: InkMap?
        // A big operator can run past the padding: grow the crop until no
        // sizeable ink touches its edge.
        for _ in 0..<3 {
            guard let m = InkMap(image, rect: crop) else { return [] }
            map = m
            let cut = m.blobs().filter { b in
                b.box.height >= 0.5 * height
                    && (b.box.minX <= 0 || b.box.minY <= 0 || b.box.maxX >= CGFloat(m.width) - 1 || b.box.maxY >= CGFloat(m.height) - 1)
            }
            guard !cut.isEmpty else { break }
            let grown = crop.insetBy(dx: -height, dy: -height).integral.intersection(bounds)
            if grown == crop { break }
            crop = grown
        }
        guard let map else { return [] }
        let foreign = others.map { $0.offsetBy(dx: -crop.minX, dy: -crop.minY) }
        let blobs = map.blobs().filter { blob in
            blob.pixels.count >= 3 && !foreign.contains { $0.contains(CGPoint(x: blob.box.midX, y: blob.box.midY)) }
                // Ink cut by the crop's edge belongs to something else.
                && blob.box.minX > 0 && blob.box.minY > 0
                && blob.box.maxX < CGFloat(map.width) - 1 && blob.box.maxY < CGFloat(map.height) - 1
        }
        guard blobs.count >= 3 else { return [] }
        return withoutActuallyEscaping(reread) { reread -> [(CGRect, String)] in
            let layout = Layout(blobs: blobs, map: map, reread: reread,
                                lines: lines.map { $0.offsetBy(dx: -crop.minX, dy: -crop.minY) })
            return layout.rows().compactMap { row in
                layout.needed = false
                let parsedNode = layout.parse(row)
                guard let node = parsedNode, node.hasStructure, layout.needed else { return nil }
                let text = node.linear
                let box = layout.box(row).offsetBy(dx: crop.minX, dy: crop.minY).insetBy(dx: 0, dy: -0.2 * layout.unit)
                return text.isEmpty ? nil : (box, text)
            }
        }
    }

    private final class Layout {
        let blobs: [InkMap.Blob]
        let map: InkMap
        let reread: (CGImage) -> String?
        let lines: [CGRect]
        /// A typical glyph's height: the unit of every threshold.
        let unit: CGFloat
        /// A capital's height, for the typeset prefix Vision compares case against.
        let cap: CGFloat
        /// Set when the row has something only this can rebuild.
        var needed = false

        init(blobs: [InkMap.Blob], map: InkMap, reread: @escaping (CGImage) -> String?, lines: [CGRect]) {
            self.blobs = blobs
            self.map = map
            self.reread = reread
            self.lines = lines
            let all = blobs.map(\.box.height).sorted()
            let median = all[all.count / 2]
            let glyphs = blobs.filter { $0.box.width < 3 * $0.box.height && $0.box.height >= 0.5 * median }
                .map(\.box.height).sorted()
            let typical = glyphs.isEmpty ? median : glyphs[glyphs.count / 2]
            unit = typical
            let capped = glyphs.filter { $0 <= 1.4 * typical }
            cap = capped.max() ?? typical
        }

        func box(_ members: [Int]) -> CGRect {
            members.dropFirst().reduce(blobs[members[0]].box) { $0.union(blobs[$1].box) }
        }

        func isBar(_ m: Int) -> Bool {
            let b = blobs[m].box
            return b.width >= 3 * b.height && b.height <= max(3, 0.2 * unit)
        }

        /// Per pixel row of the blob: its leftmost and rightmost ink, relative to its box.
        private func profile(_ m: Int) -> [(Int, Int)] {
            let b = blobs[m].box, w = Int(b.width), h = Int(b.height)
            var rows = [(Int, Int)](repeating: (w, -1), count: h)
            for p in blobs[m].pixels {
                let x = p % map.width - Int(b.minX), y = p / map.width - Int(b.minY)
                guard y >= 0, y < h else { continue }
                rows[y] = (min(rows[y].0, x), max(rows[y].1, x))
            }
            return rows
        }

        /// `∫`, `∑`, or nil: a glyph far taller than the text, told by shape.
        /// An integral's ends lie on opposite sides (a parenthesis's on the same
        /// side); a sum has a full bar at its top and its bottom and its point
        /// in the middle (a bracket's spine is at its edge).
        func operatorSymbol(_ m: Int) -> String? {
            let b = blobs[m].box
            guard b.height >= 1.6 * unit, !isBar(m), b.height >= 12 else { return nil }
            let rows = profile(m), h = rows.count, w = Int(b.width)
            let edge = max(2, h / 8)
            func centre(_ r: ArraySlice<(Int, Int)>) -> Double {
                let xs = r.filter { $0.1 >= 0 }.map { Double($0.0 + $0.1) / 2 }
                return xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
            }
            if b.width <= 0.6 * b.height {
                let top = centre(rows[..<edge]), bottom = centre(rows[(h - edge)...])
                return top - bottom > 0.25 * Double(w) ? "∫" : nil
            }
            func coverage(_ r: ArraySlice<(Int, Int)>) -> Double {
                Double(r.map { $0.1 >= 0 ? $0.1 - $0.0 + 1 : 0 }.max() ?? 0) / Double(w)
            }
            let middle = rows[(h / 2 - edge / 2)...(h / 2 + edge / 2)]
            if coverage(rows[..<edge]) >= 0.6, coverage(rows[(h - edge)...]) >= 0.6,
               centre(middle) >= 0.3 * Double(w), coverage(middle) < 0.6 {
                return "∑"
            }
            return nil
        }

        /// A tall bracket (`[`, `(`, `]`, `)`) from its outline: narrow, taller
        /// than the text, its spine at one side and its ends reaching the other.
        func bracket(_ m: Int) -> (opening: Bool, square: Bool)? {
            let b = blobs[m].box
            // (Taller than ordinary parentheses, which run about 1.3 capitals.)
            guard b.height >= 2 * unit, b.height >= 1.5 * cap, b.width <= 0.45 * b.height, b.width >= 2,
                  operatorSymbol(m) == nil else { return nil }
            let rows = profile(m), h = rows.count, w = Double(max(Int(b.width), 1))
            let middle = rows[(h * 2 / 5)...(h * 3 / 5)].filter { $0.1 >= 0 }
            // Each end: its widest row (a bracket's serif, a parenthesis's tip).
            let ends = [rows.prefix(max(2, h / 8)), rows.suffix(max(2, h / 8))]
                .compactMap { $0.filter { $0.1 >= 0 }.max { $0.1 - $0.0 < $1.1 - $1.0 } }
            guard !middle.isEmpty, ends.count == 2 else { return nil }
            let midCentre = middle.map { Double($0.0 + $0.1) / 2 }.reduce(0, +) / Double(middle.count) / w
            let endCentre = ends.map { Double($0.0 + $0.1) / 2 }.reduce(0, +) / 2 / w
            guard abs(midCentre - endCentre) > 0.15 else { return nil }
            let square = Double(rows.prefix(max(2, h / 12)).map { $0.1 - $0.0 + 1 }.max() ?? 0) >= 0.7 * w
            return (midCentre < endCentre, square)
        }

        /// Top-to-bottom bands of ink separated by empty rows.
        func bands(_ members: [Int]) -> [[Int]] {
            let sorted = members.sorted { blobs[$0].box.minY < blobs[$1].box.minY }
            var out: [[Int]] = []
            var bottom = -CGFloat.infinity
            for m in sorted {
                if out.isEmpty || blobs[m].box.minY > bottom + 0.1 * unit { out.append([m]) } else { out[out.count - 1].append(m) }
                bottom = max(bottom, blobs[m].box.maxY)
            }
            return out
        }

        /// `[1 2; 3 4]`: the ink between two tall brackets in rows (split by
        /// empty stretches) and cells (split by gaps wider than a letter).
        func matrix(open: Int, close: Int, inside: [Int], script: Bool) -> Node? {
            let kind = bracket(open)!
            let rows = bands(inside)
            guard rows.count >= 2 else {
                // One row: a big bracketed expression.
                guard let body = parse(inside, script: script) else { return nil }
                return .row([.text(kind.square ? "[" : "("), body, .text(kind.square ? "]" : ")")])
            }
            var lines: [String] = []
            for row in rows {
                let sorted = row.sorted { blobs[$0].box.minX < blobs[$1].box.minX }
                var cells: [[Int]] = []
                var right = -CGFloat.infinity
                for m in sorted {
                    if !cells.isEmpty, blobs[m].box.minX - right < 0.6 * unit { cells[cells.count - 1].append(m) } else { cells.append([m]) }
                    right = max(right, blobs[m].box.maxX)
                }
                var texts: [String] = []
                for cell in cells {
                    guard let text = read(cell, script: script) else { return nil }
                    texts.append(text)
                }
                lines.append(texts.joined(separator: " "))
            }
            return .text((kind.square ? "[" : "(") + lines.joined(separator: "; ") + (kind.square ? "]" : ")"))
        }

        /// The equation rows: bands of ink split by empty stretches wider than
        /// the gaps around a fraction bar.
        func rows() -> [[Int]] {
            let sorted = blobs.indices.sorted { blobs[$0].box.minY < blobs[$1].box.minY }
            var bands: [[Int]] = []
            var bottom = -CGFloat.infinity
            for m in sorted {
                if bands.isEmpty || blobs[m].box.minY > bottom + 0.45 * unit { bands.append([m]) } else { bands[bands.count - 1].append(m) }
                bottom = max(bottom, blobs[m].box.maxY)
            }
            // Two equations close together: one row per full-size `=`.
            return bands.flatMap { band -> [[Int]] in
                let axes = equalsAxes(band)
                guard axes.count >= 2 else { return [band] }
                var parts = [[Int]](repeating: [], count: axes.count)
                for m in band {
                    let y = blobs[m].box.midY
                    parts[axes.indices.min { abs(axes[$0] - y) < abs(axes[$1] - y) }!].append(m)
                }
                return parts.filter { !$0.isEmpty }
            }
        }

        /// One of the two bars of an `=`.
        func isEqualsBar(_ m: Int, in members: [Int]) -> Bool {
            let p = blobs[m].box
            return members.contains { n in
                guard n != m, isBar(n) else { return false }
                let q = blobs[n].box
                return abs(q.midY - p.midY) < 0.6 * unit && abs(q.midY - p.midY) > 0 && abs(p.width - q.width) < 0.3 * max(p.width, q.width)
                    && min(p.maxX, q.maxX) - max(p.minX, q.minX) > 0.7 * min(p.width, q.width)
            }
        }

        /// The middles of the full-size `=` signs, top to bottom, one per height.
        func equalsAxes(_ members: [Int]) -> [CGFloat] {
            let bars = members.filter(isBar)
            var found: [(y: CGFloat, width: CGFloat)] = []
            for a in bars {
                for b in bars where b != a {
                    let p = blobs[a].box, q = blobs[b].box
                    if q.minY > p.maxY, q.minY - p.maxY < 0.6 * unit, abs(p.width - q.width) < 0.3 * max(p.width, q.width),
                       min(p.maxX, q.maxX) - max(p.minX, q.minX) > 0.7 * min(p.width, q.width) {
                        found.append(((p.midY + q.midY) / 2, p.width))
                    }
                }
            }
            let widest = found.map(\.width).max() ?? 0
            var axes: [CGFloat] = []
            for f in found.filter({ $0.width >= 0.75 * widest }).sorted(by: { $0.y < $1.y })
                where axes.last.map({ f.y - $0 > 1.2 * unit }) ?? true {
                axes.append(f.y)
            }
            return axes
        }

        /// The equation's axis: the middle of an `=`, else of a bar with ink
        /// above and below, else of the glyphs.
        func axis(_ members: [Int]) -> CGFloat {
            let bars = members.filter(isBar)
            for a in bars {
                for b in bars where b != a {
                    let p = blobs[a].box, q = blobs[b].box
                    if q.minY > p.maxY, q.minY - p.maxY < 0.6 * unit, abs(p.width - q.width) < 0.3 * max(p.width, q.width),
                       min(p.maxX, q.maxX) - max(p.minX, q.minX) > 0.7 * min(p.width, q.width) {
                        return (p.midY + q.midY) / 2
                    }
                }
            }
            for a in bars {
                let p = blobs[a].box
                let over = members.contains { blobs[$0].box.maxY < p.minY && blobs[$0].box.midX > p.minX && blobs[$0].box.midX < p.maxX }
                let under = members.contains { blobs[$0].box.minY > p.maxY && blobs[$0].box.midX > p.minX && blobs[$0].box.midX < p.maxX }
                if over && under { return p.midY }
            }
            let mids = members.map { blobs[$0].box.midY }.sorted()
            return mids[mids.count / 2]
        }

        /// `script`: the ink is set small (an operator's limits).
        func parse(_ members: [Int], script: Bool = false) -> Node? {
            guard !members.isEmpty else { return nil }
            let y = axis(members)
            let band = 0.15 * unit
            // Tall brackets pair up around a matrix (or a big bracketed
            // expression); what's between them is read as its own.
            var enclosed: [Int: (close: Int, inside: [Int])] = [:]
            var hidden = Set<Int>()
            var open: [Int] = []
            for b in members.filter({ bracket($0) != nil }).sorted(by: { blobs[$0].box.minX < blobs[$1].box.minX }) {
                if bracket(b)!.opening { open.append(b); continue }
                guard let o = open.popLast() else { continue }
                let l = blobs[o].box, r = blobs[b].box
                let inside = members.filter { m in
                    let x = blobs[m].box
                    return m != o && m != b && x.minX >= l.maxX - 1 && x.maxX <= r.minX + 1
                        && x.midY > min(l.minY, r.minY) && x.midY < max(l.maxY, r.maxY)
                }
                guard open.isEmpty, !inside.isEmpty else { continue }
                enclosed[o] = (b, inside)
                hidden.formUnion(inside + [b])
            }
            // Atoms: main-row ink, overlapping pieces together.
            // (A fraction bar sits on the axis give or take a stroke.)
            let main = members.filter { !hidden.contains($0) && (blobs[$0].box.minY <= y + band && blobs[$0].box.maxY >= y - band
                                        || isBar($0) && abs(blobs[$0].box.midY - y) < 0.4 * unit) }
                .sorted { blobs[$0].box.minX < blobs[$1].box.minX }
            guard !main.isEmpty else { return nil }
            var atoms: [[Int]] = []
            var right = -CGFloat.infinity
            for m in main {
                if !atoms.isEmpty, blobs[m].box.minX < right { atoms[atoms.count - 1].append(m) } else { atoms.append([m]) }
                right = max(right, blobs[m].box.maxX)
            }
            // What hangs above or below the row goes with the atom it overlaps
            // most — except a big operator's limits, which may sit off to its
            // right (`∫₀¹`): small ink level with its top or bottom.
            var above = [[Int]](repeating: [], count: atoms.count), below = above
            var claimed = Set<Int>()
            for (k, atom) in atoms.enumerated() where atom.count == 1 && operatorSymbol(atom[0]) != nil {
                let o = blobs[atom[0]].box
                let next = k + 1 < atoms.count ? box(atoms[k + 1]).minX : .infinity
                for m in members where !main.contains(m) && !claimed.contains(m) && !hidden.contains(m) {
                    let b = blobs[m].box
                    guard b.minX >= o.minX - 0.3 * unit, b.minX < min(o.maxX + 0.8 * unit, next), b.height < unit else { continue }
                    if b.maxY < o.minY + 0.45 * o.height { above[k].append(m); claimed.insert(m) }
                    else if b.minY > o.maxY - 0.45 * o.height { below[k].append(m); claimed.insert(m) }
                }
            }
            for m in members where !main.contains(m) && !claimed.contains(m) && !hidden.contains(m) {
                let b = blobs[m].box
                let scores = atoms.map { atom -> CGFloat in
                    let a = box(atom)
                    return min(a.maxX, b.maxX) - max(a.minX, b.minX)
                }
                let best = scores.indices.max { scores[$0] < scores[$1] }!
                let k = scores[best] > 0 ? best
                    : atoms.indices.min { abs(box(atoms[$0]).midX - b.midX) < abs(box(atoms[$1]).midX - b.midX) }!
                if b.midY < y { above[k].append(m) } else { below[k].append(m) }
            }
            var nodes: [Node] = []
            var run: [Int] = []
            func flush() -> Bool {
                guard !run.isEmpty else { return true }
                guard let text = read(run, script: script) else { return false }
                nodes.append(.text(text))
                run = []
                return true
            }
            var k = 0
            while k < atoms.count {
                let atom = atoms[k]
                // A matrix: rows of cells between tall brackets.
                if atom.count == 1, let (close, inside) = enclosed[atom[0]] {
                    guard flush(), let node = matrix(open: atom[0], close: close, inside: inside, script: script) else { return nil }
                    nodes.append(.op(node.linear, lower: nil, upper: nil))
                    needed = true
                    run += above[k] + below[k]
                    k += 1
                    continue
                }
                // `=`: known from its shape; Vision reads a lone one as `-`.
                // (Mid-run it stays in the run: `i=1` reads better whole.)
                if run.isEmpty, atom.count == 2, atom.allSatisfy({ isEqualsBar($0, in: atom) }),
                   above[k].isEmpty, below[k].isEmpty {
                    nodes.append(.text("="))
                    k += 1
                    continue
                }
                // A fraction: a bar with a numerator over it and a denominator under it.
                if atom.count == 1, isBar(atom[0]), !above[k].isEmpty, !below[k].isEmpty,
                   !(above[k].count == 1 && isBar(above[k][0])), !(below[k].count == 1 && isBar(below[k][0])),
                   box(above[k]).height >= 0.4 * unit, box(below[k]).height >= 0.4 * unit {
                    guard flush(), let n = parse(above[k]), let d = parse(below[k]) else { return nil }
                    // Vision boxed the numerator together with the row beside it.
                    let num = box(above[k])
                    if lines.contains(where: { $0.minY <= num.midY && $0.maxY >= y && $0.minX < num.maxX && $0.maxX > num.minX
                                               && ($0.minX < box(atom).minX - 0.5 * unit || $0.maxX > box(atom).maxX + 0.5 * unit) }) {
                        needed = true
                    }
                    nodes.append(.fraction(n, d))
                    k += 1
                    continue
                }
                // A big operator and its limits.
                if atom.count == 1, let symbol = operatorSymbol(atom[0]) {
                    guard flush() else { return nil }
                    let upper = above[k].isEmpty ? nil : parse(above[k], script: true)
                    let lower = below[k].isEmpty ? nil : parse(below[k], script: true)
                    if !above[k].isEmpty && upper == nil || !below[k].isEmpty && lower == nil { return nil }
                    nodes.append(.op(symbol, lower: lower, upper: upper))
                    needed = true
                    k += 1
                    continue
                }
                // A word with its limit under it (`lim` over `x→0`): wide ink below
                // the row, under this atom and the next ones.
                func deepBelow(_ i: Int) -> [Int] { below[i].filter { blobs[$0].box.minY > y + 0.6 * unit } }
                var word = [k]
                while let last = word.last, last + 1 < atoms.count, !deepBelow(last + 1).isEmpty || !deepBelow(last).isEmpty,
                      box(atoms[last + 1]).minX - box(atoms[last]).maxX < 0.5 * unit,
                      operatorSymbol(atoms[last + 1][0]) == nil, !isBar(atoms[last + 1][0]) { word.append(last + 1) }
                let limit = word.flatMap(deepBelow)
                if !limit.isEmpty, box(limit).width >= 1.2 * unit {
                    let ink = word.flatMap { atoms[$0] + above[$0] }
                    let limitInk = word.flatMap { i in below[i].filter { blobs[$0].box.minY > y + 0.6 * unit } }
                    if let text = read(ink, script: script), ["lim", "max", "min", "sup", "inf"].contains(text.lowercased()),
                       let lower = parse(limitInk, script: true) {
                        guard flush() else { return nil }
                        nodes.append(.op(text.lowercased(), lower: lower, upper: nil))
                        needed = true
                        run += word.flatMap { i in below[i].filter { !limitInk.contains($0) } }
                        k = word.last! + 1
                        continue
                    }
                }
                run += atom + above[k] + below[k]
                k += 1
            }
            guard flush() else { return nil }
            return nodes.count == 1 ? nodes[0] : .row(nodes)
        }

        /// Reads a run of ink with Vision, scripts recovered from its pixels.
        /// A typeset `a = ` goes in front: Vision won't read a lone glyph.
        func read(_ members: [Int], script: Bool = false) -> String? {
            // Vision won't read a lone glyph, so a typeset `a = ` goes first — but
            // a run starting with its own `=` then reads `-`: read those alone.
            guard let value = read(members, prefixed: true, script: script) else { return nil }
            if members.count >= 3, value.first.map({ "-=−".contains($0) }) == true,
               let alone = read(members, prefixed: false, script: script) {
                return alone
            }
            return value
        }

        private func read(_ members: [Int], prefixed: Bool, script: Bool) -> String? {
            let b = box(members)
            let scale = max(1, min(4, 40 / max(unit, 1)))
            let margin = 24
            // The prefix set at the piece's type size: Vision reads case and
            // script size against it. Limits are set about 0.7 of the text.
            let font = CTFontCreateWithName("Helvetica" as CFString, (script ? 0.7 : 1) * cap * scale / 0.72, nil)
            let prefix = CTLineCreateWithAttributedString(NSAttributedString(
                string: prefixed ? "a = " : "", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            let prefixWidth = CTLineGetTypographicBounds(prefix, nil, nil, nil)
            let width = Int((b.width * scale + prefixWidth).rounded(.up)) + 2 * margin
            let height = Int((b.height * scale).rounded(.up)) + 2 * margin
            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(gray: 0, alpha: 1)
            // The prefix sits on the run's baseline: the bottom of its main glyphs.
            let bottoms = members.map { blobs[$0].box }.filter { $0.height >= 0.6 * unit }.map(\.maxY).sorted()
            let baseline = bottoms.isEmpty ? b.maxY : bottoms[bottoms.count / 2]
            ctx.textPosition = CGPoint(x: CGFloat(margin), y: CGFloat(margin) + (b.maxY - baseline) * scale)
            CTLineDraw(prefix, ctx)
            let left = CGFloat(margin) + prefixWidth
            for m in members {
                for p in blobs[m].pixels {
                    let x = (CGFloat(p % map.width) - b.minX) * scale + left
                    let y = (CGFloat(p / map.width) - b.minY) * scale + CGFloat(margin)
                    ctx.fill(CGRect(x: x, y: CGFloat(height) - y - scale, width: scale, height: scale))
                }
            }
            guard let rendered = ctx.makeImage(), let raw = reread(rendered) else {
                return nil
            }
            let lineRect = CGRect(x: CGFloat(margin), y: CGFloat(margin), width: CGFloat(width - 2 * margin),
                                  height: CGFloat(height - 2 * margin))
            let latin = Homoglyphs.latinized(raw, keepCyrillic: false, keepGreek: true)
            let text = ScriptRecovery.recover(latin, rect: lineRect, in: rendered, reread: reread) ?? latin
            var value = text
            if prefixed {
                guard let equals = text.firstIndex(of: "=") else { return nil }
                value = text[text.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            }
            // Out of context Vision guesses a capital for `x`, `o`, `s`…: the
            // piece's own glyphs say they are x-height.
            let tallest = members.map { blobs[$0].box.height }.max() ?? 0
            if tallest < (script ? 0.56 : 0.8) * cap, value.allSatisfy({ !$0.isLetter || "CKOPSUVWXZcopsuvwxz".contains($0) }) {
                value = value.lowercased()
            }
            return value.isEmpty ? nil : value
        }
    }

    /// `sinx` → `sin x`: a function name and its argument (Vision drops the space).
    static func tidied(_ s: String) -> String {
        functionArgument.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1 ")
    }

    private static let functionArgument = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])(sin|cos|tan|sec|csc|cot|log|ln|exp)(?=[a-zθ](?![A-Za-z]))"#)

    /// `i = 1` → `i=1` for a script run.
    private static func compact(_ s: String) -> String { s.replacingOccurrences(of: " ", with: "") }
}
