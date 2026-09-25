// The annotation editor's tours (spec §14.3 table, adapted to the editor as built — lane 7E).
// Anchors are set in EditorKit (`EditorWindowController`, `EditorInspectorView`): `editor.toolbar`,
// `editor.tool.<EditorTool raw value>`, `editor.canvas` (the image area), `editor.inspector` and
// `editor.inspector.<InspectorSection raw value>`, `editor.hint`, `editor.zoom`, `editor.actions`,
// `editor.info` (the ⓘ). Events are posted where the action already happens (EditorKit/CLAUDE.md).
// Windows-port copy of every string: docs/MAC-TO-WINDOWS-PARITY-v3.md §7.5.
extension TourCatalog {
    /// The first editor window. It opens with the Arrow already chosen, so the tour starts by drawing
    /// one rather than asking to choose it.
    static let editor = Tour(id: .editor, surface: .editor, trigger: .surfaceShown(.editor), steps: [
        TourStep(anchor: "editor.toolbar", kind: .explain, title: "Your tools",
                 body: "Every tool is here. Hover one to see its key — A is Arrow, T is Text."),
        TourStep(anchor: "editor.canvas", kind: .tryIt(advanceOn: .annotationAdded("arrow")), title: "Draw an arrow",
                 body: "Drag on the image. The arrow points to where you let go."),
        TourStep(anchor: "editor.inspector", kind: .explain, title: "The side panel",
                 body: "Settings for the current tool — or for the object you select."),
        TourStep(anchor: "editor.inspector.colour", kind: .tryIt(advanceOn: .styleChanged("strokeColor")),
                 title: "Pick a colour",
                 body: "Click any swatch — it colours the selected object and everything you draw next."),
        TourStep(anchor: "editor.inspector.stroke", kind: .explain, title: "Width and opacity",
                 body: "Drag for any width, or pick Thin, Medium or Thick. Opacity, just below, makes it see-through."),
        TourStep(anchor: "editor.hint", kind: .explain, title: "The hint line",
                 body: "It says what the current tool does and which keys help."),
        TourStep(anchor: "editor.zoom", kind: .explain, title: "Zoom",
                 body: "Pinch or ⌘-scroll to zoom. ⌘0 fits the image, ⌘1 shows it at real size."),
        TourStep(anchor: "editor.actions", kind: .explain, title: "Finish up",
                 body: "Copy puts it on the clipboard, Save writes a file, Stack keeps it bottom-right. Done closes."),
        TourStep(anchor: "editor.info", kind: .explain, title: "Replay any time",
                 body: "Click ⓘ to see this tour again or list the keyboard shortcuts."),
    ])

    /// The first time the Text tool is chosen.
    static let text = Tour(id: .text, surface: .editor, trigger: .event(.toolSelected("text")), steps: [
        TourStep(anchor: "editor.canvas", kind: .tryIt(advanceOn: .annotationAdded("text")), title: "Click to type",
                 body: "Click anywhere on the image, type, then press Return."),
        TourStep(anchor: "editor.canvas", kind: .explain, title: "Or drag a box",
                 body: "Drag instead of clicking to make a text box — the words wrap inside it."),
        TourStep(anchor: "editor.canvas", kind: .tryIt(advanceOn: .action("editor.textScaled")), title: "Resize your text",
                 body: "Drag a round corner of the text to make it bigger or smaller."),
        TourStep(anchor: "editor.inspector.styles", kind: .explain, title: "Styles",
                 body: "One click gives your text a ready-made look."),
        TourStep(anchor: "editor.inspector.background", kind: .explain, title: "Background",
                 body: "Put a box behind the text: Solid in any colour, or Auto for contrast."),
        TourStep(anchor: "editor.inspector.effects", kind: .explain, title: "Effects",
                 body: "An outline or shadow keeps text readable on busy images."),
    ])

    /// The first time Blur or Pixelate is chosen — both post `editor.redactionToolChosen`, so one
    /// trigger covers either.
    static let redaction = Tour(id: .redaction, surface: .editor,
                                trigger: .event(.action("editor.redactionToolChosen")), steps: [
        TourStep(anchor: "editor.canvas", kind: .tryIt(advanceOn: .action("editor.redactionAdded")),
                 title: "Hide something",
                 body: "Drag over anything private — it's hidden when you let go."),
        TourStep(anchor: "editor.inspector.strength", kind: .tryIt(advanceOn: .styleChanged("strength")),
                 title: "Change the strength",
                 body: "Drag the Strength slider until it can't be read."),
        TourStep(anchor: "editor.inspector.redaction", kind: .explain, title: "Three ways to hide",
                 body: "Switch between Blur, Pixelate and Black-out. Black-out is the safest — nothing can be recovered."),
    ])

    /// The first time the Highlighter is chosen.
    static let highlighter = Tour(id: .highlighter, surface: .editor,
                                  trigger: .event(.toolSelected("highlighter")), steps: [
        TourStep(anchor: "editor.canvas", kind: .tryIt(advanceOn: .annotationAdded("highlighter")),
                 title: "Highlight something",
                 body: "Drag across text like a marker pen. Hold ⇧ for a straight line."),
        TourStep(anchor: "editor.inspector.highlighterStroke", kind: .explain, title: "Marker width",
                 body: "Pick a marker width. The highlighter remembers its own colour and width, apart from other tools."),
    ])

    /// The first time the Spotlight is chosen.
    static let spotlight = Tour(id: .spotlight, surface: .editor,
                                trigger: .event(.toolSelected("spotlight")), steps: [
        TourStep(anchor: "editor.canvas", kind: .tryIt(advanceOn: .annotationAdded("spotlight")),
                 title: "Spotlight something",
                 body: "Drag over what matters — everything else dims. Hold ⌥ for an ellipse."),
        TourStep(anchor: "editor.inspector.spotlightDim", kind: .explain, title: "Dim outside",
                 body: "Set how dark everything outside your spotlights gets."),
    ])
}
