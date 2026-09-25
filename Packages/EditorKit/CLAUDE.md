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
- Text v2 (v3 Part 2): `AnnotationStyle.textBackgroundMode` (none/solid/auto — the old Bool
  `textBackground` only decodes), box colour/padding/corners, underline/strike, outline, shadow.
  `TextChip` = box geometry (`insets`: padding × padding/2) + Auto colour; `TextStylePreset` = the
  Styles chips; `TextScale` = pure corner-drag scaling (the canvas maps handles 0/2/5/7 onto its
  corners and always scales the mouse-down snapshot). A text's `boundingBox()` **includes the box
  padding**, so side-handle maths subtracts it. While typing, the canvas draws the box + outline
  behind the `NSTextView` (`drawDecorations()`). The shadow maps its offset through the CTM with a
  deliberate sign flip — `canvasShadowFallsDownwardToo` guards it.
- Window: `EditorWindowController.swift` — window, tool pill, bottom bar (hint line; zoom + image size ·
  Done/Stack/Save/Copy), title-bar buttons, key handling (tool shortcuts, Esc, zoom keys, ⌥⌘I) and
  wiring. Keep it thin. The window is **always Dark Aqua** (the vibrant-dark panels wash out over a light
  window). A title-bar accessory view needs a real frame width (`stack.frame = fittingSize`) or it is clipped.
- Side panel (v3 Part 1): `InspectorModel.swift` (pure: which `InspectorSection`s show for tool +
  selection, panel heading, hint-line sentence), `EditorInspectorView.swift` (builds the sections, emits
  style edits; **Arrange is a footer** below the scroll area, not a scrolled section; Opacity / Strength /
  Dim have no caption — the name sits in the row's label column), `EditorChrome.swift` (tool button,
  `SwatchButton`, `InspectorCheckbox`, `InspectorStyle` caption/row/note helpers + the shared 56pt
  `labelWidth` and swatch grid, `LabeledSliderRow`, `CenteringClipView`). The panel's scroll area wants
  its content height below `windowSizeStayPut` — above it, a long panel grows the window instead of scrolling.
- Selection handles: shapes get 8 squares on the frame; a text gets `TextHandles` (pure) — round corners
  just outside the box (scale) and side bars (box width) that are dropped when the box is too short.
- Tools: `EditorTool.swift` — the enum plus one switch each for name, SF Symbol, single-key shortcut,
  and `maker(of:)` (annotation → the tool that draws it; how the panel describes a selection).
- Zoom: `ZoomMath.swift` (pure), `EditorZoom.swift` (`EditorScrollView` pinch / ⌘-scroll →
  `CanvasZoomController`, which resizes the canvas; the canvas maps view ↔ image through `scale`).
  Fit never goes past **100%** (the capture's real size), and the initial window is sized from the
  image's point size (`ZoomMath.pointSize`), not its pixel size.
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

## Guided tours (v3 Part 7 — anchors and events)
The editor's five tours (Editor, Text, Redaction, Highlighter, Spotlight) are data in
`Packages/TourKit/Sources/TourKit/Catalog/EditorTours.swift`; every step, trigger, anchor and event is listed
in `docs/MAC-TO-WINDOWS-PARITY-v3.md` §7.5. EditorKit only marks controls and reports actions — no tour
logic, no UI added for tours:
- **Anchors** (`view.tourAnchor = "editor.…"`, TourKit): `editor.toolbar`, `editor.tool.<EditorTool raw value>`,
  `editor.canvas` (the **scroll view** — the canvas itself outgrows the window when zoomed), `editor.inspector`,
  `editor.inspector.<InspectorSection raw value>` (each section box, set in `rebuild`; the Arrange footer is
  `editor.inspector.arrange`), `editor.hint`, `editor.zoom`, `editor.imageSize`, `editor.actions`,
  `editor.done/stack/save/copy`, `editor.undo/redo/panelToggle`, `editor.info` (the ⓘ). A new section or
  control gets its anchor the same way; renaming one silently skips the tour steps that name it.
- **Events** (`TourEvents.post`): `EditorWindowController.selectTool` → `.toolSelected(tool.rawValue)` for the
  user's tool changes (not the Arrow chosen in `init`), plus `.action("editor.redactionToolChosen")` for Blur
  or Pixelate; `EditorCanvasView.insert` → `.annotationAdded(<maker tool raw value>)`, plus
  `.action("editor.redactionAdded")` for any redaction; `mouseUp` after a text-corner drag →
  `.action("editor.textScaled")`; every side-panel edit → `.styleChanged(<field>)` via
  `EditorInspectorView.tourEdited` (sliders only when released). A **Try step** (a tour step that advances
  when the user does the thing, rather than on Next) can only wait for an event that is actually posted here.
- **ⓘ**: `InfoButton.install` in `buildTitlebarButtons` (rightmost), with `keyboardShortcuts` — update that
  list when a key is added.
- **Esc**: `EditorWindow` adopts `TourEscapeClaiming` (`escapeInUse` = not on Select, or something selected),
  so a tour tag leaves Esc-to-Select alone and Esc only skips a tour once the editor has nothing to do with it.
- Tests: `Tests/EditorKitTests/EditorTourTests.swift` (anchors exist per tour, events, ⓘ, Esc, and every
  editor-tour body fits the tag's 2 lines — the 20-word lint alone doesn't guarantee that).

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
events) — see the Part 1 section of `docs/MAC-TO-WINDOWS-PARITY-v3.md`. Capture windows with
`CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution])`:
`cacheDisplay` leaves out the title bar and the blur effects (so snapshots made with it hid the
zero-width title-bar buttons found by `docs/reviews/2026-09-25-ui-review.md`, issue E1). Keep probe
windows behind the owner's work: set every window's level to
`CGWindowLevelForKey(.desktopWindow) + 1` and call `orderBack(nil)`; never order them front.
