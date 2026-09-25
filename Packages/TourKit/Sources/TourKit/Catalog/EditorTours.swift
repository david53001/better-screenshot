// The annotation editor's tours (spec §14.3 table, adapted to the editor as built — lane 7E).
// Anchors are set in EditorKit (`EditorWindowController`, `EditorInspectorView`): `editor.toolbar`,
// `editor.tool.<EditorTool raw value>`, `editor.canvas` (the image area), `editor.inspector` and
// `editor.inspector.<InspectorSection raw value>`, `editor.hint`, `editor.zoom`, `editor.actions`,
// `editor.info` (the ⓘ). Events are posted where the action already happens (EditorKit/CLAUDE.md).
// Windows-port copy of every string: docs/MAC-TO-WINDOWS-PARITY-v3.md §7.5.
extension TourCatalog {
    /// The first editor window. It opens with the Arrow already chosen, so the tour starts by drawing
    /// one rather than asking to choose it. Five steps (review 2026-09-26, E2: Welcome → Quick Access →
    /// Editor was 16 tags in a row): "Your tools" is folded into the arrow step, the hint line and the
    /// side-panel overview are dropped, and "Finish up" names the ⓘ that replays the tour. Step 1 names
    /// the Arrow's key because a replay (ⓘ) can start with another tool chosen.
    static let editor = Tour(id: .editor, surface: .editor, trigger: .surfaceShown(.editor), steps: [
        TourStep(anchor: "editor.toolbar", kind: .tryIt(advanceOn: .annotationAdded("arrow")), title: "Draw an arrow",
                 body: "Pick the Arrow (A) in this bar, then drag on the image. Hover any tool for its key."),
        TourStep(anchor: "editor.inspector.colour", kind: .tryIt(advanceOn: .styleChanged("strokeColor")),
                 title: "Pick a colour",
                 body: "Click any swatch. It colours what’s selected and what you draw next."),
        TourStep(anchor: "editor.inspector.stroke", kind: .explain, title: "Width and opacity",
                 body: "Set the line width. Opacity, just below, makes it see-through."),
        TourStep(anchor: "editor.zoom", kind: .explain, title: "Zoom",
                 body: "Pinch or ⌘-scroll to zoom. ⌘0 fits the image, ⌘1 shows it at real size."),
        TourStep(anchor: "editor.actions", kind: .explain, title: "Finish up",
                 body: "Copy it, Save it, or Stack it bottom-right. Done closes; ⓘ replays this tour."),
    ])

    /// The first time the Text tool is chosen.
    static let text = Tour(id: .text, surface: .editor, trigger: .event(.toolSelected("text")), steps: [
        TourStep(anchor: "editor.canvas", kind: .tryIt(advanceOn: .annotationAdded("text")), title: "Click to type",
                 body: "Click anywhere on the image, type, then press Return."),
        TourStep(anchor: "editor.canvas", kind: .explain, title: "Or drag a box",
                 body: "Drag instead of clicking to make a text box — the words wrap inside it."),
        // Only once a text exists (Skip step on "Click to type" would leave nothing to resize).
        TourStep(anchor: "editor.canvas", kind: .tryIt(advanceOn: .action("editor.textScaled")), title: "Resize your text",
                 body: "Drag a round corner of the text to make it bigger or smaller.",
                 requires: .annotationAdded("text")),
        TourStep(anchor: "editor.inspector.styles", kind: .explain, title: "Styles",
                 body: "One click gives your text a ready-made look."),
        // Below, inside the panel: "left" put the tag over the text the user just made (review X3).
        TourStep(anchor: "editor.inspector.background", kind: .explain, title: "Background",
                 body: "Put a box behind the text: Solid in any colour, or Auto for contrast.", placement: .below),
        TourStep(anchor: "editor.inspector.effects", kind: .explain, title: "Effects",
                 body: "An outline or shadow keeps text readable on busy images."),
    ])

    /// The first time Blur or Pixelate is chosen — both post `editor.redactionToolChosen`, so one
    /// trigger covers either.
    static let redaction = Tour(id: .redaction, surface: .editor,
                                trigger: .event(.action("editor.redactionToolChosen")), steps: [
        TourStep(anchor: "editor.canvas", kind: .tryIt(advanceOn: .action("editor.redactionAdded")),
                 title: "Hide something",
                 body: "Drag over anything private — it’s hidden when you let go."),
        // Below, inside the panel, so the tag doesn't cover the redaction being adjusted (review X3).
        TourStep(anchor: "editor.inspector.strength", kind: .tryIt(advanceOn: .styleChanged("strength")),
                 title: "Change the strength",
                 body: "Drag the Strength slider until it can’t be read.", placement: .below),
        TourStep(anchor: "editor.inspector.redaction", kind: .explain, title: "Three ways to hide",
                 body: "Switch any time. Black-out is the safest — nothing can be recovered."),
    ])

    /// The first time the Highlighter is chosen.
    static let highlighter = Tour(id: .highlighter, surface: .editor,
                                  trigger: .event(.toolSelected("highlighter")), steps: [
        TourStep(anchor: "editor.canvas", kind: .tryIt(advanceOn: .annotationAdded("highlighter")),
                 title: "Highlight something",
                 body: "Drag across text like a marker pen. Hold ⇧ for a straight line."),
        TourStep(anchor: "editor.inspector.highlighterStroke", kind: .explain, title: "Marker width",
                 body: "Pick Thin, Medium or Thick. The marker keeps its own colour and width."),
    ])

    /// The first time the Spotlight is chosen.
    static let spotlight = Tour(id: .spotlight, surface: .editor,
                                trigger: .event(.toolSelected("spotlight")), steps: [
        TourStep(anchor: "editor.canvas", kind: .tryIt(advanceOn: .annotationAdded("spotlight")),
                 title: "Spotlight something",
                 body: "Drag over what matters — everything else dims. Hold ⌥ for an ellipse."),
        // Below, inside the panel, so the tag doesn't cover the spotlight's handles (review X3).
        TourStep(anchor: "editor.inspector.spotlightDim", kind: .explain, title: "Dim outside",
                 body: "Set how dark everything outside your spotlights gets.", placement: .below),
    ])
}
