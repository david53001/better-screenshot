import CoreGraphics
import Foundation

/// Two-dimensional math that Vision returns as separate lines: stacked
/// fractions (`a + b` over a bar over `2`, with `m =` beside them) and
/// exponents Vision boxed on their own (`ⁿᵗ` after `(1 + r/n)`). Rebuilt into
/// one line of linear math: `m = (a + b)/2`.
extension TextReflow {
    /// `ruleLength` returns the longest horizontal run of ink in a region
    /// (pixels, top-left origin). A bar about as wide as the fraction is what
    /// tells a fraction from two stacked lines or a matrix; a table border runs
    /// far past its cells.
    static func stackingFractions(_ segs: [Seg], ruleLength: (CGRect) -> CGFloat) -> [Seg] {
        var segs = segs
        var found = true
        while found {
            found = false
            search: for n in segs.indices {
                for d in segs.indices where d != n {
                    let top = segs[n].box, bottom = segs[d].box
                    let h = max(top.height, bottom.height)
                    let gap = bottom.minY - top.maxY
                    guard bottom.minY > top.midY, gap <= 1.3 * h, gap >= -0.3 * h,
                          abs(top.midX - bottom.midX) <= 0.2 * max(top.width, bottom.width) else { continue }
                    let left = min(top.minX, bottom.minX), width = max(top.maxX, bottom.maxX) - left
                    let bar = CGRect(x: left - 0.5 * width, y: min(top.maxY, bottom.minY) - 0.15 * h,
                                     width: 2 * width, height: abs(gap) + 0.3 * h)
                    let run = ruleLength(bar)
                    guard run >= 0.7 * width, run <= 1.4 * width + h,
                          let merged = replacingFraction(numerator: n, denominator: d, barY: bar.midY, in: segs)
                    else { continue }
                    segs = merged
                    found = true
                    break search
                }
            }
        }
        return segs
    }

    /// Nil when nothing sits on the bar's line — a bare pair of lines with a
    /// rule between them is more likely a heading and a table than math.
    private static func replacingFraction(numerator n: Int, denominator d: Int, barY: CGFloat, in segs: [Seg]) -> [Seg]? {
        let num = segs[n], den = segs[d]
        let text = fractionPart(num.shown) + "/" + fractionPart(den.shown)
        var fraction = Seg(text: text, shown: text, raw: nil, box: num.box.union(den.box), order: min(num.order, den.order))
        var drop: Set<Int> = [n, d]
        // What sits on the fraction bar's line to the left (`m =`) and right (`= 1`).
        let beside = segs.indices.filter { !drop.contains($0) && segs[$0].box.minY < barY && segs[$0].box.maxY > barY }
        if let l = beside.filter({ segs[$0].box.maxX <= fraction.box.minX + 0.3 * segs[$0].box.height
                                   && fraction.box.minX - segs[$0].box.maxX <= 1.5 * segs[$0].box.height })
            .max(by: { segs[$0].box.maxX < segs[$1].box.maxX }) {
            fraction.text = segs[l].text + " " + fraction.text
            fraction.shown = segs[l].shown + " " + fraction.shown
            fraction.box = fraction.box.union(segs[l].box)
            fraction.order = min(fraction.order, segs[l].order)
            drop.insert(l)
        }
        if let r = beside.filter({ !drop.contains($0) && segs[$0].box.maxX > fraction.box.maxX
                                   && segs[$0].box.minX >= num.box.minX && segs[$0].box.minX >= den.box.minX
                                   && segs[$0].box.minX - fraction.box.maxX <= 1.5 * segs[$0].box.height })
            .min(by: { segs[$0].box.minX < segs[$1].box.minX }) {
            var text = segs[r].shown
            // Vision sometimes reads the bar itself as a leading minus (`-= 3x`).
            if segs[r].box.minX < fraction.box.maxX - 0.2 * segs[r].box.height,
               let first = text.first, "-−–—_".contains(first) {
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            fraction.text += " " + text
            fraction.shown += " " + text
            fraction.box = fraction.box.union(segs[r].box)
            fraction.order = min(fraction.order, segs[r].order)
            drop.insert(r)
        }
        guard drop.count > 2 else { return nil }
        return (segs.indices.filter { !drop.contains($0) }.map { segs[$0] } + [fraction]).sorted { $0.order < $1.order }
    }

    /// `a + b` → `(a + b)`; `2a`, `dy`, `n(n + 1)` stay bare.
    static func fractionPart(_ raw: String) -> String {
        // `xln2` is `x ln 2`: a log glued between a one-letter factor and its argument.
        let text = gluedLog.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: " $1 ")
        var depth = 0
        for c in text {
            if "([{".contains(c) { depth += 1 } else if ")]}".contains(c) { depth -= 1 }
            else if depth == 0, c == " " || "+-−±×·÷/=<>".contains(c) { return "(" + text + ")" }
        }
        return text
    }

