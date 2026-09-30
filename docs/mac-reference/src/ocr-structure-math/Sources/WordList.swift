import Foundation

/// The system's English word list (`/usr/share/dict/words`, on every Mac),
/// loaded on first use. Offline, no spell-check service involved.
enum WordList {
    private static let words: Set<String>? = {
        guard let text = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else { return nil }
        return Set(text.split(separator: "\n").map { $0.lowercased() })
    }()

    /// Whether `word` (or its stem: `reactions` → `reaction`, `studied` →
    /// `study`) is an English word; nil when there is no word list.
    static func contains(_ word: String) -> Bool? {
        guard let words else { return nil }
        let w = word.lowercased()
        if words.contains(w) { return true }
        let endings: [(String, String)] = [("ies", "y"), ("ied", "y"), ("es", ""), ("s", ""), ("ed", ""), ("ed", "e"),
                                           ("d", ""), ("ing", ""), ("ing", "e"), ("ly", ""), ("er", ""), ("ers", ""),
                                           ("est", ""), ("ness", ""), ("ment", ""), ("ments", "")]
        for (ending, replacement) in endings where w.hasSuffix(ending) && w.count > ending.count + 2 {
            let stem = String(w.dropLast(ending.count))
            if words.contains(stem + replacement) { return true }
            // A doubled consonant: `running` → `run`.
            if let last = stem.last, stem.dropLast().last == last, words.contains(String(stem.dropLast())) { return true }
        }
        return false
    }
}
