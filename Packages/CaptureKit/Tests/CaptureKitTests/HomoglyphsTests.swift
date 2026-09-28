import TestKit
@testable import CaptureKit

let homoglyphsTests: [TestCase] = [
    TestCase("cyrillicLookAlikesBecomeLatin") { t in
        // "СО₂ + Н₂О" with Cyrillic С, О, Н.
        t.equal(Homoglyphs.latinized("\u{421}\u{41E}₂ + \u{41D}₂\u{41E}", keepCyrillic: false, keepGreek: false), "CO₂ + H₂O")
        t.equal(Homoglyphs.latinized("H_\u{421}\u{41E}\u{437}", keepCyrillic: false, keepGreek: false), "H_CO3")
    },
    TestCase("realScriptsStayWhenTheUserReadsThem") { t in
        t.equal(Homoglyphs.latinized("Привет", keepCyrillic: true, keepGreek: false), "Привет")
    },
    TestCase("mathGreekIsNeverTouched") { t in
        t.equal(Homoglyphs.latinized("α + β = π, Σ θ", keepCyrillic: false, keepGreek: false), "α + β = π, Σ θ")
    },
    TestCase("scriptsFromLanguages") { t in
        t.isTrue(Homoglyphs.scripts(in: ["en-US", "ru-RU"]).cyrillic)
        t.isFalse(Homoglyphs.scripts(in: ["en-US", "ro-RO"]).cyrillic)
        t.isFalse(Homoglyphs.scripts(in: ["en-US", "ro-RO"]).greek)
    },
]
