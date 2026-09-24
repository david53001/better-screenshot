/// A titled group in the editor's side panel. Case order = top-to-bottom order in the panel.
///
/// To add a section: add a case here (with its `title`), list it in
/// `InspectorModel.objectSections(for:)` / `toolSections(for:)` for the tools that show it, and
/// build its controls in `EditorInspectorView.makeSection(_:)`.
public enum InspectorSection: String, CaseIterable {
    case colour, stroke, font, background, redaction, strength, opacity, arrange
    /// Explanatory text only — the Crop tool and Select with nothing selected.
    case cropHelp, selectHelp

    /// Caption above the section; nil = no caption (a plain note).
    public var title: String? {
        switch self {
        case .colour: return "Colour"
        case .stroke: return "Stroke"
        case .font: return "Font"
        case .background: return "Background"
        case .redaction: return "Redaction"
        case .opacity: return "Opacity"
        case .arrange: return "Arrange"
        case .strength: return "Strength"
        case .cropHelp, .selectHelp: return nil   // the panel heading already names the tool
        }
    }

    /// Body text of the note-only sections.
    public var note: String? {
        switch self {
        case .cropHelp:
            return "Drag over the part of the image you want to keep. Undo (⌘Z) brings the rest back."
        case .selectHelp:
            return "Click an object on the image to change it here. Drag across empty space to select several."
        default: return nil
        }
    }
}

/// What the side panel shows: a heading plus its sections, in order.
public struct InspectorContent: Equatable {
    public var title: String
    public var sections: [InspectorSection]
    public init(title: String, sections: [InspectorSection]) {
        self.title = title; self.sections = sections
    }
}

/// Pure rules for the editor's side panel and hint line. A selected object is described by
/// the tool that draws it (`EditorTool`), so a new object type is just a new tool case.
public enum InspectorModel {
    /// Style sections an object drawn by `tool` exposes (empty for tools that draw nothing).
    public static func objectSections(for tool: EditorTool) -> [InspectorSection] {
        switch tool {
        case .arrow, .line, .rectangle, .ellipse: return [.colour, .stroke, .opacity]
        case .filledRectangle, .counter: return [.colour, .opacity]
        case .text: return [.colour, .font, .background, .opacity]
        case .blur, .pixelate: return [.redaction, .strength]
        case .blackout: return [.redaction]   // a solid box has no strength
        case .select, .crop: return []
        }
    }

    /// Sections while `tool` is active (and it isn't Select).
    public static func toolSections(for tool: EditorTool) -> [InspectorSection] {
        switch tool {
        case .crop: return [.cropHelp]
        case .select: return [.selectHelp]
        default: return objectSections(for: tool)
        }
    }

    /// `selection` lists the selected objects by the tool that draws each one.
    /// A drawing tool shows its own sections (its selection is the object just drawn with it);
    /// Select shows the selection's shared sections plus Arrange.
    public static func content(tool: EditorTool, selection: [EditorTool]) -> InspectorContent {
        guard tool == .select else {
            return InspectorContent(title: tool.displayName, sections: toolSections(for: tool))
        }
        guard let first = selection.first else {
            return InspectorContent(title: "Nothing selected", sections: [.selectHelp])
        }
        let shared = InspectorSection.allCases.filter { s in
            selection.allSatisfy { objectSections(for: $0).contains(s) }
                // One Strength slider can't show a blur radius and a pixel size at once.
                && (s != .strength || Set(selection).count == 1)
        }
        let title = selection.count == 1 ? first.displayName : "\(selection.count) objects"
        return InspectorContent(title: title, sections: shared + [.arrange])
    }

    /// One plain sentence for the hint line above the action bar.
    public static func hint(tool: EditorTool, selection: [EditorTool], editingText: Bool) -> String {
        if editingText { return "Type your text — ↩ or Esc finishes it, ⇧↩ starts a new line." }
        switch tool {
        case .select:
            if selection.count > 1 { return "Drag to move them together, or press Delete to remove them." }
            switch selection.first {
            case nil: return "Click an object to select it, or drag across empty space to select several."
            case .text?: return "Drag to move it, drag a side handle to set the box width, or double-click to edit the text."
            case .rectangle?, .filledRectangle?, .ellipse?, .blur?, .pixelate?, .blackout?:
                return "Drag to move it, drag a handle to resize it, or press Delete to remove it."
            default: return "Drag to move it, or press Delete to remove it."
            }
        case .arrow: return "Drag to draw an arrow — it points to where you let go."
        case .line: return "Drag to draw a straight line."
        case .rectangle: return "Drag to draw a rectangle outline."
        case .filledRectangle: return "Drag to draw a solid rectangle that covers what's under it."
        case .ellipse: return "Drag to draw an ellipse."
        case .text: return "Click to type a label, drag to make a text box, or click existing text to edit it."
        case .counter: return "Click to place the next numbered step."
        case .blur: return "Drag over anything you want to hide — it's blurred when you let go."
        case .pixelate: return "Drag over anything you want to hide — it's pixelated when you let go."
        case .blackout: return "Drag over anything you want to hide — it's covered in solid black when you let go."
        case .crop: return "Drag over the area to keep — everything outside is cut away (⌘Z undoes it)."
        }
    }
}
