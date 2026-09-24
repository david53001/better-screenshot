import TestKit
import Foundation
@testable import EditorKit

private func decode(_ json: String) -> AnnotationStyle? {
    try? JSONDecoder().decode(AnnotationStyle.self, from: Data(json.utf8))
}

private let legacyPrefix = """
{"strokeColor": {"r": 1, "g": 0, "b": 0, "a": 1}, "fillColor": {"r": 1, "g": 0, "b": 0, "a": 0.25},
 "lineWidth": 4, "fontSize": 24
"""

let textStyleTests: [TestCase] = [
    TestCase("textV2FieldsDefaultToTodaysLook") { t in
        let s = AnnotationStyle.default
        t.equal(s.textBackgroundMode, .none)
        t.isTrue(RecentColors.same(s.textBackgroundColor, RGBAColor(r: 0, g: 0, b: 0, a: 0.8)), "black 80%")
        t.approxEqual(Double(s.textBackgroundPadding), 6)
        t.approxEqual(Double(s.textBackgroundCornerRadius), 4)
        t.isFalse(s.textUnderline); t.isFalse(s.textStrikethrough)
        t.isFalse(s.textOutline); t.isFalse(s.textShadow)
        t.isTrue(RecentColors.same(s.textOutlineColor, RGBAColor(r: 1, g: 1, b: 1, a: 1)), "white outline")
        t.approxEqual(Double(s.textOutlineWidth), 3)
    },
    TestCase("legacyStyleWithoutTextV2KeysDecodesToTheDefaults") { t in
        guard let s = t.unwrap(decode(legacyPrefix + "}")) else { return }
        var expected = AnnotationStyle.default
        expected.strokeColor = s.strokeColor; expected.fillColor = s.fillColor
        t.isTrue(s == expected, "every new field takes its default")
    },
    TestCase("legacyTextBackgroundBoolMapsToAutoOrNone") { t in
        t.equal(decode(legacyPrefix + #", "textBackground": true}"#)?.textBackgroundMode, .auto)
        t.equal(decode(legacyPrefix + #", "textBackground": false}"#)?.textBackgroundMode, TextBackgroundMode.none)
        t.equal(decode(legacyPrefix + "}")?.textBackgroundMode, TextBackgroundMode.none)
    },
    TestCase("backgroundModeWinsOverTheLegacyBool") { t in
        t.equal(decode(legacyPrefix + #", "textBackground": true, "textBackgroundMode": "solid"}"#)?.textBackgroundMode, .solid)
        t.equal(decode(legacyPrefix + #", "textBackground": true, "textBackgroundMode": "sparkly"}"#)?.textBackgroundMode,
                .auto, "an unknown mode falls back to the legacy Bool")
    },
    TestCase("textV2FieldsRoundTrip") { t in
        var s = AnnotationStyle.default
        s.textBackgroundMode = .solid
        s.textBackgroundColor = RGBAColor(r: 0.1, g: 0.2, b: 0.3, a: 0.4)
        s.textBackgroundPadding = 11; s.textBackgroundCornerRadius = 9
        s.textUnderline = true; s.textStrikethrough = true
        s.textOutline = true; s.textOutlineColor = RGBAColor(r: 0, g: 0, b: 1, a: 1); s.textOutlineWidth = 5
        s.textShadow = true
        do {
            let d = try JSONDecoder().decode(AnnotationStyle.self, from: JSONEncoder().encode(s))
            t.isTrue(d == s, "all text v2 fields survive JSON")
        } catch { t.fail("round-trip threw: \(error)") }
    },
    TestCase("decodeClampsPaddingRadiusAndOutlineWidth") { t in
        let s = decode(legacyPrefix + #", "textBackgroundPadding": -5, "textBackgroundCornerRadius": 999, "textOutlineWidth": 0}"#)
        t.approxEqual(Double(s?.textBackgroundPadding ?? -1), 0)
        t.approxEqual(Double(s?.textBackgroundCornerRadius ?? -1), Double(AnnotationStyle.textBackgroundCornerRadiusRange.upperBound))
        t.approxEqual(Double(s?.textOutlineWidth ?? -1), 1)
    },
    TestCase("autoBoxContrastsWithTheTextColour") { t in
        let dark = TextChip.autoColor(forText: RGBAColor(r: 1, g: 1, b: 1, a: 1))
        let light = TextChip.autoColor(forText: RGBAColor(r: 0, g: 0, b: 0, a: 1))
        t.isTrue(dark.r < 0.2 && light.r > 0.9, "white text → dark box, black text → light box")
        t.equal(TextChip.insets(padding: 6), CGSize(width: 6, height: 3))
    },
    TestCase("presetsSetTheirLook") { t in
        func applied(_ p: TextStylePreset) -> AnnotationStyle { var s = AnnotationStyle.default; p.apply(to: &s); return s }
        let label = applied(.label)
        t.equal(label.textBackgroundMode, .solid)
        t.isTrue(RecentColors.same(label.textBackgroundColor, RGBAColor(r: 0, g: 0, b: 0, a: 0.8)), "Label: black box")
        t.isTrue(RecentColors.same(label.strokeColor, RGBAColor(r: 1, g: 1, b: 1, a: 1)) && label.fontBold, "Label: bold white")
        t.isTrue(RecentColors.same(applied(.callout).textBackgroundColor, RGBAColor(r: 1, g: 0.27, b: 0.23, a: 1)), "Callout: red")
        let note = applied(.note)
        t.isTrue(RecentColors.same(note.strokeColor, RGBAColor(r: 0, g: 0, b: 0, a: 1)) && !note.fontBold, "Note: black regular")
        t.isTrue(RecentColors.same(note.textBackgroundColor, RGBAColor(r: 1, g: 0.84, b: 0.04, a: 1)), "Note: yellow")
        t.equal(applied(.code).fontFamily, TextFont.mono)
        t.approxEqual(Double(applied(.title).fontSize), 48)
        t.equal(applied(.title).textBackgroundMode, TextBackgroundMode.none)
        let subtle = applied(.subtle)
        t.approxEqual(Double(subtle.fontSize), 18)
        t.isFalse(subtle.fontBold)
        t.equal(TextStylePreset.allCases.map(\.displayName), ["Label", "Callout", "Note", "Code", "Title", "Subtle"])
    },
    TestCase("presetsOnlyTouchTheTextLook") { t in
        var s = AnnotationStyle.default
        s.textAlignment = .center; s.opacity = 0.5; s.lineWidth = 9; s.fontSize = 30
        s.textOutline = true; s.textShadow = true; s.textUnderline = true; s.fontItalic = true
        var label = s; TextStylePreset.label.apply(to: &label)
        t.equal(label.textAlignment, .center)
        t.approxEqual(Double(label.opacity), 0.5)
        t.approxEqual(Double(label.lineWidth), 9)
        t.approxEqual(Double(label.fontSize), 30, tol: 1e-9)   // Label keeps the size
        t.isFalse(label.textOutline || label.textShadow || label.textUnderline || label.fontItalic, "effects reset")
        var title = s; TextStylePreset.title.apply(to: &title)
        t.isTrue(RecentColors.same(title.strokeColor, s.strokeColor), "Title keeps the colour")
    },
    TestCase("presetsRoundTripAndAreRecognised") { t in
        for p in TextStylePreset.allCases {
            var s = AnnotationStyle.default
            t.isFalse(p.isApplied(to: s), "\(p) isn't the default look")
            p.apply(to: &s)
            t.isTrue(p.isApplied(to: s), "\(p) recognised after applying")
            do {
                let d = try JSONDecoder().decode(AnnotationStyle.self, from: JSONEncoder().encode(s))
                t.isTrue(d == s && p.isApplied(to: d), "\(p) survives JSON")
            } catch { t.fail("round-trip threw: \(error)") }
            for other in TextStylePreset.allCases where other != p {
                t.isFalse(other.isApplied(to: s), "\(other) not active after \(p)")
            }
        }
    },
]
