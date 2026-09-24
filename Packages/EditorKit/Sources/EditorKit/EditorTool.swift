public enum EditorTool: String, CaseIterable {
    case select, arrow, line, rectangle, filledRectangle, ellipse
    case text, counter, blur, pixelate, crop
    /// v3 Part 3. Black-out has no toolbar button (it's the Redaction switch's third segment).
    case blackout, highlighter, spotlight
}

// Per-tool metadata: name, toolbar icon and single-key shortcut. Adding a tool means
// adding one case to each switch (the compiler points at every one).
public extension EditorTool {
    /// Human name — toolbar tooltip, inspector title.
    var displayName: String {
        switch self {
        case .select: return "Select"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .filledRectangle: return "Filled Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .counter: return "Counter"
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .crop: return "Crop"
        case .blackout: return "Black-out"
        case .highlighter: return "Highlighter"
        case .spotlight: return "Spotlight"
        }
    }

    /// SF Symbol shown in the toolbar.
    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .filledRectangle: return "rectangle.fill"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .counter: return "1.circle.fill"
        case .blur: return "drop.fill"
        case .pixelate: return "square.grid.3x3.fill"
        case .crop: return "crop"
        case .blackout: return "rectangle.inset.filled"
        case .highlighter: return "highlighter"
        case .spotlight: return "flashlight.on.fill"
        }
    }

    /// Single-key shortcut (lowercase; case-insensitive when typed).
    var shortcutKey: Character {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .line: return "l"
        case .rectangle: return "r"
        case .filledRectangle: return "f"
        case .ellipse: return "o"
        case .text: return "t"
        case .counter: return "n"
        case .blur: return "b"
        case .pixelate: return "p"
        case .crop: return "c"
        case .blackout: return "x"
        case .highlighter: return "h"
        case .spotlight: return "s"
        }
    }

    /// Toolbar tooltip, e.g. "Arrow (A)".
    var tooltip: String { "\(displayName) (\(shortcutKey.uppercased()))" }

    /// The tool whose shortcut is `characters` (a single typed key), if any.
    static func forShortcut(_ characters: String) -> EditorTool? {
        guard characters.count == 1, let c = characters.lowercased().first else { return nil }
        return allCases.first { $0.shortcutKey == c }
    }
}

public extension EditorTool {
    /// The tool that draws `annotation` — how the inspector describes a selected object.
    static func maker(of annotation: any Annotation) -> EditorTool? {
        switch annotation {
        case is ArrowAnnotation: return .arrow
        case is LineAnnotation: return .line
        case is RectangleAnnotation: return .rectangle
        case is FilledRectangleAnnotation: return .filledRectangle
        case is EllipseAnnotation: return .ellipse
        case is TextAnnotation: return .text
        case is CounterAnnotation: return .counter
        case let r as RedactionAnnotation: return r.style.redactionMode.tool
        case is HighlighterAnnotation: return .highlighter
        case is SpotlightAnnotation: return .spotlight
        default: return nil
        }
    }
}
