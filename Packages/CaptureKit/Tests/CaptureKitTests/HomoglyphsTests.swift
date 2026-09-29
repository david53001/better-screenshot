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
    TestCase("cyrillicPeIsPiInMathAndNElsewhere") { t in
        t.equal(Homoglyphs.latinized("x = 5\u{43F}/6, 2\u{43F}r", keepCyrillic: false, keepGreek: false), "x = 5π/6, 2πr")
        t.equal(Homoglyphs.latinized("Ca\u{43F}ada", keepCyrillic: false, keepGreek: false), "Canada")
    },
    TestCase("romanianCedillasTakeTheirCommas") { t in
        t.equal(Homoglyphs.latinized("Ştefănescu, Timiş, Ţara", keepCyrillic: false, keepGreek: false, romanian: true),
                "Ștefănescu, Timiș, Țara")
        t.equal(Homoglyphs.latinized("Timiş", keepCyrillic: false, keepGreek: false), "Timiş")
        t.isTrue(Homoglyphs.scripts(in: ["en-US", "ro-RO"]).romanian)
    },
    TestCase("scriptsFromLanguages") { t in
        t.isTrue(Homoglyphs.scripts(in: ["en-US", "ru-RU"]).cyrillic)
        t.isFalse(Homoglyphs.scripts(in: ["en-US", "ro-RO"]).cyrillic)
        t.isFalse(Homoglyphs.scripts(in: ["en-US", "ro-RO"]).greek)
    },
]
