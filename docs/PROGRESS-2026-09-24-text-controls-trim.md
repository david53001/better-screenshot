# Progress — text fix, recording controls, rich text tool, trim (started 2026-09-24)

Repo: this BetterScreenshot macOS app (see `CLAUDE.md`). Owner-approved batch (built directly, no spec — owner OK'd a short plan in chat). All four items
are **committed locally on `main`, not pushed to GitHub** (owner asked to hold the push):
`d845ad1` editor (items 0 + 2) · `4a4316c` recording pill (1) · `88f3a8f` trim (3) · then a docs
commit (CHANGELOG / README / CLAUDE.md / this file).

## 0. Text tool "deletes the line above" — DONE
- Cause: inline editor was a fixed 200×28 `NSTextField`; wrapped lines scrolled out of view.
- Fix: `EditorCanvasView` inline editor is now an auto-growing `NSTextView` (grows right to the
  canvas edge, then wraps and grows down). Return commits · ⇧/⌥Return newline · Esc / click-away
  commits. `TextAnnotation.wrapWidth` (image px, optional) makes the committed text wrap exactly
  like the editor showed it.
- Tests: `Packages/EditorKit/Tests/EditorKitTests/TextAnnotationTests.swift` (newline + wrap cases).

## 1. Floating stop/pause controls while recording — DONE
- `App/Recording/RecordingControlsController.swift`: dark pill (red dot · timer · Pause/Resume ·
  Stop), draggable, shown from `RecordingCoordinator.begin` (before the countdown — Stop there
  cancels) until stop/cancel/failure (`tearDownPanels`, `cancelStrip`, `stop`).
- Setting `RecordingConfig.controlsInRecording` (key `controlsInRecording`, default **false**) →
  Settings → Recording → "Show stop button in recording". Off = the pill's `SCWindow` is passed
  to `SCContentFilter(display:excludingWindows:)`. Window recordings never include it.
- `RecordingCoordinator.shareableContent(containing:)` retries briefly so the freshly shown pill
  is in the ScreenCaptureKit (SCK) window list before building the filter.
- Verified with a headless probe: buttons fire, paused state swaps Pause→Resume, the pill is in the
  SCK window list, and an `SCScreenshotManager` capture with the exclusion filter has no pill.

## 2. Rich text tool — DONE
- `AnnotationStyle` gained `fontFamily` (a `TextFont` preset — "System", "System Rounded",
  "System Serif", "System Mono" — or an installed family name), `fontBold` (default true = the old
  semibold look), `fontItalic`, `textAlignment` (`TextAlign` left/center/right). All decode with
  defaults, so an older persisted `editorDefaultStyle` still loads.
- `Packages/EditorKit/Sources/EditorKit/TextFont.swift` resolves the font (unknown family → system).
- Canvas (`EditorCanvasView`): Text tool click = free label, drag = fixed-width text box
  (`TextAnnotation.wrapWidth`); clicking existing text with the Text tool, or double-clicking it
  with Select, edits it in place (same annotation id, one undo step; emptying it deletes it);
  a selected text shows only side handles, which change the box width. Inspector changes restyle
  the live editor and (Text tool only) the selected text. `commitPendingText()` runs before
  Copy/Save/Stack so text being typed isn't dropped from the export (was a latent bug).
- Inspector (`EditorWindowController`): Text tool now has a second row — font menu, size menu
  (12–96), B/I, alignment. Other tools keep the single 44pt row.
- Tests: `TextFontTests.swift`, `AnnotationStyleCodableTests.swift` (legacy decode). A headless
  canvas probe (synthetic mouse/keyboard events, 40 checks, not in the repo) passed all checks.

## 3. Trim for recordings — DONE
Follows `docs/superpowers/specs/2026-06-05-betterscreenshot-trim-editor-design.md`, with one owner
change: after **Replace Original** the window stays open on plain playback of the trimmed file
("Trimmed ✓ original replaced", Cancel becomes Done, Adjust Trim trims again); Save as Copy closes
and presents a new Quick Access card + History entry.
- RecordingKit: `TrimRange`, `TrimmedFileName` (pure), `TrimExporter` (passthrough export; mute =
  video-only composition; `exportCopy`; `replaceOriginal` = temp in an item-replacement dir +
  `FileManager.replaceItemAt`), `TrimWindowController` (AVKit trim mode; Save buttons disabled
  while the yellow handles are up — the range is read when AVKit's own Trim is pressed).
- OverlayKit: `QuickAccessActions.onTrim` (optional) → ✂ button on recording cards (MP4 only).
- App: `RecordingCoordinator.presentTrim(url:)`; History window gets **Trim…** (action bar +
  context menu) via `HistoryWindowActions.trim`.
- Tests: `TrimRangeTests.swift`, `TrimExporterTests.swift` (writes a real H.264+AAC MP4 fixture).
  The spec's AVKit go/no-go probe passed: trim mode works in the CLT-built SwiftPM binary; a
  headless probe drove Trim → Save as Copy and Trim → Mute → Replace Original end to end.

## Known gaps / not verified
- Nothing was clicked by a human yet: GUI checks were done with synthetic events + snapshots.
  Worth a real pass: type in the Text tool, record with the pill, trim a real recording.
- After Replace Original, the History thumbnail (first frame) is not regenerated.
- The macOS 14 export path (`exportAsynchronously`) compiles but only the macOS 15+ path
  (`export(to:as:)`) ran here (owner's Mac is on macOS 26).
- The Windows port (`windows-port` branch) has none of these features.
- Not pushed, not tagged, no version bump. CHANGELOG has an "Unreleased" entry. Next release steps:
  bump the version, tag, push (see earlier releases in `git log` for the pattern).

## Build / test
`swift build` · `scripts/test.sh` · `scripts/build-app.sh` → `dist/BetterScreenshot.app`.
If you get "PCH was compiled with module cache path …/Home/Code/…" or "cannot find 'TextFont' in
scope" from the root build: the repo moved / a stale build plan; run `swift package clean` (root and
each `Packages/*`), then rebuild.
