import Foundation

/// Folds typographic look-alikes a careful human would type either way
/// (minus sign vs hyphen, curly vs straight quotes, prime vs apostrophe, NBSP).
/// Everything else (², ₁, ×, √, tabs, indentation) must match exactly.
func fold(_ s: String) -> String {
    var out = ""
    for ch in s {
        switch ch {
        case "\u{2212}": out.append("-")          // − minus
        case "\u{2019}", "\u{2018}", "\u{2032}": out.append("'")   // ’ ‘ ′
        case "\u{201C}", "\u{201D}": out.append("\"")
        case "\u{00A0}": out.append(" ")
        default: out.append(ch)
        }
    }
    return out
}

/// Normalizes a clipboard string for comparison: fold look-alikes, strip
/// trailing whitespace per line, drop leading/trailing blank lines, drop blank
/// lines entirely unless the case keeps them (code), and drop ASCII spaces in
/// `.ignoreSpaces` mode.
func normalize(_ s: String, mode: Mode, keepBlankLines: Bool) -> String {
    var lines = fold(s).replacingOccurrences(of: "\r\n", with: "\n")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            var l = String(line)
            while let last = l.last, last == " " || last == "\t" { l.removeLast() }
            return l
        }
    while lines.first?.isEmpty == true { lines.removeFirst() }
    while lines.last?.isEmpty == true { lines.removeLast() }
    if !keepBlankLines { lines = lines.filter { !$0.isEmpty } }
    var joined = lines.joined(separator: "\n")
    if mode == .ignoreSpaces { joined = joined.replacingOccurrences(of: " ", with: "") }
    return joined
}

func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = Array(0...b.count)
    var cur = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
        cur[0] = i
        for j in 1...b.count {
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
        }
        swap(&prev, &cur)
    }
    return prev[b.count]
}

struct Score {
    var pass: Bool
    /// Character error rate: Levenshtein(actual, expected) / len(expected), best variant.
    var cer: Double
    /// Same with every whitespace character removed from both sides — isolates
    /// glyph recognition from layout (line breaks, tabs, indentation, order of lines is still counted).
    var glyphCER: Double
}

func score(_ c: Case, actual: String?) -> Score {
    if c.expected.isEmpty {
        let ok = actual == nil
        return Score(pass: ok, cer: ok ? 0 : 1, glyphCER: ok ? 0 : 1)
    }
    let act = normalize(actual ?? "", mode: c.mode, keepBlankLines: c.keepBlankLines)
    let actGlyphs = Array(act.filter { !$0.isWhitespace })
    var best = Score(pass: false, cer: .infinity, glyphCER: .infinity)
    for variant in c.expected {
        let exp = normalize(variant, mode: c.mode, keepBlankLines: c.keepBlankLines)
        let expGlyphs = Array(exp.filter { !$0.isWhitespace })
        let cer = Double(levenshtein(Array(act), Array(exp))) / Double(max(exp.count, 1))
        let g = Double(levenshtein(actGlyphs, expGlyphs)) / Double(max(expGlyphs.count, 1))
        if act == exp { return Score(pass: true, cer: 0, glyphCER: 0) }
        best.cer = min(best.cer, cer)
        best.glyphCER = min(best.glyphCER, g)
    }
    return best
}

/// Makes tabs and line structure visible in the text report.
func visible(_ s: String?) -> String {
    guard let s else { return "    | <no text found — clipboard untouched>" }
    return s.split(separator: "\n", omittingEmptySubsequences: false)
        .map { "    | " + $0.replacingOccurrences(of: "\t", with: "⇥") }
        .joined(separator: "\n")
}
