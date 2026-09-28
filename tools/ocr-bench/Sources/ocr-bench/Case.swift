import CoreGraphics

enum Area: String, CaseIterable {
    case prose, lists, code, tables, math, layout, robustness
}

/// How the clipboard string is compared with the ground truth.
enum Mode: String {
    /// Exact after normalization (see Scoring.swift).
    case exact
    /// Same, but ASCII spaces are ignored (math: `x²+y²=z²` == `x² + y² = z²`).
    /// Newlines and tabs still count.
    case ignoreSpaces
}

/// One corpus case: an HTML snippet rendered offscreen by WKWebView, cropped to
/// the `#cap` element (the simulated user selection), then fed to the real
/// `TextRecognizer.recognize(in:pointWidth:)`.
struct Case {
    var id: String
    var area: Area
    var desc: String
    /// 2 = Retina capture (pointWidth = pixelWidth / 2); 1 = external 1x monitor
    /// (the 2x render is area-averaged down to 1x, pointWidth = pixelWidth).
    var density: Int = 2
    /// Web view width in points (CSS px).
    var width: CGFloat = 800
    /// true: `#cap` is inline-block (a tight selection around a formula).
    var fit: Bool = false
    var css: String = ""
    var html: String
    /// Accepted clipboard strings; the first is canonical. Empty = the case
    /// expects "No text found" (clipboard untouched).
    var expected: [String]
    var mode: Mode = .exact
    /// Code keeps blank lines; everything else ignores them.
    var keepBlankLines = false

    var document: String {
        """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><style>
        html,body{margin:0;padding:0;background:#fff;color:#111}
        #cap{padding:24px;box-sizing:border-box}
        #cap.fit{display:inline-block}
        math{font-family:'STIX Two Math',math}
        \(css)
        </style></head><body><div id="cap"\(fit ? " class=\"fit\"" : "")>\(html)</div></body></html>
        """
    }
}

// MARK: - Variant helpers

/// Leading-tab indentation rendered as 2 or 4 spaces too.
func indentVariants(_ s: String) -> [String] {
    func swap(_ unit: String) -> String {
        s.components(separatedBy: "\n").map { line -> String in
            let tabs = line.prefix { $0 == "\t" }.count
            return String(repeating: unit, count: tabs) + line.dropFirst(tabs)
        }.joined(separator: "\n")
    }
    return [s, swap("  "), swap("    ")]
}

/// Leading 4-space indentation rendered as tabs too.
func codeVariants(_ s: String, unit: Int = 4) -> [String] {
    let tabbed = s.components(separatedBy: "\n").map { line -> String in
        let spaces = line.prefix { $0 == " " }.count
        return String(repeating: "\t", count: spaces / unit) + String(repeating: " ", count: spaces % unit) + line.dropFirst(spaces)
    }.joined(separator: "\n")
    return [s, tabbed]
}

/// Inner tabs (label → value) typed as a single space instead.
func tabOrSpace(_ s: String) -> [String] {
    [s, s.replacingOccurrences(of: "\t", with: " ")]
}
