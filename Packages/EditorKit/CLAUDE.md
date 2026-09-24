# EditorKit — annotation editor (model + canvas + renderer)

The annotation document model, a custom AppKit `NSView` canvas + tools, and the flatten-to-image
renderer. Imported by the `App/` target (capture flow opens the editor).

## Key files (`Sources/EditorKit/`)
- `EditorDocument.swift` — the annotation document model.
- Annotation types: `Annotation.swift` (+ `drawComposited()`, which applies `style.opacity` as one
  transparency layer — canvas and renderer call it, never `draw()` directly), `ArrowAnnotation.swift`,
  `ShapeAnnotations.swift`, `TextAnnotation.swift`, `CounterAnnotation.swift`, `RedactionAnnotations.swift`.
- Styling: `AnnotationStyle.swift`, `RGBAColor.swift` (Codable — persisted as the app's sticky default;
  every field added later decodes with `decodeIfPresent` + a default so an older saved style still loads),
  `TextFont.swift` (font family/bold/italic → `NSFont`; unknown family falls back to system).
- Text: `TextAnnotation.wrapWidth` = text-box width (nil = free label). The canvas's inline editor is
  an `NSTextView` laid out with the same attributes as the committed annotation.
- Window: `EditorWindowController.swift` — window, tool pill, bottom bar (hint line, dims, zoom, actions),
  title-bar buttons, key handling (tool shortcuts, Esc, zoom keys, ⌥⌘I) and wiring. Keep it thin.
- Side panel (v3 Part 1): `InspectorModel.swift` (pure: which `InspectorSection`s show for tool +
  selection, panel heading, hint-line sentence), `EditorInspectorView.swift` (builds the sections, emits
  style edits), `EditorChrome.swift` (tool button, `SwatchButton`, `InspectorStyle` caption/row/note
  helpers, `LabeledSliderRow`, `CenteringClipView`).
- Tools: `EditorTool.swift` — the enum plus one switch each for name, SF Symbol, single-key shortcut,
  and `maker(of:)` (annotation → the tool that draws it; how the panel describes a selection).
- Zoom: `ZoomMath.swift` (pure), `EditorZoom.swift` (`EditorScrollView` pinch / ⌘-scroll →
  `CanvasZoomController`, which resizes the canvas; the canvas maps view ↔ image through `scale`).
- `RecentColors.swift` — last 6 custom colours (pure); the host persists them (`editorRecentColors`).
- Rendering/geometry: `DocumentRenderer.swift`, `Redactor.swift`, `ArrowGeometry.swift`.
- v3 Part 3: `RedactionAnnotations.swift` (one `RedactionAnnotation`; mode Blur/Pixelate/Black-out +
  strength live in the style, so panel edits convert/restyle selected ones), `HighlighterAnnotation.swift`
  (multiply `blendMode`; the tool's own sticky `HighlighterPen`, swapped in by the window),
  `SpotlightAnnotation.swift` (+ `AnnotationPainter`: the draw order both canvas and renderer use),
  `ToolDefaults.swift`.

## How to add an inspector section
(The "inspector" is the editor's right-side panel. Parts 2/3 = text v2 and redaction/highlighter/spotlight
in `docs/superpowers/specs/2026-09-24-betterscreenshot-editor-recording-v3-design.md` §5–§6.)
1. `InspectorModel.swift`: add a case to `InspectorSection` (case order = panel order) with its `title`,
   and list it in `objectSections(for:)` (objects of that tool, used under Select too) and/or
   `toolSections(for:)` (while the tool is active). Add a TestKit case in `InspectorModelTests.swift`.
2. `EditorInspectorView.swift`: return the section's rows from `makeSection(_:)` (each row spans
   `InspectorStyle.contentWidth` = 232pt; reuse `LabeledSliderRow`, `InspectorStyle.row`, segmented
   controls with `.small` size + `.fillEqually`), and append a closure to `refreshers` that reads
   `style` (or `tool`) back into the controls — sections are rebuilt only when the section list changes.
3. Emit changes with `onStyleEdit?({ $0.field = v }, group)`: the window applies the edit to the default
   style *and* every selected object as one undo step. Pass a non-nil `group` for continuous controls
   (slider drags) and call `onStyleEditEnded?()` when the drag finishes, so the drag is one step.
4. A new object type = a new `EditorTool` case (fill in every switch in `EditorTool.swift`, incl.
   `maker(of:)`) + `objectSections(for:)` + a `hint(...)` sentence. Tool shortcuts come from
   `shortcutKey` (Part 3: H highlighter, S spotlight); the toolbar groups are `toolGroups` in the controller.
5. New style fields go on `AnnotationStyle` with `decodeIfPresent` defaults + a legacy-decode test.

## Invariants (do not break)
- Annotations live in **base-image pixel space, top-left origin**.
- The renderer draws into a **flipped `NSGraphicsContext`** so AppKit drawing (incl. text) is
  right-side-up. Changing the flip will mirror/upside-down everything.
- **Zoom only resizes the canvas** inside its scroll view; everything maps through `scale`
  (image px per view pt). Never assume view points == image pixels (handles are 8 *view* points).
- **Sticky default style:** the app injects a `defaultStyle` (last-used color/size) and listens for
  style changes; the persistence itself lives in `App/Settings/SettingsStore` (`editorDefaultStyle`).
  Recent colours use the same pattern (`recentColors:` in, `onRecentColorsChanged` out).
- Switching to a drawing tool clears the selection; Select keeps it. A just-drawn object stays selected,
  so the panel restyles it straight away.
- The bottom-bar **Stack** button is wired in the app to `keepInStack` (add to Quick Access), not Pin.
- **Redactions render from the base image for their current frame** (cached) — never store a baked patch;
  a crop rebases them (`EditorDocument.cropped`). They are always opaque.
- **Draw order** (`AnnotationPainter`): base → spotlight dim layer → objects in stacking order, with the dim
  re-applied over each redaction. Draw through it (or `drawComposited()`), never a bare `draw()` loop.

## Verify
`swift run -j 2 --package-path Packages/EditorKit EditorKitTests`. UI: headless probe (synthetic
events + `cacheDisplay` snapshots) — see the Part 1 section of `docs/MAC-TO-WINDOWS-PARITY-v3.md`.