    private static let gluedLog = try! NSRegularExpression(pattern: #"(?<=\b[a-z])(ln|log)(?=\d|[a-z]\b)"#)

    /// A short box sitting raised (or lowered) right after another line is its
    /// exponent (or index) that Vision boxed on its own.
    static func attachingDetachedScripts(_ segs: [Seg]) -> [Seg] {
        var segs = segs
        var i = 0
        while i < segs.count {
            let s = segs[i]
            guard s.words == 1, s.text.count <= 4,
                  let a = segs.indices.first(where: { j in
                      let base = segs[j].box
                      // Only a symbol, digit or bracket carries an exponent (not `=`).
                      guard j != i, let end = segs[j].text.last, end.isLetter || end.isNumber || ")]".contains(end)
                      else { return false }
                      return s.box.height <= 0.8 * base.height
                          && s.box.minX >= base.maxX - 0.2 * base.height
                          && s.box.minX - base.maxX <= 0.6 * base.height
                          && (s.box.maxY <= base.midY + 0.1 * base.height && s.box.maxY > base.minY - 0.5 * base.height
                              || s.box.minY >= base.midY - 0.1 * base.height && s.box.maxY > base.maxY + 0.1 * base.height)
                  }) else { i += 1; continue }
            let superscript = s.box.maxY <= segs[a].box.midY + 0.1 * segs[a].box.height
            let script = ScriptRecovery.script(s.text, superscript: superscript)
            // ScriptRecovery may already have read it as part of the line.
            if !segs[a].shown.hasSuffix(script) { segs[a].shown += script }
            segs[a].box = segs[a].box.union(s.box)
            segs[a].order = min(segs[a].order, s.order)
            segs.remove(at: i)
            i = 0
        }
        return segs.sorted { $0.order < $1.order }
    }

    private static let mathMarks = CharacterSet(charactersIn: "=≤≥≠→⇒⇔±×÷∑∫√∞")
        .union(CharacterSet(charactersIn: String(ScriptRecovery.superscripts.values) + String(ScriptRecovery.subscripts.values)))

    /// Operators on a math line spaced the way it is typeset (`F= ma` →
    /// `F = ma`, `(x²-9)` → `(x² - 9)`): relations always, `+` and `-` only
    /// between two operands (`-3`, `(-x)`, `= -1` stay tight), never inside a
    /// word (`x-axis`, `Cobb-Douglas`).
    static func spacedOperators(_ text: String) -> String {
        let chars = Array(text)
        func operand(_ c: Character?) -> Bool {
            guard let c else { return false }
            return c.isLetter || c.isNumber || ")]′'!".contains(c)
                || ScriptRecovery.superscripts.values.contains(c) || ScriptRecovery.subscripts.values.contains(c)
        }
        func opens(_ c: Character?) -> Bool {
            guard let c else { return false }
            return c.isLetter || c.isNumber || "([√".contains(c)
        }
        var out = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            var before = i - 1
            while before >= 0, chars[before] == " " { before -= 1 }
            var after = i + 1
            while after < chars.count, chars[after] == " " { after += 1 }
            let prev: Character? = before >= 0 ? chars[before] : nil
            let next: Character? = after < chars.count ? chars[after] : nil
            let relation = "=≤≥≠≈→⇒⇔".contains(c) && prev != nil && next != nil
                && !"=<>!".contains(prev!) && !"=<>".contains(next!)
            var binary = "×÷".contains(c) && operand(prev) && opens(next)
            if c == "+" || c == "-", operand(prev), opens(next) {
                // Letters touching both sides, one side a word: a hyphen.
                let left = chars[..<i].reversed().prefix { $0.isLetter }.count
                let right = chars[(i + 1)...].prefix { $0.isLetter }.count
                binary = !(left >= 1 && right >= 1 && max(left, right) >= 2)
            }
            if relation || binary {
                while out.last == " " { out.removeLast() }
                out += " \(c) "
                i = after
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }

    /// Set symbols Vision reads as letters, by what surrounds them: `A n B` →
    /// `A ∩ B`, `A U B` → `A ∪ B`, `x E R` → `x ∈ ℝ`; a stray `.` after `=`
    /// (a fraction bar's end); a space after a comma between terms (`b,c`).
    static func repairedMathSymbols(_ text: String) -> String {
        var out = text
        for (pattern, template) in mathRepairs {
            out = pattern.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: template)
        }
        return spacedFunctionArguments(out)
    }

    private static let mathRepairs: [(NSRegularExpression, String)] = [
        (#"(?<=[A-Z)] )n(?= [A-Z(])"#, "∩"),
        (#"(?<=[A-Z)] )U(?= [A-Z(])"#, "∪"),
        (#"(?<=\b[a-z] )[E€](?= [A-Z]\b)"#, "∈"),
        (#"(?<=∈ )N\b"#, "ℕ"), (#"(?<=∈ )Z\b"#, "ℤ"), (#"(?<=∈ )Q\b"#, "ℚ"), (#"(?<=∈ )R\b"#, "ℝ"),
        (#"= ?\.(?= |$)"#, "="),
        (#",(?=[^\s\d])|(?<=[^\d]),(?=\d)"#, ", "),
        // `lal` / `| a|` → `|a|` (a norm or absolute value), `√(14)` → `√14`,
        // `a•b` → `a · b`, `cosθ` / `sin3x` → `cos θ` / `sin 3x`.
        (#"(?<![A-Za-z])l([a-zA-Z])l(?![A-Za-z])"#, "|$1|"),
        (#"\| ([a-zA-Z])\|"#, "|$1|"),
        (#"√\((\d+(?:\.\d+)?)\)"#, "√$1"),
        // Trig names with a digit look-alike (`3c0s3x`, `s1n x`).
        (#"(?<![A-Za-z])c[0O]s(?=[\s\dA-Za-zθ(])"#, "cos"),
        (#"(?<![A-Za-z])s[1l|]n(?=[\s\dA-Za-zθ(])"#, "sin"),
        (#"(?<=[\w)|]) ?[•·] ?(?=[\w(|])"#, " · "),
        // A lone x between two fractions is a times sign (`dy/du X du/dx`).
        (#"(?<=/[\w)]{1,12}) [xX] (?=[\w(]{1,12}/)"#, " × "),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    /// `cosθ`, `sinx`, `sin3x` → `cos θ`, `sin x`, `sin 3x` — unless the
    /// letter makes a word (`cost`, `sine`, `sect`).
    static func spacedFunctionArguments(_ text: String) -> String {
        var out = text
        for match in functionArgument.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let name = Range(match.range(at: 1), in: out) else { continue }
            let next = out[name.upperBound]
            if next.isLetter, WordList.contains(String(out[name]) + String(next)) == true { continue }
            if next.isNumber, !["sin", "cos", "tan", "sec", "csc", "cot"].contains(String(out[name])) { continue }
            out.insert(" ", at: name.upperBound)
        }
        return out
    }

    private static let functionArgument = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])(sin|cos|tan|sec|csc|cot|log|ln|exp)(?=\d|[a-zθ](?![A-Za-z]))"#)

    /// A line of mostly-math: separate display equations are separate lines.
    static func isMath(_ text: String) -> Bool {
        text.unicodeScalars.contains { mathMarks.contains($0) } && text.split(separator: " ").filter { $0.count > 3 && $0.allSatisfy(\.isLetter) }.count <= 1
    }
}
