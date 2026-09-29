/// Vision mixes scripts even when only Latin-script languages are requested:
/// "CO₂" can come back as Cyrillic "СО", which looks right but breaks search,
/// spell-check and anything that parses the text. When the user reads no
/// Cyrillic or Greek, letters that only look Latin are mapped back to Latin.
/// Greek letters with no Latin twin (α, θ, π, Σ …) are real math and stay.
public enum Homoglyphs {
    static let cyrillic: [Character: Character] = [
        "А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "І": "I", "Ј": "J", "К": "K", "М": "M",
        "О": "O", "Р": "P", "Ѕ": "S", "Т": "T", "Х": "X", "а": "a", "с": "c", "е": "e", "і": "i",
        "ј": "j", "о": "o", "р": "p", "ѕ": "s", "у": "y", "х": "x", "з": "3",
    ]
    static let greek: [Character: Character] = [
        "Α": "A", "Β": "B", "Ε": "E", "Ζ": "Z", "Η": "H", "Ι": "I", "Κ": "K", "Μ": "M", "Ν": "N",
        "Ο": "O", "Ρ": "P", "Τ": "T", "Υ": "Y", "Χ": "X", "ο": "o",
    ]

    /// Romanian's `ș ț` take a comma below; Vision returns the cedilla forms
    /// `ş ţ` (Turkish letters), which search and spell-check treat as different.
    static let romanianCommas: [Character: Character] = ["Ş": "Ș", "ş": "ș", "Ţ": "Ț", "ţ": "ț"]

    public static func latinized(_ text: String, keepCyrillic: Bool, keepGreek: Bool, romanian: Bool = false) -> String {
        let chars = Array(text)
        return String(chars.indices.map { i -> Character in
            let c = chars[i]
            if romanian, let comma = romanianCommas[c] { return comma }
            // Cyrillic `п`/`П` is how Vision reads `π`: beside a digit, `/` or `=`
            // it is π, anywhere else the `n` it looks like.
            if "пП".contains(c), !keepCyrillic {
                // One on its own (an integral's limit, read as `a = П`) is π too.
                let alone = (i == 0 || chars[i - 1] == " ") && (i + 1 == chars.count || chars[i + 1] == " ")
                if alone { return "π" }
                let near = [i > 0 ? chars[i - 1] : " ", i + 1 < chars.count ? chars[i + 1] : " "]
                return near.contains { $0.isNumber || "/=()".contains($0) } ? "π" : "n"
            }
            return (!keepCyrillic ? cyrillic[c] : nil) ?? (!keepGreek ? greek[c] : nil) ?? c
        })
    }

    /// Whether the recognition languages include a Cyrillic / Greek script
    /// one, and Romanian.
    public static func scripts(in languages: [String]) -> (cyrillic: Bool, greek: Bool, romanian: Bool) {
        let codes = Set(languages.map { String($0.prefix { $0 != "-" && $0 != "_" }) })
        return (!codes.isDisjoint(with: ["ru", "uk", "bg", "sr", "be", "mk", "kk", "ky", "mn", "tg"]), codes.contains("el"),
                codes.contains("ro"))
    }
}
