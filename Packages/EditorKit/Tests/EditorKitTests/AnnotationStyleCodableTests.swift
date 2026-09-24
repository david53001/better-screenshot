import TestKit
import Foundation
@testable import EditorKit

let annotationStyleCodableTests: [TestCase] = [
    TestCase("annotationStyleRoundTripsThroughJSON") { t in
        let original = AnnotationStyle(
            strokeColor: RGBAColor(r: 0.04, g: 0.52, b: 1.0, a: 1.0),
            fillColor: RGBAColor(r: 0.04, g: 0.52, b: 1.0, a: 0.25),
            lineWidth: 7, fontSize: 36)
        do {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AnnotationStyle.self, from: data)
            t.approxEqual(Double(decoded.strokeColor.r), 0.04, tol: 1e-6)
            t.approxEqual(Double(decoded.strokeColor.g), 0.52, tol: 1e-6)
            t.approxEqual(Double(decoded.strokeColor.b), 1.0, tol: 1e-6)
            t.approxEqual(Double(decoded.strokeColor.a), 1.0, tol: 1e-6)
            t.approxEqual(Double(decoded.fillColor.a), 0.25, tol: 1e-6)
            t.approxEqual(Double(decoded.lineWidth), 7, tol: 1e-9)
            t.approxEqual(Double(decoded.fontSize), 36, tol: 1e-9)
            t.isTrue(decoded == original, "decoded should equal original")
        } catch {
            t.fail("round-trip threw: \(error)")
        }
    },
    TestCase("annotationStyleDefaultsTextBackgroundToFalse") { t in
        let style = AnnotationStyle(
            strokeColor: RGBAColor(r: 0.04, g: 0.52, b: 1.0, a: 1.0),
            fillColor: RGBAColor(r: 0.04, g: 0.52, b: 1.0, a: 0.25),
            lineWidth: 7, fontSize: 36)
        t.isTrue(style.textBackgroundMode == .none, "freshly constructed style should default to no text background")
        t.isTrue(AnnotationStyle.default.textBackgroundMode == .none, "AnnotationStyle.default should default to no text background")
    },
    TestCase("annotationStyleDecodesLegacyJSONMissingTextBackground") { t in
        let legacyJSON = """
        {
            "strokeColor": {"r": 0.04, "g": 0.52, "b": 1.0, "a": 1.0},
            "fillColor": {"r": 0.04, "g": 0.52, "b": 1.0, "a": 0.25},
            "lineWidth": 7,
            "fontSize": 36
        }
        """
        do {
            let decoded = try JSONDecoder().decode(AnnotationStyle.self, from: Data(legacyJSON.utf8))
            t.isTrue(decoded.textBackgroundMode == .none, "legacy JSON without textBackground key should decode to none")
            t.approxEqual(Double(decoded.strokeColor.r), 0.04, tol: 1e-6)
            t.approxEqual(Double(decoded.strokeColor.g), 0.52, tol: 1e-6)
            t.approxEqual(Double(decoded.strokeColor.b), 1.0, tol: 1e-6)
            t.approxEqual(Double(decoded.strokeColor.a), 1.0, tol: 1e-6)
            t.approxEqual(Double(decoded.fillColor.a), 0.25, tol: 1e-6)
            t.approxEqual(Double(decoded.lineWidth), 7, tol: 1e-9)
            t.approxEqual(Double(decoded.fontSize), 36, tol: 1e-9)
        } catch {
            t.fail("legacy decode threw: \(error)")
        }
    },
    TestCase("annotationStyleTextBackgroundRoundTripsTrue") { t in
        var style = AnnotationStyle(
            strokeColor: RGBAColor(r: 0.04, g: 0.52, b: 1.0, a: 1.0),
            fillColor: RGBAColor(r: 0.04, g: 0.52, b: 1.0, a: 0.25),
            lineWidth: 7, fontSize: 36)
        style.textBackgroundMode = .auto
        do {
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(AnnotationStyle.self, from: data)
            t.isTrue(decoded.textBackgroundMode == .auto, "textBackgroundMode = auto should round-trip through JSON")
        } catch {
            t.fail("round-trip threw: \(error)")
        }
    },
    TestCase("legacyStyleDecodesWithTodaysTextLook") { t in
        let legacyJSON = """
        {"strokeColor": {"r": 1, "g": 0, "b": 0, "a": 1},
         "fillColor": {"r": 1, "g": 0, "b": 0, "a": 0.25},
         "lineWidth": 4, "fontSize": 24, "textBackground": true}
        """
        do {
            let s = try JSONDecoder().decode(AnnotationStyle.self, from: Data(legacyJSON.utf8))
            t.equal(s.fontFamily, TextFont.system)
            t.isTrue(s.fontBold, "legacy text was semibold")
            t.isFalse(s.fontItalic)
            t.equal(s.textAlignment, .left)
            t.equal(s.textBackgroundMode, .auto)
        } catch { t.fail("legacy decode threw: \(error)") }
    },
    TestCase("textFontFieldsRoundTrip") { t in
        var s = AnnotationStyle.default
        s.fontFamily = "Georgia"; s.fontBold = false; s.fontItalic = true; s.textAlignment = .center
        do {
            let d = try JSONDecoder().decode(AnnotationStyle.self, from: JSONEncoder().encode(s))
            t.isTrue(d == s, "round-trip keeps font fields")
        } catch { t.fail("round-trip threw: \(error)") }
    },
]
