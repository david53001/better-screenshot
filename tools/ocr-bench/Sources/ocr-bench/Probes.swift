import CoreGraphics
import CaptureKit

/// Deterministic, Vision-free reproductions of the TextReflow root causes found
/// in the corpus (boxes copied/simplified from real `dump` output). Each prints
/// input → actual → expected. Run: `ocr-bench probes`.
func runProbes() {
    func L(_ t: String, top: CGFloat, x: CGFloat, w: CGFloat, h: CGFloat) -> TextReflow.Line {
        TextReflow.Line(text: t, box: CGRect(x: x, y: top, width: w, height: h))
    }
    let probes: [(String, [TextReflow.Line], [String])] = [
        ("R1 row fragments joined in arrival (minY) order, not x order — C06 printf split by Vision",
         [L("printf(\"%d\\n\"", top: 0.6195, x: 0.094, w: 0.181, h: 0.080),
          L(", *p);", top: 0.6190, x: 0.273, w: 0.083, h: 0.080)],
         ["printf(\"%d\\n\", *p);"]),
        ("R2 height-ratio rule splits a paragraph whose last line is a short word — P02 'years.'",
         [L("Rivers carry these dissolved salts to the sea, where they accumulate over millions of", top: 0.359, x: 0.035, w: 0.894, h: 0.069),
          L("years.", top: 0.461, x: 0.032, w: 0.067, h: 0.043)],
         ["Rivers carry these dissolved salts to the sea, where they accumulate over millions of years."]),
        ("R3 longest line always 'wraps' — two separate sentences merge (R06)",
         [L("Der Bär läuft über die Brücke.", top: 0.10, x: 0.03, w: 0.40, h: 0.08),
          L("Le garçon a mangé une crème brûlée.", top: 0.25, x: 0.03, w: 0.46, h: 0.08),
          L("El niño tiene cinco años.", top: 0.40, x: 0.03, w: 0.33, h: 0.08)],
         ["Der Bär läuft über die Brücke.", "Le garçon a mangé une crème brûlée.", "El niño tiene cinco años."]),
        ("R4 de-hyphenation deletes the hyphen of a real compound (P03 light-dependent)",
         [L("chemical energy stored in glucose. The light-", top: 0.20, x: 0.07, w: 0.86, h: 0.12),
          L("dependent reactions take place in the thylakoid", top: 0.34, x: 0.07, w: 0.86, h: 0.12)],
         ["chemical energy stored in glucose. The light-dependent reactions take place in the thylakoid"]),
        ("R5 x/y unit mix in isAdjacent: table cells 5+ char-widths apart glue into one line with spaces (T03-like, 1240x282 image)",
         [L("Ana Ionescu", top: 0.30, x: 0.030, w: 0.090, h: 0.10),
          L("78", top: 0.30, x: 0.220, w: 0.018, h: 0.10),
          L("85", top: 0.30, x: 0.325, w: 0.018, h: 0.10)],
         ["Ana Ionescu\t78\t85"]),
        ("R6 re-sorting by minY destroys Vision's column order (Y07: Vision returns left column, then right)",
         [L("Advantages", top: 0.386, x: 0.056, w: 0.167, h: 0.091),
          L("• Low carbon emissions", top: 0.533, x: 0.064, w: 0.278, h: 0.071),
          L("Disadvantages", top: 0.388, x: 0.532, w: 0.206, h: 0.087),
          L("• Radioactive waste", top: 0.533, x: 0.536, w: 0.233, h: 0.071)],
         ["Advantages", "• Low carbon emissions", "Disadvantages", "• Radioactive waste"]),
        ("R7 indentation discarded (C07 YAML: minX 0.037 / 0.068 / 0.096 = 0 / 2 / 4 spaces)",
         [L("jobs:", top: 0.295, x: 0.037, w: 0.070, h: 0.058),
          L("build:", top: 0.377, x: 0.068, w: 0.084, h: 0.063),
          L("runs-on: macos-15", top: 0.473, x: 0.096, w: 0.236, h: 0.058)],
         ["jobs:", "  build:", "    runs-on: macos-15"]),
    ]
    var failed = 0
    for (name, lines, expected) in probes {
        let got = TextReflow.paragraphs(lines)
        let ok = got == expected
        if !ok { failed += 1 }
        print("[\(ok ? "PASS" : "FAIL")] \(name)")
        print("   actual:   \(got.map { $0.replacingOccurrences(of: "\t", with: "⇥") })")
        print("   expected: \(expected.map { $0.replacingOccurrences(of: "\t", with: "⇥") })")
    }
    print("\(probes.count - failed)/\(probes.count) probes pass")
}
