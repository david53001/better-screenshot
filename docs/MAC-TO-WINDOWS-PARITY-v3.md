# macOS → Windows parity — the 2026-09 editor & recording work

**What this is.** The macOS app (this repo, `main`) gained features in September 2026 that the
Windows port does not have. This document tells whoever ports them **exactly** what was built —
layout, items, labels, behaviour, defaults, persisted data, and pure logic — so the Windows version
can match without reading Swift. It is the reverse of `docs/WINDOWS-TO-MAC-PARITY.md`.

**The Windows port.** C#/.NET 9 + WPF on the `windows-port` branch, under `windows/`. Start with
`windows/README-win.md`, `windows/docs/PROGRESS.md`, and the per-module ground-truth files
`windows/docs/port-reference/0N-*.md`. Its recording engine is **ffmpeg** (`ddagrab`/`gdigrab` video,
WASAPI loopback system audio, `dshow` microphone) with pause implemented as one ffmpeg segment per
active span, concatenated at the end (`windows/src/BetterScreenshot.App/Recording/RecordingEngine.cs`).

**Conventions.** Sizes are macOS points; treat 1 pt = 1 WPF device-independent pixel. "SF Symbol"
names are macOS icon names — map them to the port's icon set in
`windows/src/BetterScreenshot.App/Resources/Icons.xaml`. Quoted UI strings are verbatim and should be
copied exactly. The design rationale for Parts 0–6 is in
`docs/superpowers/specs/2026-09-24-betterscreenshot-editor-recording-v3-design.md`.

**Each section below covers:** Layout (exact) · Items & behaviour · Data (persisted keys, defaults,
legacy decoding) · Pure logic to port 1:1 (with the macOS test cases) · Where it goes in the port ·
Platform notes (where Windows must differ).

---

## A. Already built on macOS, 2026-09-24 (commits `d845ad1`, `4a4316c`, `88f3a8f`)

Three features landed on macOS before the v3 parts. Parts 1, 5 and 6 below later **restyle or
replace** some of their UI (the Text options move into the Part 1 side panel; the pill is expanded by
Part 5; the trim window becomes the Part 6 cut editor) — port the **behaviour and data** from this
section and the **final UI** from the later part sections.

### A.1 Text tool: fonts, text boxes, in-place editing, and the "line above disappears" fix

**The bug it fixed.** The inline text editor was a fixed 200×28 single-line field; once typing wrapped,
earlier lines scrolled out of view ("it deletes the line above"). The Windows port's `PlaceTextBox`
(`windows/src/BetterScreenshot.App/Editor/EditorWindow.xaml.cs`) uses a WPF `TextBox` with no
`AcceptsReturn` / wrapping and commits on Enter — check it for the same symptom when porting.

**Behaviour (port exactly):**
- **Text tool, click** → a *free label*: the editor grows to the right as you type, up to the canvas's
  right edge; past that it wraps and grows downward. It never scrolls earlier lines out of view.
- **Text tool, drag ≥ 12 view points wide** → a *text box* of the dragged width: text wraps inside it and
  the box grows downward only.
- **Keys while typing:** Return = commit · ⇧Return or ⌥Return = new line (on Windows use Shift+Enter;
  WPF: `AcceptsReturn` off, insert `\n` on Shift+Enter) · Esc = commit (not discard) · clicking elsewhere
  on the canvas = commit, and **that same click does not start a new text**.
- **Edit existing text:** click it with the Text tool, or double-click it with the Select tool. The text
  reopens in place with its own style, which is loaded into the inspector (not saved as the sticky
  default unless the user changes something). Committing keeps the **same annotation id** and is **one
  undo step**; committing an unchanged text adds no undo step; emptying the text deletes the annotation.
- **Resize a text box:** a selected text shows only the two **side (middle-left / middle-right)
  handles**; dragging them changes the box width (minimum = the font size in px) and the text reflows.
  Vertical drags are ignored for text. A free label becomes a box once resized.
- **Style changes while text is selected** under the Text tool restyle that text (one undo step each)
  and also become the default for the next text.
- **Copy / Save / Stack** first commit any text still being typed (it used to be dropped from the export).
- The committed text must lay out **exactly** like the editor showed it: same font, same wrap width,
  no text-container padding (macOS: `lineFragmentPadding = 0`, `textContainerInset = .zero`).

**Inspector (as shipped 2026-09-24; Part 1 moves these into the side panel's Text sections):**
Font popup · Size popup · Bold/Italic toggle pair · Alignment Left/Centre/Right, in a second row under
the colour row, only for the Text tool.
- **Font menu:** four presets first, each shown in its own face — "System", "Rounded", "Serif", "Mono"
  (persisted values `System`, `System Rounded`, `System Serif`, `System Mono`) — then a separator, then
  every installed font family (hide names starting with "."). Windows mapping suggestion: System →
  Segoe UI Variable/Segoe UI, Rounded → a rounded face if present else Segoe UI, Serif → Georgia or
  Cambria, Mono → Cascadia Mono/Consolas; list `Fonts.SystemFontFamilies` for the rest.
- **Size menu:** 12, 14, 18, 24, 30, 36, 48, 64, 96 pt (shown as "24 pt"); a persisted size not in the
  list is inserted in order.
- **Bold** defaults to **on** (reproduces the old semibold look): presets → Semibold weight when on,
  Regular when off; named families → Bold face when on. **Italic** default off.
- **Missing faces:** try (bold+italic) → drop italic → drop bold; an unknown / uninstalled family falls
  back to the System preset, so an old document or sticky style naming a removed font still renders.
- Text tool tooltip: "Text — click to type, drag for a text box, double-click text to edit".

**Data:**
- `AnnotationStyle` new JSON keys (all optional when decoding, defaults preserve the old look):
  `fontFamily` (string, default `"System"`), `fontBold` (bool, default `true`), `fontItalic` (bool,
  default `false`), `textAlignment` (`"left"` | `"center"` | `"right"`, default `"left"`). Persisted inside
  the sticky editor style (macOS UserDefaults key `editorDefaultStyle`; Windows: `EditorStyle.cs` JSON).
- `TextAnnotation.wrapWidth` (image px, optional): **null = free label** (only explicit newlines break
  lines; the box hugs the text); set = text-box width (lines wrap at it; alignment is relative to it; the
  bounding box width equals it). A free label that wrapped at the canvas edge while typing is stored with
  `wrapWidth` = the room that was available.
- The Windows `AnnotationStyle` already has `TextBackground: RGBAColor?` (a solid chip colour) where macOS
  had a Bool auto-contrast chip; Part 2 reconciles the two (None / Solid colour / Auto).

**Rendering:** attributes = font from the style + stroke colour + paragraph alignment; layout with the
text's line-fragment bounding rect at width `wrapWidth ?? ∞`; box size = `(wrapWidth ?? ceil(naturalWidth),
ceil(height))`; draw into that rect (a free label gets +1 px width slack so rounding can't wrap its last
word). WPF: `FormattedText` with `MaxTextWidth = wrapWidth`, `TextAlignment`, or a `TextBlock` with
`TextWrapping.Wrap`.

**Tests to recreate** (macOS files in `Packages/EditorKit/Tests/EditorKitTests/`):
`TextAnnotationTests` — a newline makes the box ≥ 1.8× taller than one line; `wrapWidth` 200 keeps width
≤ 200 and makes a long sentence ≥ 1.8× taller. `TextFontTests` — Mono preset is fixed-pitch; italic trait
applied; Helvetica bold+italic resolves both traits; unknown family → system family at the same size;
installed list contains Helvetica and no "."-names; ten "i"s in Mono are ≥ 1.3× wider than in System;
a box's width equals its `wrapWidth`; a 3-line wrapped text renders its first ink row within 20 px below
its origin and its last ink row inside its box. `AnnotationStyleCodableTests` — legacy JSON without the
font keys decodes to System / bold / not italic / left; all four font fields round-trip.

### A.2 Floating recording pill (compact v1) + "Show recording controls in the video"

(Part 5 turns this into the expanded pill — port Part 5's layout; the rules here still hold.)
- **When:** shown on the recording screen as soon as a recording is started — **before** the countdown —
  and hidden on stop, cancel, or failure. **Stop during the countdown cancels** the recording.
- **Layout v1:** borderless, non-activating, draggable pill 176×40 pt, fully rounded (radius 20), dark HUD
  material, drop shadow, always-on-top (macOS `.statusBar` level), positioned bottom-centre of the
  screen's visible area, 20 pt above its bottom. Left to right: red dot (10 pt, x = 16) · elapsed time
  (monospaced digits, 14 pt semibold, white; "m:ss") · Pause button (32×32, symbol `pause.fill` 15 pt,
  white) · Stop button (32×32, `stop.fill`, red). Buttons react on the first click without activating the
  app (macOS `acceptsFirstMouse`; WPF: `ShowActivated=false` + `WS_EX_NOACTIVATE`).
- **Paused:** the time freezes and turns secondary grey (white 60 %) under a small **"Paused"** label
  (Part 5); Pause becomes `play.fill` "Resume recording". Hover hints (Part 5's bubble, not tooltips):
  "Pause recording" / "Resume recording" / "Stop recording".
- **Setting:** Settings → In the video → **"Show recording controls in the video"** (renamed from "Show
  stop button in recording" by the fixes for `docs/reviews/2026-09-25-ui-review.md` item T6), default
  **off**, persisted key
  `controlsInRecording` ("true"/"false" in the recording-config dictionary). Help text (verbatim):
  "While recording, a floating pill with the timer, Pause and Stop is always on screen. Off: it's left
  out of the video itself. On: it's recorded like any other window." Example line: "Leave off for clean
  tutorials; window recordings never include it either way."
- **macOS mechanism:** the pill's window is passed to ScreenCaptureKit's exclusion list
  (`SCContentFilter(display:excludingWindows:)`), after waiting briefly until the new window shows up in
  the capturable-window list. **Windows:** call `SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)`
  (Windows 10 2004+) on the pill when the setting is off — it hides the window from Desktop Duplication
  (`ddagrab`) and GDI (`gdigrab`) capture; verify with a test recording. Region/window recordings that
  don't contain the pill need nothing.

### A.3 Trim window v1 (lossless trim / mute; save as copy or replace)

(Part 6 replaces the window's UI with the cut editor and Part 0 changes what Cancel does — port those
sections for the UI; the **export rules, names and strings** below carry over.)
- **Entry points:** an **Edit video** button (`scissors`, tooltip "Edit video" — it was "Trim" until the Part 6 editor landed) on the Quick Access card of **MP4**
  recordings only — the recording card becomes Copy file · Trim · Open · Show in Finder · Close (5 × 32 pt
  buttons; GIF cards keep 4) — and **"Edit Video…"** (was "Trim…") in the History window (action bar + right-click menu),
  enabled for a single MP4 recording whose file still exists. One trim window at a time; opening another
  file closes the current window.
- **v1 window:** title "Trim — <file name>", 900×600 (min 640×480): video player above a 52 pt action bar:
  range label (monospaced digits 12 pt, secondary) · "Mute audio" checkbox · spinner · Adjust Trim ·
  Cancel · Save as Copy · Replace Original (accent colour, deliberately **no** Return shortcut). Save
  buttons are disabled while the trim handles are up.
- **Label strings (verbatim):** "Loading…" · "Drag the yellow handles, then press Trim" ·
  "0:02.1 – 0:41.8 of 0:45.0" (format `m:ss.t`, rounded to tenths) · "Whole recording · 0:45.0" ·
  "Trimmed ✓ original replaced · 0:03.0" · "This recording can't be trimmed." · "This recording can't be
  opened for trimming." · error "Couldn't export trimmed recording — original untouched" (also as a HUD
  toast). After a replace the app shows the HUD "Recording trimmed".
- **Range rules (`TrimRange`, pure):** order the two ends, clamp into 0…duration, enforce a **0.5 s
  minimum** (grow the end, or the start backwards at the very end; a clip shorter than 0.5 s is kept
  whole). A range within **0.05 s** of both ends counts as "whole recording" (no trim).
- **Export:** lossless stream copy (no re-encode). Mute = drop every audio track. **Save as Copy** →
  "<stem> (trimmed).mp4" next to the original, then "<stem> (trimmed) 2.mp4", " 3"…; trimming a
  "(trimmed)" file reuses the stem instead of stacking suffixes. The copy gets its own card + History
  entry and the window closes. **Replace Original** → export to a temp file on the same volume, then
  atomically swap it in (the original is untouched unless the export fully succeeds); the window stays
  open, reloads the player on the trimmed file (plain playback), and Cancel becomes **Done**.
- **Windows (ffmpeg):** trim = `ffmpeg -ss <start> -to <end> -i in.mp4 -c copy [-an] out.mp4` (stream
  copy snaps to keyframes like macOS passthrough); replace = write to a temp file in the same folder,
  then `File.Replace` / `MoveFileEx(MOVEFILE_REPLACE_EXISTING)`.
- **Tests to recreate** (`Packages/RecordingKit/Tests/RecordingKitTests/TrimRangeTests.swift`,
  `TrimExporterTests.swift`): clamp 8→2 on 10 s = 2…8; −3…42 = 0…10; 4…4.1 → 4…4.5; 9.9…10 → 9.5…10;
  0.1…0.2 on 0.3 s → 0…0.3; no-op checks; timestamp 2.14 → "0:02.1", 61.96 → "1:02.0"; file names
  as above (incl. "Rec (trimmed).mp4" + taken " 2" → " 3"); a 3 s generated MP4 trimmed 0.5–2.0 is
  1.5 s with audio; muted 1.0–2.5 has no audio track; whole-range export keeps 3 s; two copies are named
  "(trimmed)" and "(trimmed) 2" and the original stays 3 s; replace leaves no temp files; replacing from
  a non-video file fails and leaves the original bytes unchanged.

---

## Part 0 — Trim window: Cancel restores the Quick Access card

**The bug (macOS, fixed).** A recording's Quick Access card has a ✂ **Trim** button. Pressing it
dismisses the card (reason `actionTaken`, so it is *not* added to "Restore Recently Closed") and opens
the trim / video-editor window. Closing that window never brought the card back, so cancelling looked
like it had deleted the recording.

**Behaviour now (port exactly).** The window that the card opens takes a `restoreCard` callback that
runs **exactly once, when the window closes, whatever closed it**:

| How the window closes | Cards afterwards |
|---|---|
| **Cancel** button or the window's close box, nothing saved | the original's card comes back in its corner |
| **Replace Original**, then **Done** / close box | the original's card comes back, its thumbnail re-extracted from the file (so it shows the *edited* file's first frame) |
| **Save as Copy** (the window closes itself) | the copy gets its own new card + History entry (as before) **and** the original's card comes back |
| **Export as GIF** (Part 6; window stays open), later closed | the GIF's card appears right after export; the original's card comes back on close |

- The restored card is a *new* card built the normal way (`presentCard(for:image:historyID:)` on macOS)
  with the **same History id** as the original, a **fresh thumbnail** (first frame, ≤ 640 px) and the
  normal corner / auto-dismiss settings. If the file no longer exists (thumbnail fails), no card.
- Opening the window from the **History** window's **Edit Video…** passes no callback: nothing is restored
  (there was no card).
- Only one trim window exists at a time. Opening a *different* file closes the current window first
  (which restores *its* card). Opening the *same* file again just brings the window forward; if that
  request came from another card of the same file, its restore is chained onto the window's close so
  both cards come back.

**macOS code.** `App/Recording/RecordingCoordinator.swift`: `presentTrim(url:restoreCard:)` (the
callback runs from the window's `onClosed`), `presentCard(for:image:historyID:)` (the card's `onTrim`
passes `restoreCard: { bringBackCard(for: url, historyID: historyID) }`), `bringBackCard(for:historyID:)`
(fresh thumbnail → `presentCard`). `TrimWindowController.onClosed` fires from `windowWillClose`, i.e. on
every close path including Save as Copy's own `close()`.

**Verified by** a headless probe (synthetic button clicks on a generated MP4): Cancel → restore ×1,
copy ×0 · close box → restore ×1 · Save as Copy → copy card ×1 **and** restore ×1 · Replace Original →
window stays open, Cancel reads "Done" → Done → restore ×1.

**Where it goes in the port.** The port has no trim window yet (it arrives with Part 6). Recording cards
are shown by `CaptureCoordinator.ShowRecordingCard(path, thumbnail, historyId)` in
`windows/src/BetterScreenshot.App/Capture/CaptureCoordinator.cs` (called from `OnRecordingFinished`);
`QuickAccessActions` (`windows/src/BetterScreenshot.App/Overlays/QuickAccessTypes.cs`) needs an optional
`OnTrim` (MP4 only), and the card's Trim button must dismiss with `DismissReason.ActionTaken` and then
open the editor with a `restoreCard` delegate that calls `ShowRecordingCard(path, freshThumb, historyId)`.

**Platform note.** The port's recording thumbnail today is a *screen grab taken at stop time*
(`RecordingCoordinator.CaptureThumb`), not a video frame. For the restored card after Replace Original,
extract the new first frame with ffmpeg instead:
`ffmpeg -v error -i "<file>.mp4" -frames:v 1 -vf "scale='min(640,iw)':-2" -y "<temp>.png"`.

---

## Part 1 — Editor side panel, hint line, zoom, tool shortcuts, opacity

**What changed, in one paragraph.** The annotation editor's one-row "inspector pill" under the toolbar
is gone. Its options now live in a **264pt dark side panel on the right** (the *inspector*) with titled
sections that change with the active tool and the selection. A one-sentence **hint line** above the
bottom action bar explains the active tool. The canvas can be **zoomed** (Fit … 800%). Every tool has a
**single-key shortcut**. Every object has an **opacity**. The Colour section keeps the last 6 custom
colours (**Recent**) and has an **eyedropper**. Any style change now applies to the **selected
object(s)** — not only to new objects — as one undo step. macOS code: `Packages/EditorKit/Sources/EditorKit/`
(`EditorWindowController.swift`, `EditorInspectorView.swift`, `InspectorModel.swift`, `EditorZoom.swift`,
`ZoomMath.swift`, `RecentColors.swift`, `EditorTool.swift`, `EditorChrome.swift`, `Annotation.swift`).

Snapshots from the headless probe (synthetic screenshot, Retina): `docs/parity-v3/part1-arrow-tool.png`
(Arrow tool, Fit), `docs/parity-v3/part1-select-text.png` (Select tool, one text selected),
`docs/parity-v3/part1-min-width-text-tool.png` (minimum window width, Text tool — panel scrolls).

### 1.1 Layout (exact, as built)

```
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●  Annotate                                                            ↶  ↷    ▯▮        │ ← title bar: Undo, Redo, 10pt gap, panel toggle
│            ┌─────────────────────────────────────────────────────┐   ┌──────────────────────┐ │
│            │ ↖ │ ↗ ╱ ▭ ■ ◯ │ Aa ① │ 💧 ▦ │ ⌗ │                    │   │ Arrow                │ │ ← heading
│            └─────────────────────────────────────────────────────┘   │                      │ │
│  ┌──────────────────────────────────────────────────────────────┐    │ COLOUR               │ │
│  │                                                              │    │ ● ● ● ● ● ● ● ●      │ │ ← 8 presets
│  │                                                              │    │ RECENT     ● ● ●     │ │ ← on preset columns 3–8; hidden if empty
│  │                 canvas (centred, Fit by default)             │    │ CUSTOM [▬] [⌖ Pick from Screen] ← colour well + eyedropper
│  │                                                              │    │ ──────────────────── │ │
│  │                                                              │    │ STROKE               │ │
│  │                                                              │    │ Width   ──●──── 4 px │ │
│  │                                                              │    │ [Thin|Medium|Thick]  │ │
│  │                                                              │    │ ──────────────────── │ │
│  │                                                              │    │ Opacity ──────● 100% │ │ ← no caption
│  │                                                              │    │ ──────────────────── │ │
│  │                                                              │    │ [Front][Back][Delete]│ │ ← Arrange footer (Select + selection)
│  └──────────────────────────────────────────────────────────────┘    └──────────────────────┘ │
├──────────────────────────────────────────────────────────────────────────────────────────────┤
│ ⓘ Drag to draw an arrow — it points to where you let go.                                      │ ← hint line
│ [Fit · 100% ⌄]  1600 × 1000 px                          [Done]  [Stack]  [Save]  [Copy]      │ ← action row
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Window.** Title "Annotate", transparent title bar, **always dark** (`NSAppearance.darkAqua`, whatever the system
appearance — the vibrant-dark panels wash out over a light window). Minimum size **884 × 440** while the panel is
shown (600 canvas column + 8 gap + 264 panel + 12 margin), **600 × 440** while it is hidden. Initial content size:
`width = min(max(imageW' + 48, 600) + 264 + 20, screenW − 40)`, `height = min(max(imageH' + 112 + 64, 660),
screenH − 60)`, where `imageW' = min(image width in points, 1200)` — points = pixels ÷ the main screen's backing
scale (2 on Retina), i.e. the capture's real on-screen size — and `imageH'` keeps the aspect ratio; screen = the
main screen's visible area. Backdrop behind the canvas: white 12%.

**Tool pill** (unchanged look): top 12pt from the content top, **centred over the canvas column** (not the
window). Dark HUD (`NSVisualEffectView` `.hudWindow`, vibrant dark), corner radius 15, 1px border white 10%,
6pt padding. Buttons 38×38, SF Symbol 16pt medium, 3pt apart; selected = accent-colour rounded rect
(radius 9, inset 2), hover = white 13%. Groups separated by 1×22pt lines (white 13%):
`[Select] | [Arrow, Line, Rectangle, Filled Rectangle, Ellipse] | [Text, Counter] | [Blur, Pixelate] | [Crop]`.
Tooltips are now **"<Name> (<Key>)"**, e.g. "Arrow (A)", "Filled Rectangle (F)" (the Text tooltip's long
instruction moved to the hint line).

| Tool | SF Symbol | Port icon (`Icons.xaml`) | Key | Tooltip |
|---|---|---|---|---|
| Select | `cursorarrow` | `icon-cursor` | V | Select (V) |
| Arrow | `arrow.up.right` | `icon-arrow` | A | Arrow (A) |
| Line | `line.diagonal` | `icon-line` | L | Line (L) |
| Rectangle | `rectangle` | `icon-rect` | R | Rectangle (R) |
| Filled Rectangle | `rectangle.fill` | `icon-rect-fill` | F | Filled Rectangle (F) |
| Ellipse | `circle` | `icon-ellipse` | O | Ellipse (O) |
| Text | `textformat` | `icon-text` | T | Text (T) |
| Counter | `1.circle.fill` | `icon-counter` | N | Counter (N) |
| Blur | `drop.fill` | `icon-blur` | B | Blur (B) |
| Pixelate | `square.grid.3x3.fill` | `icon-pixelate` | P | Pixelate (P) |
| Crop | `crop` | `icon-crop` | C | Crop (C) |

(Part 3 will add Highlighter = H and Spotlight = S.)

**Canvas column.** A scroll view from 6pt below the tool pill down to the bottom bar, from the window's left
edge to 8pt left of the panel (to the window's right edge when the panel is hidden). Content insets
top 20 / left 24 / bottom 24 / right 24. The canvas is centred when smaller than the visible area.

**Side panel** (`EditorInspectorView`). 264pt wide; top 12pt below the content top, 12pt from the right
edge, bottom 12pt above the bottom bar. Same HUD look as the pill: `.hudWindow`, vibrant dark, corner
radius **12**, 1px border white 10%.
- **Heading:** 13pt semibold, white 92%, 14pt from the top, 16pt from the left; single line, truncates.
  Text: the tool name (table above); under Select: **"Nothing selected"**, the object's tool name
  ("Text", "Arrow"…), or **"N objects"** (e.g. "2 objects").
- **Sections** start 10pt below the heading, inside a vertical scroll area (overlay scroller, flashed once
  when the sections don't fit — e.g. Text at the minimum window height). Each section: padding 12 top /
  16 sides / 14 bottom, 8pt between rows, content width **232pt**. Caption = the section title in
  UPPERCASE, 10pt semibold, white 45%. Sections are separated by a 1px line (white 10%) inset 16pt each side.
- Row labels: 12pt regular, white 88%, in **one 56pt label column** for every labelled row (so all slider
  tracks start at the same x). Value readouts: 11.5pt monospaced digits, white 55%, right-aligned,
  40pt wide. Controls use the small control size (≈22pt tall); slider rows are 24pt tall.
- Sections holding a single slider (**Opacity**, Part 3's **Strength** and **Dim outside**) have **no
  caption**: the name is the row's label ("Opacity", "Strength", "Dim").
- Checkboxes are custom-drawn (`InspectorCheckbox`): a 14pt rounded box (radius 3.5) with a 1px white-55%
  outline and a white-6% fill when off, accent-filled with a white tick when on; 6pt gap; 12pt title, white 88%.
- **Arrange is a footer** (under Select with a selection): a 1px white-10% line inset 16pt, then 10pt, the
  Arrange row, 12pt bottom padding. It sits right under the last section when everything fits and stays
  pinned to the panel's bottom (the sections scroll above it) when they don't — so Delete never scrolls away.

Section contents (top to bottom, only the sections listed in §1.2 appear):

| Section (caption) | Rows (exact) |
|---|---|
| **Colour** | ① 8 preset swatches spread evenly across 232pt: Red `#FF453B` (1.00, 0.27, 0.23), Orange (1.00, 0.62, 0.04), Yellow (1.00, 0.84, 0.04), Green (0.19, 0.82, 0.35), Blue (0.04, 0.52, 1.00), Purple (0.75, 0.35, 0.95), White, Black — sRGB; each 22×22 hit area with a 16pt circle, 1px white-22% outline, tooltip = colour name; the current colour gets a 2px white ring (the swatches are 8pt apart, so they form an 8-column grid). ② "RECENT" caption (52pt wide = two swatch columns) + up to 6 swatches 8pt apart — on preset columns 3–8 — tooltip "Recent colour"; row hidden when there are none. ③ "CUSTOM" caption (52pt) · colour well 40×24 (tooltip "Custom colour — opens the colour picker") · 6pt · small rounded button **"Pick from Screen"** with SF `eyedropper` (tooltip "Eyedropper — click anywhere on screen to use that colour"). |
| **Stroke** | ① "Width" label (56pt) · slider 1…24 (whole px) · value "4 px". ② Segmented **Thin / Medium / Thick** = 2 / 4 / 7 px (tooltips "2 px", "4 px", "7 px"), equal widths, full row; no segment highlighted when the width is another value. |
| **Font** (Text) | Two rows. ① Font pop-up, the rest of the row (tooltip "Font"; long family names truncate): System, Rounded, Serif, Mono (each drawn in its own face), separator, every installed family · 8pt · size pop-up 84pt wide (tooltip "Font size"): 12, 14, 18, 24, 30, 36, 48, 64, 96 "pt" (+ the current size if it's another value). ② Emphasis toggles at the left (SF `bold`, `italic`, 28pt segments, tooltips "Bold", "Italic"; Part 2 adds underline/strikethrough) · alignment at the right, three 28pt segments (SF `text.alignleft`, `text.aligncenter`, `text.alignright`; tooltips "Align left", "Align centre", "Align right"). |
| **Background** (Text) | Checkbox **"Contrasting box behind the text"** (tooltip "A dark or light box, whichever stands out against the text colour") = today's auto-contrast chip, `textBackground`. *Part 2 replaces this section with None / Solid / Auto + colour, padding, radius.* |
| **Redaction** (Blur/Pixelate tools) | Segmented **Blur / Pixelate**, full width (tooltips "Blur (B)", "Pixelate (P)"); switches the active tool. *Part 3 adds Strength here.* |
| **Opacity** (no caption) | "Opacity" label (56pt) · slider 10…100 · value "100%" (tooltip "How see-through the object is"). |
| **Arrange** (Select with a selection; the footer, no caption) | Three equal small buttons, 6pt apart: **Front** (SF `arrow.up.to.line`, port `icon-bring-front`, tooltip "Bring to front ( ] )"), **Back** (`arrow.down.to.line`, `icon-send-back`, "Send to back ( [ )"), **Delete** (`trash`, `icon-trash`, "Delete (⌫)"). |
| *(note)* Crop | No caption. 12pt, white 62%: "Drag over the part of the image you want to keep. Undo (⌘Z) brings the rest back." |
| *(note)* Select, nothing selected | No caption: "Click an object on the image to change it here. Drag across empty space to select several." |

**Bottom bar** (64pt tall, standard header material, 1px separator line on top).
- **Hint line:** 9pt below the top, 16pt from the left, the full width: SF `info.circle` (12pt, tertiary label
  colour) + 6pt + the sentence (12pt, secondary label colour, truncates at the right; its tooltip is the whole
  sentence).
- **Action row:** 10pt above the bottom. Left (16pt in): **zoom pull-down** (small) · 12pt · image size
  "1600 × 1000 px" (12pt system font with tabular digits, secondary, tooltip "Image size"). Right (16pt in),
  8pt apart: **Done** (bordered, tooltip "Close the editor (⌘W)", ⌘W) · **Stack** (SF `square.stack`, tooltip
  "Keep in the bottom-right stack") · **Save** (SF `square.and.arrow.down`, ⌘S) · **Copy** (accent-filled, white
  text, SF `doc.on.doc`, ⇧⌘C). Copy stays the rightmost, primary button.

**Title bar, right side:** Undo (SF `arrow.uturn.backward`, tooltip "Undo (⌘Z)"), Redo
(`arrow.uturn.forward`, "Redo (⇧⌘Z)"), 10pt gap, **panel toggle** (SF `sidebar.right`, an on/off button,
tooltip "Hide Inspector (⌥⌘I)" when shown / "Show Inspector (⌥⌘I)" when hidden). Buttons 26×22, borderless,
in a title-bar accessory whose view is 106×22 (6pt left / 10pt right insets). macOS note: the accessory view's
frame must be given that size explicitly — at width 0 the buttons are laid out past the window edge.

### 1.2 Which sections show (pure `InspectorModel` — port 1:1)

Objects are described by **the tool that draws them** (arrow → Arrow, text → Text, …).

| Active tool | Selection | Heading | Sections |
|---|---|---|---|
| Arrow, Line, Rectangle, Ellipse | (any) | tool name | Colour · Stroke · Opacity |
| Filled Rectangle, Counter | (any) | tool name | Colour · Opacity |
| Text | (any) | Text | Colour · Font · Background · Opacity |
| Blur, Pixelate | (any) | tool name | Redaction |
| Crop | (any) | Crop | Crop note |
| Select | none | Nothing selected | Select note |
| Select | one object | its tool name | that object's sections (rows above; Blur/Pixelate objects have none) + **Arrange** |
| Select | several | "N objects" | only the sections **every** selected object has, in panel order, + **Arrange** |

Panel order is always: Colour, Stroke, Font, Background, Redaction, Opacity, Arrange.
Under a drawing tool the selection is the object just drawn with it, so its sections are the tool's.

### 1.3 Hint line — verbatim strings

| When | Sentence |
|---|---|
| Typing in a text (any tool) | Type your text — ↩ or Esc finishes it, ⇧↩ starts a new line. |
| Select, nothing selected | Click an object to select it, or drag across empty space to select several. |
| Select, one text | Drag to move it, drag a side handle to set the box width, or double-click to edit the text. |
| Select, one rectangle / filled rectangle / ellipse / blur / pixelate | Drag to move it, drag a handle to resize it, or press Delete to remove it. |
| Select, one arrow / line / counter | Drag to move it, or press Delete to remove it. |
| Select, several | Drag to move them together, or press Delete to remove them. |
| Arrow | Drag to draw an arrow — it points to where you let go. |
| Line | Drag to draw a straight line. |
| Rectangle | Drag to draw a rectangle outline. |
| Filled Rectangle | Drag to draw a solid rectangle that covers what's under it. |
| Ellipse | Drag to draw an ellipse. |
| Text | Click to type a label, drag to make a text box, or click existing text to edit it. |
| Counter | Click to place the next numbered step. |
| Blur | Drag over anything you want to hide — it's blurred when you let go. |
| Pixelate | Drag over anything you want to hide — it's pixelated when you let go. |
| Crop | Drag over the area to keep — everything outside is cut away (⌘Z undoes it). |

On Windows write Ctrl+Z for ⌘Z and Shift+Enter / Enter for ⇧↩ / ↩.

### 1.4 Behaviour

- **Style edits.** Every panel change is one *edit* of one field (e.g. "line width = 7"). It is applied to
  (a) the **default style** for new objects — which is also the persisted sticky default — and (b) **every
  selected object**, as **one undo step**. With nothing selected only the default changes (no undo step).
  A slider drag and one colour-picker session each merge into a single undo step (the step ends when the
  slider is released, the selection changes, or anything else changes the document). While a text is being
  typed the edit restyles the live text instead (committed with the text as one step).
- **Values shown** = the selection's style (the back-most selected object's) when something is selected,
  otherwise the default style.
- **Selection vs tools.** Choosing a drawing tool (button or key) **clears the selection** and commits any
  text being typed; choosing Select **keeps** it. A just-drawn object stays selected, so the panel restyles
  it right away. **Change:** a Counter click now selects the new badge too (it used to leave nothing selected).
- **Esc:** with a drawing tool → Select tool; with Select → clears the selection. (While typing text, Esc
  finishes the text as before.)
- **Tool keys** (table in §1.1) are single keys with no modifiers, case-insensitive, and do nothing while
  a text is being typed (the keys type into the text instead).
- **Opacity** 10–100% for every object except Blur/Pixelate (no Opacity section there). An object is drawn
  as **one layer** at that opacity, so where its own parts overlap (arrow shaft cap under the head, text
  over its background box) the tint does not double up. The live text editor shows the same opacity.
- **Recent colours:** only *custom* colours are recorded — colours set with the colour well or the
  eyedropper (the 8 presets are always visible). Newest first, no duplicates (equal at 8-bit precision),
  max 6. Clicking a Recent swatch applies it and moves it to the front. One colour-picker drag session adds
  **one** entry (each new colour from the same session replaces the front entry). Shared by all tools.
- **Eyedropper:** macOS `NSColorSampler` — a magnifier loupe; click anywhere on screen to take that colour
  (Esc cancels). The picked colour is applied and added to Recent.
- **Panel toggle:** title-bar button or ⌥⌘I. Hiding gives the canvas the full width (min width 600);
  showing it again grows the window to 884pt if it's narrower. The canvas re-fits. Not persisted.
- **Zoom** (`ZoomMath` + `CanvasZoomController`):
  - *Percent* is per **screen pixel**: 100% = one image pixel per physical screen pixel (on a 2× display
    that is 0.5pt per image pixel). The control shows **"Fit · 57%"** in Fit mode, else **"150%"**.
  - *Fit* (default; ⌘0) = the whole image inside the canvas column (minus the insets), but **never larger
    than 100%** — the capture's real on-screen size, so a screenshot never opens enlarged and soft (on Windows:
    one image pixel per device pixel, i.e. 1/DPI-scale DIPs per pixel). Fit re-fits whenever the window resizes,
    the panel toggles, or a crop/undo changes the image size.
  - Range: **min(Fit, 100%) … 800%**. ⌘+ (also ⌘=) / ⌘− step through **10, 25, 50, 75, 100, 150, 200,
    300, 400, 600, 800 %** (next stop above/below the current value). ⌘1 = 100%. Landing exactly on the Fit
    value switches back to Fit mode.
  - Trackpad **pinch** and **⌘ + scroll wheel** zoom continuously (pinch: ×(1 + magnification); wheel:
    ×e^(0.01·Δ), Δ = the precise scroll delta, or 12× the line delta for a notched mouse wheel ≈ 13% per
    notch), **anchored on the pointer**: the image point under the pointer stays under the pointer. Keys and
    the menu anchor on the centre of the visible area. Plain scrolling pans.
  - Zoom pull-down menu: "Zoom In ⌘+", "Zoom Out ⌘−", —, "Fit to Window ⌘0", "Actual Size (100%) ⌘1", —,
    "50%", "200%", "400%", "800%". Tooltip: "Zoom — pinch, ⌘-scroll, ⌘+ / ⌘−, ⌘0 fits, ⌘1 is 100%".
  - At ≥ 3 screen pixels per image pixel the image is drawn with nearest-neighbour sampling (crisp pixels).
  - Everything works at any zoom: drawing, hit-testing, 8pt resize handles (screen-sized, not image-sized),
    marquee, crop, and the live text editor (it moves and rescales with the zoom while you type).

### 1.5 Data

| Key / field | Type & default | Legacy rule |
|---|---|---|
| `AnnotationStyle.opacity` (JSON key `opacity`, inside the `editorDefaultStyle` blob) | number 0.1…1, default **1** | missing → 1; decoded values are clamped to 0.1…1 |
| `editorRecentColors` (UserDefaults, JSON array of `{"r","g","b","a"}` 0…1 sRGB) | newest first, ≤ 6, default `[]` | missing/corrupt → `[]` |
| `AnnotationStyle.strokeColor` / `fillColor` (inside `editorDefaultStyle`) | default = the **Red swatch** (1, 0.27, 0.23), fill the same at alpha 0.25 (`AnnotationStyle.defaultRed`) | the old default red (1, 0.23, 0.19) — equal at 8-bit precision, any alpha — decodes as (1, 0.27, 0.23) at that alpha, so the Red swatch shows as selected. Tests: defaultRedIsThePresetRedSwatch · oldDefaultRedDecodesAsThePresetRed. |

Port: add `public double Opacity { get; init; } = 1;` to `AnnotationStyle` in
`windows/src/BetterScreenshot.Editor/EditorStyle.cs` (System.Text.Json leaves the initializer value when the
property is missing; clamp in the setter or after load), and an `EditorRecentColors` list to the DTO in
`windows/src/BetterScreenshot.Platform/SettingsStore.cs` next to `EditorDefaultStyle`.

### 1.6 Pure logic to port 1:1 (with the macOS tests)

- **`InspectorModel`** (`InspectorModel.swift`) — `objectSections(for:)`, `toolSections(for:)`,
  `content(tool:selection:)` → heading + sections, `hint(tool:selection:editingText:)`; section titles and
  note texts. Tests (`Tests/EditorKitTests/InspectorModelTests.swift`): strokeToolsShowColourStrokeOpacity ·
  filledRectangleAndCounterShowColourOpacity · textShowsColourFontBackgroundOpacity · redactionAndCropTools ·
  drawingToolIgnoresItsSelectionForSections · selectWithNothingSelected · selectWithOneObjectShowsItsSectionsPlusArrange
  (text → Colour, Font, Background, Opacity, Arrange; blur → Arrange) · selectWithSeveralShowsSharedSectionsPlusArrange
  (arrow+text → Colour, Opacity, Arrange, heading "2 objects"; arrow+rectangle adds Stroke; arrow+pixelate → Arrange) ·
  sectionsKeepPanelOrder · hintsCoverEveryToolAndState.
- **`EditorTool` metadata** (`EditorTool.swift`) — display name, symbol, shortcut key, tooltip "Name (K)",
  `forShortcut` (single character, case-insensitive), `maker(of:)` (annotation → tool). Tests:
  toolShortcutsAreUniqueAndCaseInsensitive ("z" and "ab" → none; tooltips "Arrow (A)", "Filled Rectangle (F)") ·
  everyAnnotationTypeMapsToItsTool.
- **`RecentColors`** (`RecentColors.swift`) — `add(color, replacingFront:)`, `same(a, b)` at 8-bit precision,
  capacity 6; `init(list)` dedupes and keeps order. Test: recentColoursAreMostRecentFirstUniqueAndCapped.
- **`ZoomMath`** (`ZoomMath.swift`) — percent ↔ magnification, `fitMagnification(imageSize, available,
  backingScale)` (capped at 100%), `pointSize(pixels, backingScale)` = pixels ÷ scale (scale < 1 treated as 1),
  `clamp`, `steppedPercent`,
  `isFit` (within 0.5%), `anchoredOrigin(anchor, visibleOrigin, from, to)` = `anchor·k − (anchor − origin)`,
  `k = new/old`, `label`. Tests (`zoomMathTests`): percentIsPerScreenPixel (m 0.5 @2× = 100%) ·
  fitCoversBothDimensionsAndNeverUpscalesPastOneHundredPercent (@1×: 2000×1000 in 1000² → 0.5, 200×100 → 1;
  @2×: 1000×3000 in 1000×600 → 0.2, 360×225 → 0.5 = 100%, 1600×1000 in 920×577 → 0.5) ·
  pointSizeIsTheCapturesRealOnScreenSize (1600×1000 px @2× → 800×500 pt; @1× → 1600; scale 0 → unchanged) ·
  clampRangeIsFitToEightHundred (@2×: 10 → 4, 0.1 → fit 0.3, fit 1 lets 0.5
  through) · stepsWalkTheStopTable (100→150, 57→75 / 50, 800 stays, 10 stays) ·
  anchoredZoomKeepsThePointUnderThePointer ((300,200) with origin (100,50), 1→2 → origin (400,250), and back) ·
  labels ("Fit · 57%", "150%").
- **Opacity** — tests (`OpacityTests.swift`): opacityDefaultsToOpaque · legacyStyleWithoutOpacityDecodesOpaque ·
  opacityRoundTripsAndClampsOnDecode (0 → 0.1) · halfOpacityFilledRectBlendsWithBase (red 50% on white →
  G,B ≈ 128) · translucentArrowDoesNotDoubleUpWhereShaftMeetsHead (12px arrow (20,50)→(80,50): pixel (51,50)
  equals the shaft's (35,50)) · canvasDrawsWithOpacityToo.
- **Style edits on the selection** — tests (`CanvasStyleEditTests.swift`): styleEditRestylesTheSelectionAsOneUndoStep ·
  groupedEditsMergeUntilTheGroupEnds · editWithNothingSelectedLeavesTheDocumentAlone ·
  selectionIsDescribedByTheToolsThatDrawIt.

### 1.7 Where it goes in the port

- `windows/src/BetterScreenshot.App/Editor/EditorWindow.xaml` — today a `DockPanel` with the toolbar +
  horizontal `Inspector` StackPanel on top, buttons at the bottom and a `Viewbox` canvas. Becomes: top band
  with the tool pill centred over the canvas column; a right-docked 264px panel; a bottom bar with the hint
  line and the action row (image size · zoom drop-down · Done/Stack/Save/Copy); the canvas in a
  `ScrollViewer` (the `Viewbox Stretch="Uniform"` can't zoom or scroll — size the `Stage` grid explicitly:
  image px × magnification, like the Mac canvas frame).
- `windows/src/BetterScreenshot.App/Editor/EditorWindow.xaml.cs` — `BuildInspector`/`RefreshInspector`/
  `SetColor`/`SetWeight`/`SetSize` move into a new panel `UserControl` (e.g. `Editor/EditorInspectorPanel.xaml`)
  driven by `InspectorModel`; `OnKeyDown` gains the tool keys, Esc and the zoom keys; `SelectTool` clears the
  selection for drawing tools; tool tooltips become "Name (K)".
- `windows/src/BetterScreenshot.Editor/` — new `InspectorModel.cs`, `ZoomMath.cs`, `RecentColors.cs`;
  `EditorTool.cs` gains name / key / `ForShortcut` / `MakerOf` helpers; `EditorStyle.cs` gains `Opacity`.
- `windows/src/BetterScreenshot.App/Editor/DocumentRenderer.cs` — wrap each annotation's drawing in
  `DrawingContext.PushOpacity(style.Opacity)` … `Pop()` (WPF composites a pushed opacity as one layer, the
  same as the Mac transparency layer); the canvas preview must do the same.
- `windows/src/BetterScreenshot.Platform/SettingsStore.cs` — `EditorRecentColors`.
- `windows/src/BetterScreenshot.App/Resources/Icons.xaml` — existing keys cover the tools, `icon-undo`,
  `icon-redo`, `icon-bring-front`, `icon-send-back`, `icon-trash`, `icon-stack`, `icon-save`, `icon-copy`;
  **new icons needed:** eyedropper, info (hint line), panel toggle (sidebar-right), bold, italic,
  align-left / centre / right.
- Tests: `windows/tests/BetterScreenshot.Tests/` — recreate the cases in §1.6 (next to `EditorStyleTests.cs`).

### 1.8 Platform notes (Windows)

- **Modifier keys:** ⌘ → Ctrl throughout (Ctrl+= / Ctrl+− / Ctrl+0 / Ctrl+1, Ctrl+Z, Ctrl+Shift+Z / Ctrl+Y);
  ⌥⌘I → **Ctrl+Alt+I**. Tool keys must be ignored when the focused element is the text-editing `TextBox`
  (`e.OriginalSource is TextBox`).
- **Pinch:** precision touchpads deliver pinch to classic apps as **Ctrl + mouse wheel**, so handling
  `PreviewMouseWheel` with Ctrl covers both pinch and Ctrl+wheel; anchor on `e.GetPosition(stage)`. Plain
  wheel scrolls the `ScrollViewer`; Shift+wheel pans horizontally.
- **100%** = one image pixel per *physical* pixel: magnification = 1 / (monitor DPI ÷ 96)
  (`VisualTreeHelper.GetDpi(window).DpiScaleX`). Use `RenderOptions.BitmapScalingMode="NearestNeighbor"`
  on the image at ≥ 300%.
- **Colour well:** WPF has no built-in colour picker — use `System.Windows.Forms.ColorDialog` (or a
  custom popup) behind a 44×24 swatch button; a dialog is one "session" → one Recent entry, one undo step.
- **Eyedropper:** no system sampler on Windows. Show a full-screen, top-most transparent overlay over a
  `Graphics.CopyFromScreen` snapshot with a small magnifier by the cursor; click takes the pixel, Esc cancels.
- **Opacity:** `DrawingContext.PushOpacity` (renderer) / `UIElement.Opacity` on the preview shapes and on the
  text-editing `TextBox`.


---

## Part 2 — Text v2 (corner scaling, background, outline, presets)

**What changed, in one paragraph.** A selected text now has **corner handles that scale the whole text**
(font size, box width, box padding / corner radius, outline width — like scaling an image) besides the side
handles that set the box width. The old "contrasting box" checkbox became a real **Background** with three modes
— **None / Solid / Auto** — a box colour, **Padding** and **Corners**. Text also gets **Underline**,
**Strikethrough**, an **Outline** (colour + width) and a **Shadow**, and six one-click **style presets** (Label,
Callout, Note, Code, Title, Subtle) at the top of the Text panel. While typing, the box and outline show behind the
text so it looks like the result. **Prerequisites in the port:** §A.1 (fonts, `wrapWidth` text boxes, the growing
inline editor) and Part 1 (the side panel) — Part 2 builds on both. macOS code (`Packages/EditorKit/Sources/EditorKit/`):
`AnnotationStyle.swift`, `TextAnnotation.swift`, `TextChip.swift`, `TextScale.swift`, `TextStylePreset.swift`,
`EditorCanvasView.swift` (handles, live box), `EditorInspectorView.swift` (sections), `EditorChrome.swift`
(`TextPresetChip`, `LabeledSliderRow(labelWidth:)`), `InspectorModel.swift`.

Snapshots from the headless probe (synthetic screenshot, Retina): `docs/parity-v3/part2-selected-text.png` (Select
tool, one text with a Solid box + outline + underline selected — note the 6 handles), `docs/parity-v3/part2-panel-text-tool.png`
(Text tool, default style — Background None, Outline off), `docs/parity-v3/part2-panel-solid-box.png` (Background
Solid: box palette, Recent, well, Padding, Corners), `docs/parity-v3/part2-panel-effects.png` (panel scrolled to
the bottom in a short window: Outline on with its Width row, Shadow on, Opacity, Arrange),
`docs/parity-v3/part2-rendered-results.png` (exported pixels: every preset, outline on a busy strip, shadow alone and
under a box, underline, strikethrough, Auto box, a 16 px / 40 px "pill").

### 2.1 Layout (exact, as built)

Text sections, top to bottom: **Styles · Colour · Font · Background · Effects · Opacity** (+ **Arrange** under
Select). The panel-wide order is now: Styles, Colour, Stroke, Font, Background, Effects, Redaction, Opacity, Arrange.
Everything else about the panel (264 pt, 232 pt content column, captions, 8 pt row gap, hairlines) is as in §1.1.

```
┌──────────────────────────────┐
│ Text                         │ ← heading (tool / selection name, §1.2)
│ STYLES                       │
│ [ Label ] [Callout] [ Note ] │ ← 3 chips per row, equal width (72 pt), 28 pt tall, 8 pt apart
│ [ Code  ] [ Title ] [Subtle] │    each drawn as a preview of its look; active one ringed
│ ──────────────────────────── │
│ COLOUR   (unchanged, §1.1)   │
│ ──────────────────────────── │
│ FONT                         │
│ [System        ⌃⌄] [24 pt ⌃⌄]│ ← family (rest of the row) + size 84 pt
│ [B|I|U|S]          [≡ |≡ |≡ ]│ ← four 28 pt toggles left, three 28 pt alignments right
│ ──────────────────────────── │
│ BACKGROUND                   │
│ [  None  | Solid |  Auto  ]  │ ← full width, equal segments
│ ● ● ● ● ● ● ● ●              │ ← Solid only: box palette (Black = 80 %)
│ CUSTOM [▬] [⌖ Pick from Screen] ← Solid only: box colour well + eyedropper (no Recent row)
│ Dark or light — whichever …  │ ← Auto only (note)
│ Padding ─────●────── 6 px    │ ← Solid and Auto
│ Corners ───●──────── 4 px    │ ← Solid and Auto
│ ──────────────────────────── │
│ EFFECTS                      │
│ ☑ Outline [▬]      ☐ Shadow  │ ← outline checkbox + its colour well; Shadow at the right
│ Width   ──●──────── 3 px     │ ← only while Outline is on (same label column, not indented)
│ ──────────────────────────── │
│ Opacity ──────────●  100%    │ ← (as §1.1, no caption)
│ ──────────────────────────── │
│ [Front] [Back] [Delete]      │ ← Arrange footer, under Select (§1.1)
└──────────────────────────────┘
```

| Section (caption) | Rows (exact) |
|---|---|
| **Styles** | Two rows of three `TextPresetChip`s, `fillEqually`, 8 pt apart; each 28 pt tall. Chip drawing: rounded rect (radius 6) inset 1.5 pt; fill = the preset's box colour, or white 6 % for presets without a box (Title, Subtle); border 1 px white 16 %; **active** (the current style already has that look, `TextStylePreset.isApplied`) = 2 px accent-colour border; hover = white 10 % overlay. Label = the preset's name, centred, in the preset's font family and weight at 12 pt (Title: 15 pt), in the preset's text colour (Title keeps the user's colour, so its chip label is white 92 %). Tooltips: "Label — bold white text on a black box", "Callout — bold white text on a red box", "Note — black text on a yellow box", "Code — light monospaced text on a dark box", "Title — 48 pt bold, no box (keeps the colour)", "Subtle — 18 pt regular grey, no box". |
| **Font** | As §1.1, except the emphasis group in row ② has **four** segments (select-any, 28 pt each): SF `bold`, `italic`, `underline`, `strikethrough`; tooltips "Bold", "Italic", "Underline", "Strikethrough". |
| **Background** | ① Segmented **None / Solid / Auto**, full width, equal segments; tooltips "No box behind the text", "A box in the colour you pick below", "A dark or light box, whichever stands out against the text colour". ② *(Solid only)* two of the Colour section's rows, editing the **box** colour: 8 swatches with the same colours and names except the last is **black at 80 % alpha**, tooltip "Black (80%)"; then "CUSTOM" + a second colour well 40×24 (tooltip "Custom box colour — opens the colour picker") + "Pick from Screen" — **no RECENT row** here, to keep the Text panel short (same tooltip as §1.1; the picked colour becomes the box colour — handy for covering old text with the page's own colour). ③ *(Auto only)* note, 12 pt white 62 %: "Dark or light — whichever stands out against the text colour." ④ *(Solid and Auto)* slider row "Padding" (label 56 pt wide), 0…40 whole px, value "6 px", tooltip "Space between the text and the edge of the box". ⑤ *(Solid and Auto)* slider row "Corners" (label 56 pt), 0…40 whole px, value "4 px", tooltip "How rounded the box's corners are". Hidden rows take no space. |
| **Effects** | ① One row: checkbox **"Outline"** (12 pt, white 88 %; tooltip "An edge around every letter — keeps text readable on busy screenshots") · 6 pt · outline colour well 40×24 (tooltip "Outline colour — picking one turns the outline on") · flexible space · checkbox **"Shadow"** (tooltip "A soft drop shadow under the text (and its box)"). ② *(only while Outline is on)* slider row, not indented: "Width" (56 pt label column), 1…20 whole px, value "3 px", tooltip "Outline thickness in image pixels". |

**Outline colour follows the text colour** (`TextChip.outlineColor(current, forText:)`, pure). When the Outline is
switched on — and when the text colour changes while it is on — the outline colour is kept if its WCAG contrast
ratio with the text colour is **≥ 3:1** (`TextChip.minOutlineContrast`), otherwise it becomes black or white,
whichever contrasts more with the text. (WCAG contrast = (L1 + 0.05) / (L2 + 0.05) of the two colours' relative
luminances, sRGB gamma-expanded; alpha ignored.) So ticking Outline on white Label / Callout text gives a black
outline, while red text keeps the default white one (≈ 3.4:1). A colour picked in the outline well is used as is.
Tests (`TextChipTests.swift`): contrastRatioIsWCAG (white/black 21; preset red vs white ≈ 3.4, vs black ≈ 6.2) ·
outlineContrastsWithTheTextColour (white on white → black, white on yellow → black, black on black → white; kept:
white on red, blue on white, black on white).

**Canvas handles** (`TextHandles`, pure). A single selected text shows the four corners (**scale**) as **round**
handles (9 pt circles, white fill, 1 px blue border) centred **4 pt outside** each corner of the box, so they never
cover the letters; and middle-left / middle-right (**box width**) as **bars** (4 pt wide, height = min(16, box
height − 5) pt, fully rounded) centred 4 pt outside the left/right edges — **left out when shorter than 6 pt** (a
one-line text zoomed out), so they never overlap the corners. Top-/bottom-middle are not shown. All in view points
(screen-sized at any zoom). Hit areas: +2 pt around each handle, at least 10 pt wide for the bars; corners are
tested first. Other shapes keep the 8 square 8×8 handles on their frame. All handles and the dashed selection
outline sit on the **box** (text + padding) when the text has a background. Tests (`TextHandlesTests.swift`):
textCornersSitOutsideTheBoxAndSidesClearThem · sideBarsShrinkThenDisappearOnShortTexts (17 pt box → 12 pt bars;
6 pt box → corners only).

**While typing**, a dashed frame (1 px system blue, dash 4/3, 3 pt outside) surrounds the live text — its box when it
has one — so it is clear the text is being edited.

**Hint line** (§1.3) — one sentence changed: *Select, one text* → "Drag to move it, drag a corner to resize the
text, drag a side to change the box width, or double-click to edit."

### 2.2 Behaviour

- **Corner scaling** (`TextScale` + `TextAnnotation.scaled(dragging:by:)`), always computed from the text as it was
  at mouse-down (never incrementally), with `drag` = pointer − mouse-down point in image px (so grabbing a handle
  slightly off its centre doesn't jump):
  1. `box` = the text's bounding box (incl. background padding); `A` = the corner opposite the dragged one (fixed);
     `C` = the dragged corner; `d = C − A`.
  2. `factor = ((C + drag − A) · d) / (d · d)` — the drag projected onto the diagonal (moving across the diagonal
     does nothing; past `A` gives ≤ 0). A zero-size box → factor 1.
  3. `newSize = clamp(round(fontSize × factor), 8, 400)`; `k = newSize / fontSize` (the factor actually applied).
  4. `wrapWidth × k` (nil stays nil — a free label stays free, so line breaks stay put), `padding × k` clamped
     0…40, `cornerRadius × k` clamped 0…40, `outlineWidth × k` clamped 1…20. Nothing else changes.
  5. Place the result so its new bounding box's corner opposite the dragged one is exactly at `A`
     (`TextScale.placed(size:anchor:corner:)`), by shifting `origin`.
  - The panel's size pop-up follows **live** during the drag (it lists the current size, e.g. "37 pt", when it
    isn't a preset size). The whole drag is **one undo step**. Works at any zoom (all maths in image px). The drag
    changes only that object, not the sticky default style.
- **Side handles** set `wrapWidth` = dragged box width − 2 × padding (minimum = the font size in px); the text's
  x origin = box left + padding. With no background, padding = 0 (exactly §A.1).
- **Background geometry:** box = the text's layout rect expanded by `padding` left/right and `padding / 2`
  top/bottom (the line box already includes leading; 6 → 6 × 3 = the pre-v3 chip exactly). Corner radius =
  `min(radius, boxW / 2, boxH / 2)`. One box around all lines. **Solid** fills `textBackgroundColor`; **Auto** fills
  `#18181A` behind light text or `#F4F4F6` behind dark text, decided at draw time from the text colour's luminance
  `0.2126 R + 0.7152 G + 0.0722 B > 0.5` (so it follows colour changes automatically).
- **Bounding box** (selection outline, handles, hit-testing, marquee, keep-on-canvas while moving) = the box when
  there is one, else the text's layout rect.
- **Draw order:** (shadow layer begins) → box → outline pass → letters (→ shadow layer ends); the whole thing then
  goes through the object's opacity layer (§1.4). *Outline pass* = the same text stroked (not filled) in the outline
  colour with a pen of **2 × outline width** and **round joins**, then the normal letters on top — so the visible
  edge is outline-width wide and sits outside the letters. *Underline / strikethrough* are normal single text
  decorations in the text colour (not outlined).
- **Shadow** (fixed, no settings): black 45 %, offset **straight down** by `max(1, 0.05 × fontSize)` px, blur
  `max(2, 0.15 × fontSize)` px (24 pt → 1.2 px down, 3.6 px blur). Box + outline + letters cast **one** shadow as a
  group, so a boxed text's shadow falls from the box. It scales with the text.
- **While typing** (inline editor): the canvas draws the box and outline (and their shadow) behind the text field at
  the field's width; the field draws the letters (with underline/strikethrough, which are text attributes). Known
  small difference: a shadow on *plain* text (no box, no outline) appears only once the text is committed.
- **Presets** (`TextStylePreset.apply`) set only these fields, and apply to the selected text(s) and the default style
  as **one undo step** like any style edit. All presets also switch off italic, underline, strikethrough, outline and
  shadow. They never touch alignment, opacity, line width or box width.

  | Preset | Text colour (sRGB) | Size | Font / weight | Background |
  |---|---|---|---|---|
  | Label | white (1, 1, 1) | kept | System, bold | Solid (0, 0, 0, 0.8), padding 6, corners 4 |
  | Callout | white | kept | System, bold | Solid (1, 0.27, 0.23, 1), padding 8, corners 6 |
  | Note | black (0, 0, 0) | kept | System, regular | Solid (1, 0.84, 0.04, 1), padding 8, corners 2 |
  | Code | (0.90, 0.92, 0.95) | kept | Mono (`System Mono`), regular | Solid (0.12, 0.13, 0.15, 1), padding 6, corners 4 |
  | Title | **kept** | **48** | System, bold | None |
  | Subtle | (0.56, 0.56, 0.58) | **18** | System, regular | None |

  Setting a text colour also sets `fillColor` = that colour at alpha 0.25 (same as a colour swatch). Note: the editor
  has **one** sticky style shared by all tools (Part 1), so a preset's text colour also becomes the next arrow's
  colour — same as picking a colour while the Text tool is active.
- **Colour wells:** the box well and the outline well behave like the Colour well (§1.4): each picked colour goes into
  Recent (one entry per colour-panel session), and a session is one undo step. **Picking an outline colour turns the
  outline on.** Clicking a box swatch or Recent swatch in the Background section sets only the box colour.
- **Hidden-row rules:** Background colour rows only in Solid; the Auto note only in Auto; Padding/Corners in Solid
  and Auto; Outline Width only while Outline is on.

### 2.3 Data

All inside the sticky `AnnotationStyle` JSON (`editorDefaultStyle`); every key is optional when decoding and missing
keys give today's look.

| JSON key | Type & default | Legacy / decode rule |
|---|---|---|
| `textBackgroundMode` | `"none"` \| `"solid"` \| `"auto"`, default `"none"` | Missing or unknown → read the old macOS Bool `textBackground`: `true` → `"auto"`, else `"none"`. The Bool is no longer written. |
| `textBackgroundColor` | `{"r","g","b","a"}`, default (0, 0, 0, **0.8**) | — |
| `textBackgroundPadding` | number (image px), default **6** | clamped to 0…40 |
| `textBackgroundCornerRadius` | number, default **4** | clamped to 0…40 |
| `textUnderline`, `textStrikethrough` | bool, default false | — |
| `textOutline` | bool, default false | — |
| `textOutlineColor` | colour, default white (1, 1, 1, 1) | — |
| `textOutlineWidth` | number (image px), default **3** | clamped to 1…20 |
| `textShadow` | bool, default false | — |

**Port mapping for its existing `TextBackground: RGBAColor?`** (`windows/src/BetterScreenshot.Editor/EditorStyle.cs`):
the port's UI only ever stores its auto chip there (`EditorWindow.xaml.cs` `ToggleTextBackground` / `SetColor` →
`AutoChip(strokeColor)`), so it means **Auto**. Add the new properties (`TextBackgroundMode`, enum
`None/Solid/Auto` serialised as the lower-case strings above, `TextBackgroundColor`, `TextBackgroundPadding`,
`TextBackgroundCornerRadius`, `TextUnderline`, `TextStrikethrough`, `TextOutline`, `TextOutlineColor`,
`TextOutlineWidth`, `TextShadow`) with the defaults above, and keep `TextBackground` as a **read-only legacy**
property (`[JsonPropertyName("textBackground")]`, `JsonIgnoreCondition.WhenWritingNull`, never set by new code).
After deserialising: if `textBackgroundMode` was absent → `TextBackground != null ? Auto : None`; leave
`TextBackgroundColor` at its default (don't copy the old chip colour — it was an auto colour, not a user choice). Then
delete `AutoChip` and the chip recompute in `SetColor`: Auto is computed at draw time with the macOS colours and
luminance formula (§2.2), replacing the port's `(1,1,1,0.92)` / `(0,0,0,0.6)` chips.

### 2.4 Pure logic to port 1:1 (with the macOS tests)

- **`TextScale`** (`TextScale.swift`): `point(of:in:)`, `anchor(of:in:)`, `factor(box:corner:by:)`,
  `scaled(style, wrapWidth:, by:)`, `placed(size:anchor:corner:)`, and `TextAnnotation.scaled(dragging:by:)`.
  Tests (`Tests/EditorKitTests/TextScaleTests.swift`): draggingACornerAlongTheDiagonalScalesProportionally (box
  (100,100,200,50): BR by (200,50) → 2; TR by (200,−50) → 2; BL by (−200,50) → 2; TL by (−200,−50) → 2; TL by
  (100,25) → 0.5) · dragAcrossTheDiagonalDoesNotScale ((0,0,200,50), BR by (−50,200) → 1; zero box → 1) ·
  scaledRoundsTheFontAndScalesTheRestByTheSameFactor (24 pt × 1.55 → 37; box 240, padding 6, radius 4, outline 3 all
  × 37/24; nil width stays nil) · scaledClampsTheFontTo8Through400 (× 100 → 400; × 0.01 → 8 with box 120 → 40;
  × −3 → 8) · scaledKeepsPaddingRadiusAndOutlineInTheirRanges (10 pt, padding 30, radius 30, outline 2, × 10 → 40, 40,
  20; outline 1 × 0.8 → 1) · placedKeepsTheOppositeCornerFixed (80×30 at anchor (100,100): BR → (100,100); TL →
  (20,70); TR → (100,70); BL → (20,100); anchor of TL in (10,20,30,40) = (40,60), of BL = (40,20)) ·
  cornerDragScalesATextAndKeepsTheOppositeCorner ("Hello world" box width 200 at (100,100): BR by (w,h) → 48 pt, width
  400, top-left unchanged, same id; TL by (w/2,h/2) → 12 pt, bottom-right unchanged) · cornerDragKeepsLineBreaks
  (3-line box at width 150, × 2 → height ratio 1.9…2.1) · cornerDragAnchorsTheBoxBehindTheText (Solid box, TL by
  (−w,−h) → bottom-right of the box unchanged, padding 12).
- **`TextStylePreset`** (`TextStylePreset.swift`): `displayName`, `tooltip`, `apply(to:)`, `isApplied(to:)` (= applying
  it changes nothing). **`TextChip`**: `autoColor(forText:)`, `insets(padding:)` = (p, p/2).
  Tests (`TextStyleTests.swift`): textV2FieldsDefaultToTodaysLook · legacyStyleWithoutTextV2KeysDecodesToTheDefaults ·
  legacyTextBackgroundBoolMapsToAutoOrNone · backgroundModeWinsOverTheLegacyBool (unknown mode string → falls back to
  the Bool) · textV2FieldsRoundTrip · decodeClampsPaddingRadiusAndOutlineWidth (−5 → 0, 999 → 40, 0 → 1) ·
  autoBoxContrastsWithTheTextColour (white text → dark box, black → light; insets(6) = 6×3) · presetsSetTheirLook ·
  presetsOnlyTouchTheTextLook (alignment, opacity, line width and — for Label — size kept; effects reset; Title keeps
  the colour) · presetsRoundTripAndAreRecognised (each preset: not active on the default style, active after applying,
  survives JSON, no other preset active).
- **Rendering** — tests (`TextRenderTests.swift`, white 300×120 base): solidBackgroundFillsTheBoxWithItsColour (pixel
  3 px inside the box's left edge is the chosen blue; 3 px outside is white) · autoBackgroundKeepsTheContrastingChip
  (white text → #18181A ± 3) · noBackgroundDrawsNoBox · boundingBoxIncludesTheBoxPadding (padding 10 → rect inset by
  (−10, −5), Solid and Auto) · paddingAndCornerRadiusShapeTheBox (padding 20 filled; radius 0 fills the corner pixel,
  radius 20 leaves it white) · outlineWidensTheInkInItsColour (4 px outline → ink ≥ 3 px wider each side and lower;
  red pixels at the new edge) · underlineAddsInkBelowTheBaseline ("ace") · strikethroughCrossesTheGapsBetweenLetters
  ("i  i  i": one ink row spans the whole text) · shadowFallsBelowTheText (48 pt "HH": ink extends further down than
  up) · canvasShadowFallsDownwardToo (same through the canvas at half size).
- **`InspectorModel`** updates (§1.6 tests renamed/extended): textShowsStylesColourFontBackgroundEffectsOpacity →
  `[styles, colour, font, background, effects, opacity]`; Select with one text → those + arrange; the one-text hint
  contains "corner".

### 2.5 Where it goes in the port

- `windows/src/BetterScreenshot.Editor/EditorStyle.cs` — the new properties + legacy rule (§2.3).
- `windows/src/BetterScreenshot.Editor/` — new `TextScale.cs`, `TextStylePreset.cs`, `TextChip.cs` (`AutoColor`,
  `Insets`); `Annotations.cs` `TextAnnotation`: bounding box includes the padded box, `Scaled(corner, drag)`.
- `windows/src/BetterScreenshot.App/Editor/DocumentRenderer.cs` — the `TextAnnotation` case: box (radius + padding
  from the style, Auto colour at draw time), outline pass, letters with decorations, shadow group (§2.6). Replace the
  fixed `TextChipPadX = 6` / `TextChipPadY = 2` with `Insets(padding)`.
- `windows/src/BetterScreenshot.App/Editor/EditorWindow.xaml.cs` — six handles for a text (hit-test corners first),
  the scale drag (snapshot the text at mouse-down; one `UndoHistory` entry on mouse-up; refresh the panel's size
  control during the drag), side handles minus padding; `PlaceTextBox`: wrap the `TextBox` in a `Border` with
  `CornerRadius` = radius and `Padding` = (p, p/2) filled with the Solid/Auto colour; delete `ToggleTextBackground`,
  `AutoChip` and the chip recompute in `SetColor`.
- The Part 1 panel `UserControl` (e.g. `Editor/EditorInspectorPanel.xaml`) — Styles, Background and Effects sections,
  B I U S toggles; `InspectorModel.cs` — the two new sections.
- `windows/src/BetterScreenshot.App/Resources/Icons.xaml` — **new icons:** underline, strikethrough (bold / italic
  were already listed in §1.7).
- Tests: `windows/tests/BetterScreenshot.Tests/` — recreate §2.4 next to `EditorStyleTests.cs`.

### 2.6 Platform notes (Windows / WPF)

- **Outline:** `FormattedText.BuildGeometry(origin)` gives the letters' geometry; draw it with
  `dc.DrawGeometry(null, new Pen(outlineBrush, 2 * width) { LineJoin = PenLineJoin.Round }, geometry)`, then draw the
  text normally on top (`dc.DrawText` or `DrawGeometry(fill, null, geometry)`). Check that the geometry includes the
  underline/strikethrough decorations; either way draw the normal decorations with the fill pass.
- **Underline / strikethrough:** `FormattedText.SetTextDecorations(TextDecorations.Underline)` /
  `TextDecorations.Strikethrough` (in the live `TextBox`: `TextBox.TextDecorations`).
- **Shadow:** `DrawingContext` has no shadow. Draw box + outline + letters into a `DrawingGroup`/`DrawingVisual`,
  give that visual a `DropShadowEffect { Color = Black, Opacity = 0.45, Direction = 270 (down), ShadowDepth =
  max(1, 0.05·size), BlurRadius ≈ 2 × max(2, 0.15·size) }` (WPF's BlurRadius is roughly twice CoreGraphics' blur —
  compare against `part2-rendered-results.png` and tune), and composite it into the export with
  `RenderTargetBitmap` (effects render there). The canvas preview can put the same effect on the element. Scale the
  depth and radius by the canvas magnification so the preview matches the export.
- **Opacity** stays `PushOpacity` around the whole group (§1.8), so box, outline and letters fade as one.
- **Size control while scaling:** the port's size control must accept non-preset whole sizes (show "37 pt").
- **Chips:** a `ToggleButton`/`Button` template with a `Border` (CornerRadius 6, background = the preset's box colour
  or `#0FFFFFFF`) and a `TextBlock` in the preset's font; active = accent `BorderBrush`, thickness 2.

---

## Part 3 — Redaction strength, Highlighter, Spotlight

**What changed, in one paragraph.** Blur and pixelate get a **Strength** (blur radius / pixel size) and a
third mode, **Black-out** (a solid black box). A three-way **Blur / Pixelate / Black-out** switch in the side
panel **converts a selected redaction in place**. A redaction's pixels are now **re-rendered from the base
image for its current position and size** — this fixes a bug where a moved blur kept showing the blur of the
area it was drawn over (and a resized one stretched it). Two new tools: **Highlighter (H)**, a translucent
marker that *multiplies* with the image so text under it stays readable, with its own remembered colour /
width / opacity; and **Spotlight (S)**, which dims everything outside one or more rectangles/ellipses. macOS
code: `Packages/EditorKit/Sources/EditorKit/` — `RedactionAnnotations.swift`, `Redactor.swift`,
`HighlighterAnnotation.swift`, `SpotlightAnnotation.swift` (+ `AnnotationPainter`, the shared draw order),
`ToolDefaults.swift`, and edits to `AnnotationStyle.swift`, `Annotation.swift` (`blendMode`),
`EditorTool.swift`, `InspectorModel.swift`, `EditorInspectorView.swift`, `EditorCanvasView.swift`,
`EditorDocument.swift`, `DocumentRenderer.swift`, `EditorWindowController.swift`.

Snapshots from the headless probe (Retina): `docs/parity-v3/part3-panels.png` (the side panel for Blur,
Pixelate, Black-out, Highlighter, Spotlight, left to right) and `docs/parity-v3/part3-select-spotlight.png`
(Select tool with a spotlight selected: two spotlights, highlighter strokes, a dimmed blur, an arrow above the
dim).

### 3.1 Layout (exact, as built)

**Toolbar pill** — two new buttons (same 38×38 look as Part 1). Groups are now:
`[Select] | [Arrow, Line, Rectangle, Filled Rectangle, Ellipse] | [Text, Counter, Highlighter] |
[Blur, Pixelate, Spotlight] | [Crop]` — 13 buttons, **558pt wide**, so it still fits the 600pt canvas column at
the minimum window width (21pt spare each side).

| Tool | SF Symbol | Port icon (`Icons.xaml`) | Key | Tooltip | In toolbar |
|---|---|---|---|---|---|
| Highlighter | `highlighter` | **new** `icon-highlighter` (a marker pen) | H | Highlighter (H) | yes, after Counter |
| Spotlight | `flashlight.on.fill` | **new** `icon-spotlight` (a torch/flashlight) | S | Spotlight (S) | yes, after Pixelate |
| Black-out | `rectangle.inset.filled` | — | X | Black-out (X) | **no** — reached with X or the Redaction switch; while it is active no toolbar button is highlighted |

**Side panel sections** (same section chrome as Part 1: caption 10pt semibold UPPERCASE white 45%, 12/16/14
padding, 8pt between rows, 232pt content width, hairlines between sections). Full panel order is now:
Styles · Colour · Stroke · **Stroke (highlighter)** · Font · Background · Effects · Redaction · **Strength** ·
**Shape** · **Dim outside** · Opacity · Arrange (Styles and Effects are Part 2's text sections).

```
 Blur / Pixelate               Black-out                     Highlighter                   Spotlight
┌──────────────────────────┐  ┌──────────────────────────┐  ┌──────────────────────────┐  ┌──────────────────────────┐
│ Blur                     │  │ Black-out                │  │ Highlighter              │  │ Spotlight                │
│ REDACTION                │  │ REDACTION                │  │ COLOUR                   │  │ SHAPE                    │
│ [Blur|Pixelate|Black-out]│  │ [Blur|Pixelate|Black-out]│  │ ● ● (●) ● ● ● ● ●        │  │ [▭ Rectangle|◯ Ellipse]  │
│ Softens what's under-    │  │ Covers it with solid     │  │ CUSTOM [▬] [⌖ Pick …]    │  │ ──────────────────────── │
│ neath. Raise the strength│  │ black — the safest       │  │ ──────────────────────── │  │ Dim      ────●──── 60%   │
│ until it can't be read.  │  │ choice, nothing can be   │  │ STROKE                   │  └──────────────────────────┘
│ ──────────────────────── │  │ recovered.               │  │ Width   ───●─── 20 px    │
│ Strength ──●──── 12 px   │  └──────────────────────────┘  │ [Thin|Medium|Thick]      │
└──────────────────────────┘                                │ ──────────────────────── │
                                                            │ Opacity ──●───── 40%     │
                                                            └──────────────────────────┘
```
Under Select, a selected object shows the same sections plus the **Arrange** footer (§1.1) (e.g. one blur →
Redaction · Strength · Arrange; one spotlight → Shape · Dim outside · Arrange). Strength and Dim outside, like
Opacity, have no caption: the name is the row label ("Strength", "Dim") in the 56pt label column.

| Section (caption) | Rows (exact) |
|---|---|
| **Redaction** (Blur, Pixelate, Black-out) | ① Segmented **Blur / Pixelate / Black-out**, small, full width, equal segments; tooltips "Blur (B)", "Pixelate (P)", "Black-out (X)". Selected segment = the active redaction tool, or (under Select) the selected redaction's mode. ② A note (12pt, white 62%, wraps at 232pt) that follows the mode — Blur: "Softens what's underneath. Raise the strength until it can't be read." · Pixelate: "Turns what's underneath into blocks. Bigger blocks hide more." · Black-out: "Covers it with solid black — the safest choice, nothing can be recovered." |
| **Strength** (Blur, Pixelate — not Black-out; no caption) | "Strength" label (56pt, tooltip "How strongly it hides what's underneath") · slider · value "12 px" (11.5pt monospaced digits, white 55%, 40pt, right-aligned). Blur: 2…40, tooltip "Blur radius, in image pixels". Pixelate: 4…48, tooltip "Size of each block, in image pixels". Whole pixels. Blur and Pixelate share this section, so switching between them only changes the range, value and tooltip. |
| **Stroke** (Highlighter — its own section, same look as Part 1's Stroke) | ① "Width" label (56pt) · slider **4…48** · value "20 px". ② Segmented **Thin / Medium / Thick** = **12 / 20 / 32 px** (tooltips "12 px", "20 px", "32 px"); no segment highlighted for other widths. |
| **Colour**, **Opacity** (Highlighter) | Exactly Part 1's sections; they show and edit the highlighter's own pen (default Yellow ring, 40%). |
| **Shape** (Spotlight) | Segmented **Rectangle / Ellipse**, small, full width, equal segments, each with an icon before the label (SF `rectangle`, `circle`; port: rectangle / circle outline icons); tooltips "Rectangle", "Ellipse — or hold ⌥ while dragging". |
| **Dim outside** (Spotlight; no caption) | "Dim" label (56pt) · slider **10…90 %** · value "60%"; tooltip (label and slider) "How dark everything outside the spotlights gets". |

**Hint line — new / changed sentences (verbatim):**

| When | Sentence |
|---|---|
| Highlighter | Drag to highlight, like a marker pen — hold ⇧ for a straight line. |
| Spotlight | Drag over what matters — everything else is dimmed. Hold ⌥ for an ellipse. |
| Black-out | Drag over anything you want to hide — it's covered in solid black when you let go. |
| Select, one black-out or spotlight | Drag to move it, drag a handle to resize it, or press Delete to remove it. (same as rectangles/blur) |
| Select, one highlighter stroke | Drag to move it, or press Delete to remove it. (same as arrows) |

Blur / Pixelate hints are unchanged. On Windows write Shift for ⇧ and Alt for ⌥.

### 3.2 Which sections show (pure `InspectorModel` — port 1:1)

| Active tool / selected object | Sections |
|---|---|
| Blur, Pixelate | Redaction · Strength |
| Black-out | Redaction |
| Highlighter | Colour · Stroke (highlighter) · Opacity |
| Spotlight | Shape · Dim outside |

Under Select the Part 1 rule still applies (sections every selected object has, in panel order, + Arrange),
with **one extra rule: Strength only shows when every selected object is drawn by the same tool** (a blur and a
pixelate together show Redaction + Arrange — one slider can't be a blur radius and a pixel size at once). A
highlighter + an arrow share Colour · Opacity only (their Stroke sections differ).

### 3.3 Behaviour

**Redactions (Blur / Pixelate / Black-out).**
- One object type, `RedactionAnnotation` (frame + style); its **mode and strength live in the style**
  (`redactionMode`, `blurRadius`, `pixelSize`), so panel edits reach selected redactions through the ordinary
  Part 1 style-edit path (one undo step; a slider drag = one step; the value becomes the sticky default).
- **The patch is rendered from the base image for the current frame** every time it is drawn, cached on
  (base image identity, frame rect, mode, strength) — so moving, resizing or dragging the strength slider
  re-renders only when something changed (probe: 1.6 ms per move tick for a 600×160 px blur at radius 30).
  The patch rect is the frame **snapped outward to whole pixels and clipped to the image** (no sliver of the
  original at a fractional edge). After a crop, redactions render from the cropped image.
- **Blur** = Gaussian blur with σ = strength (CoreImage `CIGaussianBlur` radius), reading up to
  `ceil(3 × strength)` px of the **real image around the box** (clamped at the image edges only), then keeping
  only the box. (Before, the box's own edge pixels were smeared outward, which streaked at high strengths.)
- **Pixelate** = mosaic of `strength`-px square blocks, **each block its average colour**, using only the box's
  own pixels (edge-clamped). The grid is **centred on the box's centre** (partial blocks at the edges).
- **Black-out** = solid **opaque black `#000000`**, always black — not the palette colour (the Filled Rectangle
  tool already draws coloured boxes; black is the unambiguous "redacted" look). No strength.
- Redactions are **always opaque** (opacity forced to 100%, whatever the default style's opacity is).
- **The switch**: choosing a segment (a) sets `redactionMode` on every selected redaction — **converted in
  place** (same object, same stacking position), one undo step — and on the default style; (b) if a redaction
  tool is active, switches the tool to that mode **without clearing the selection** (so the just-drawn,
  just-converted box stays selected). Under Select the tool stays Select; the heading follows the object
  ("Black-out"). New redactions take their mode from the tool (B / P / X), not from the default style.
- Drawing: drag a box (dashed marquee while dragging); on release a box smaller than 2×2 px is ignored; the box
  is clipped to the image.

**Highlighter.**
- Drag draws a freehand path: each drag event adds the pointer position (image px) if it is ≥ 0.5 px from the
  last point. **⇧ (Shift) held** → the path becomes a straight line from the drag's start to the pointer. A click
  without a drag draws nothing. The stroke is live while dragging; it is selected when drawn.
- Drawn as **one path, stroked once** (round caps and joins, width = style line width), so where the stroke
  crosses itself it doesn't get darker. The object is composited as **one layer at its opacity with multiply
  blending** — multiply against everything drawn before it: black text stays black, white paper takes the
  colour, a mid-grey keeps its red/green and loses blue under yellow.
- **Own sticky pen** (`highlighterPen`): colour **Yellow (1.00, 0.84, 0.04)**, width **20 px**, opacity **40%**
  by default. While the Highlighter tool is active — or under Select when **only** highlighter strokes are
  selected — the Colour / Stroke / Opacity sections show and edit the pen (and the selected strokes); other
  tools' colour / width / opacity are untouched (after a yellow 40% highlight, the next arrow is still red,
  4 px, 100%).
- Bounding box = the points' bounds grown by half the width on every side. Selectable (Part 1's box hit-test
  + 6 px slop), movable, deletable; **no resize handles** (like arrows/lines).

**Spotlight.**
- Drag a rectangle; **⌥ (Alt) held during the drag → ellipse** (otherwise the panel's Shape). The whole dim is
  previewed live while dragging. On release, a spotlight narrower or shorter than **4 px is discarded**.
- **One dim layer for all spotlights**: black at the dim amount over the whole image, with every spotlight's
  shape **cleared out** (the union of the holes — overlapping spotlights stay bright where they overlap; a
  plain even-odd fill would re-dim the overlap, so it is not used). Dim amount = the topmost spotlight's, and
  the editor keeps all spotlights' dims equal: **a Dim-outside change applies to every spotlight in the
  document, even with nothing selected** (e.g. right after pressing S), as one undo step. Shape changes apply
  to the selected spotlight(s) only.
- **Draw order:** base image → dim layer → every other object in stacking order, so arrows, text, shapes and
  highlights stay bright. **Redactions count as part of the picture:** after each redaction is drawn, the dim
  layer is drawn again clipped to that redaction's rect, so a blur outside the spotlight is dimmed like the
  pixels around it.
- Selectable, movable, **resizable with the 8 handles**. Hit-testing tries every other object first and
  spotlights last, so clicking an arrow inside a spotlight picks the arrow; clicking empty spotlight area
  picks the spotlight. Arrange › Front/Back has no visible effect on a spotlight (it always draws beneath).

**Opening a text for editing** (Part 1 makes its style the default) now keeps the current redaction / pen /
spotlight settings instead of the copies stored with that old text (`keepingToolDefaults(of:)`).

### 3.4 Data

All inside the `editorDefaultStyle` JSON blob (`AnnotationStyle`), and on every object's style:

| JSON key | Type & default | Legacy / bad-value rule |
|---|---|---|
| `redactionMode` | `"blur"` \| `"pixelate"` \| `"blackout"`, default `"blur"` | missing or unknown → `"blur"` |
| `blurRadius` | number, px, **2…40**, default **12** | missing → 12; clamped |
| `pixelSize` | number, px, **4…48**, default **12** | missing → 12; clamped |
| `highlighterPen` | `{"color": {"r","g","b","a"}, "width": n, "opacity": n}`, default `{yellow (1, 0.84, 0.04, 1), 20, 0.4}` | missing/corrupt → default; width clamped 4…48, opacity 0.1…1 |
| `spotlightShape` | `"rectangle"` \| `"ellipse"`, default `"rectangle"` | missing or unknown → `"rectangle"` |
| `spotlightDim` | number **0.1…0.9**, default **0.6** | missing → 0.6; clamped |

Port: add these as `init` properties with those defaults to `AnnotationStyle` in
`windows/src/BetterScreenshot.Editor/EditorStyle.cs`; enums need
`[JsonConverter(typeof(JsonStringEnumConverter))]` with camelCase names (`blur`, `blackout`, `rectangle`…) and
a fallback for unknown strings (catch + default); clamp after `FromJson`.

### 3.5 Pure logic to port 1:1 (with the macOS tests)

- **Redactor** — `blur(base, region, radius)`, `pixelate(base, region, blockSize)` as described in §3.3. Tests
  (`RedactorTests.swift`): higherBlurStrengthLeavesLessDetail (400×400 random-noise image, region
  (120, 140, 160×120): the red-channel **variance** of the patch falls strictly for radius 2, 6, 12, 24, 40) ·
  biggerPixelsLeaveLessDetail (same region: the **mean absolute difference between neighbouring pixels** falls
  strictly for block 4, 8, 16, 32, 48) · plus the existing size / destroys-detail tests.
- **RedactionAnnotation** — tests (`RedactionTests.swift`): movedRedactionRedactsItsNewRegion (noise image; a
  30×20 box drawn at (10,10), rendered, moved by (60,50): the rendered pixels at (70,60) equal a fresh
  `blur`/`pixelate` of that region within 2 levels) · resizedRedactionIsRenderedNotStretched (20×20 → 60×50:
  patch is 60 wide and equals a fresh render) · patchIsCachedUntilFrameOrStrengthChanges ·
  redactionIsAlwaysOpaque (style opacity 0.3 → 1) · redactionFollowsTheBaseIntoACrop ·
  redactionMapsToTheToolOfItsMode · blackoutIsSolidBlackAndHasNoPatch (frame (20.4, 10.6, 30×20): every pixel
  of (20, 10, 31×21) is opaque black) · switchingModeConvertsTheSelectedRedactionInPlace (same id; blur →
  pixelate → black-out; one undo per switch) · strengthEditsRestyleTheSelectedRedaction (grouped slider edits
  12 → 32 = one undo step) · legacyStyleDecodesRedactionDefaults · redactionFieldsRoundTripAndClamp (500 → 40,
  0 → 4, `"smudge"` → blur).
- **Highlighter** — tests (`HighlighterTests.swift`), on a white image with a black band and a mid-grey band,
  yellow (1,1,0) pen, stroke across y = 50: highlighterMultipliesSoTextUnderneathStaysReadable (100%: white →
  (≥245, ≥245, <10), black stays < 10, grey keeps its R/G within 4 and loses blue) ·
  highlighterOpacityFadesTheTint (40% on white → blue ≈ 153 = 0.6 × 255; black stays black) ·
  selfCrossingStrokeDoesNotDarkenTwice · canvasMultipliesToo · boundingBoxIsPathPlusHalfWidthAndMovesWithIt
  (points (10,20), (60,25), (40,50), width 20 → (0, 10, 70×50)) · penStyleIsItsOwnStickyDefault ·
  adoptingAnObjectsStyleKeepsTheCurrentToolDefaults · legacyStyleDecodesTheDefaultPenAndClampsABadOne.
- **Spotlight** — tests (`SpotlightTests.swift`), white 100×100 image: insideUnchangedOutsideDarkenedByTheDimAmount
  (rect (20,20,40×40): inside 255; outside 255 × (1 − dim) = 102 at 0.6, 179 at 0.3, ±3) ·
  ellipseSpotlightDimsTheBoxCorners · severalSpotlightsMakeOneLayerWithSeveralHoles (overlap stays 255, outside
  dimmed once) · otherObjectsStayBrightAboveTheDim (a red box drawn before the spotlight stays full red) ·
  redactionsOutsideTheSpotlightAreDimmedToo · canvasDrawsTheDimLayerToo · dimEditReachesEverySpotlight (dim edit
  with one of two selected → both; shape edit → only the selected; with nothing selected the dim still changes
  both; one undo step) · spotlightsAreHitLastAndResizeLikeBoxes · legacyStyleDecodesSpotlightDefaultsAndClamps
  (1 → 0.9).
- **InspectorModel** additions (`InspectorModelTests.swift`): redactionAndCropTools (Blur/Pixelate → Redaction,
  Strength; Black-out → Redaction, heading "Black-out") · selectWithOneObjectShowsItsSectionsPlusArrange (one
  blur → Redaction, Strength, Arrange) · highlighterShowsColourItsOwnStrokeOpacity ·
  spotlightShowsShapeAndDim · redactionSelectionsShareStrengthOnlyWithinOneMode (blur+blur keep Strength;
  blur+pixelate and pixelate+black-out → Redaction, Arrange) · toolShortcutsAreUniqueAndCaseInsensitive now
  covers H, S, X.
- **`keepingToolDefaults(of:)`** — copy `redactionMode`, `blurRadius`, `pixelSize`, `highlighterPen`,
  `spotlightShape`, `spotlightDim` from the current default onto an adopted object style.

### 3.6 Where it goes in the port

- `windows/src/BetterScreenshot.Editor/Annotations.cs` — replace `PixelateAnnotation` / `BlurAnnotation` (which
  carry a baked `Patch`) with `RedactionAnnotation(Guid Id, AnnotationStyle Style, PxRect Frame)` (mode in the
  style, no patch); add `HighlighterAnnotation(Id, Style, IReadOnlyList<PxPoint> Points)` (bounding box = points'
  bounds ± width/2; `MovedBy` offsets every point) and `SpotlightAnnotation(Id, Style, PxRect Frame)`.
- `windows/src/BetterScreenshot.Editor/Redactor.cs` — `Blur(source, region, radius)` / `Pixelate(source, region,
  blockSize)` take the strength; Blur reads a `3 × radius` margin of the real image (clamped to the image) and
  approximates the Gaussian with **three box passes of radius ≈ strength**, using running sums (O(1) per pixel —
  the current per-pixel O(radius) loop gets slow at radius 40 on big boxes); Pixelate already averages blocks —
  centre its grid on the region's centre. Add a `Blackout` path in the renderer (no Redactor call).
- `windows/src/BetterScreenshot.Editor/EditorDocument.cs` — `TopmostHit`: non-spotlights first, then spotlights.
- `windows/src/BetterScreenshot.Editor/EditorTool.cs` — add `Highlighter`, `Spotlight`, `Blackout` (+ the Part 1
  name / key / tooltip / `MakerOf` helpers; `MakerOf(RedactionAnnotation)` = the tool of its style's mode).
- `windows/src/BetterScreenshot.Editor/EditorStyle.cs` — the §3.4 fields; `InspectorModel.cs` (from Part 1) — the
  §3.2 rules and hint strings; a `KeepingToolDefaults` helper.
- `windows/src/BetterScreenshot.App/Editor/DocumentRenderer.cs` — the draw order of §3.3 (base → dim layer →
  objects, dim re-applied over each redaction); redaction patches computed **here from `baseImage`** for the
  current frame (cache keyed on frame + mode + strength, e.g. a `ConditionalWeakTable<RedactionAnnotation, …>` or
  a dictionary by `Id`); the highlighter's multiply (see §3.7).
- `windows/src/BetterScreenshot.App/Editor/EditorWindow.xaml(.cs)` — the two toolbar buttons + H / S / X keys;
  mouse handling (`ApplyRedaction` just adds a `RedactionAnnotation`; highlighter path + Shift; spotlight + Alt,
  4 px minimum); the panel sections; the pen routing (the window keeps `_style` and shows/edits
  `_style.HighlighterPen` as colour/width/opacity while the Highlighter is active or only highlighter strokes are
  selected); the "dim applies to every spotlight" rule in the style-edit path; the Redaction switch
  (convert selected + switch tool keeping the selection).
- `windows/src/BetterScreenshot.App/Resources/Icons.xaml` — new: `icon-highlighter`, `icon-spotlight`, and small
  rectangle / circle outline icons for the Shape segments (existing `icon-rect` / `icon-ellipse` will do).
- Tests: `windows/tests/BetterScreenshot.Tests/` — recreate §3.5.

### 3.7 Platform notes (Windows)

- **Multiply blending isn't available in WPF** (no blend modes on `DrawingContext`, and a `ShaderEffect` can't read
  what is behind an element). Because the port's canvas already shows the flattened `DocumentRenderer.Render`
  bitmap (`Redraw()`), do the multiply **on the CPU inside the renderer**: when the draw loop reaches a
  highlighter, flatten what has been drawn so far to a `RenderTargetBitmap`, render the stroke's **coverage
  mask** (the path in opaque white on transparent, round caps/joins, one geometry so self-overlaps count once)
  over the stroke's bounding box, then per pixel `out_c = dst_c × (1 − k × (1 − colour_c))` with
  `k = opacity × coverage` (straight colour 0…1 per channel), write it back (`WriteableBitmap`) and keep drawing
  on top. A single-colour multiply can't be faked with normal alpha (the needed alpha differs per channel).
- **Dim layer:** `Geometry dim = Geometry.Combine(new RectangleGeometry(imageRect), holes,
  GeometryCombineMode.Exclude, null)` where `holes` is the **union** of the spotlight shapes (successive
  `Geometry.Combine(..., GeometryCombineMode.Union, ...)` of `RectangleGeometry` / `EllipseGeometry`);
  `dc.DrawGeometry(new SolidColorBrush(Color.FromArgb((byte)(dim*255), 0, 0, 0)), null, dim)`. Over each
  redaction: `dc.PushClip(new RectangleGeometry(redactionRect))`, draw the same geometry, `dc.Pop()`.
- **Move optimisation:** the port renders "everything except the moved object" once and draws the moved object
  over it while dragging (`_moveBackground`). A moved redaction must still take its patch from `_baseImage`
  (not from that background), and when spotlights are involved (moving one, or any spotlight in the document)
  the dim layer must be recomputed — simplest is a full `Render` per tick in that case.
- **Modifiers:** ⇧ → Shift, ⌥ → **Alt** (`Keyboard.Modifiers.HasFlag(ModifierKeys.Alt)` during `MouseMove`; the
  editor has no menu bar, so Alt won't steal focus). Hint strings: "…hold Shift for a straight line.",
  "…Hold Alt for an ellipse.", tooltip "Ellipse — or hold Alt while dragging".
- **Blur quality:** WPF's `BlurEffect` is GPU-only and resolution-dependent at render time — keep the CPU
  `Redactor` so export and screen match pixel for pixel.

---

## Part 4 — Recording setup strip v2 (device menus, level meter, hint line)

**What changed.** The pre-record strip (shown by the Start/Stop Recording shortcut before a target is
picked) used to be one row of buttons with three unlabelled icon toggles (mic / speaker / camera).
It is now a labelled panel: the target buttons plus Format / FPS on top, one **column per source** (icon +
caption + dropdown), a **live microphone level meter**, and a **hint line** at the bottom that explains
whatever the pointer is over. The Settings window's Recording card got the same dropdowns. A **Show
mouse cursor** option was added. On macOS, window recordings also got a system-audio fix (see Platform
notes). Snapshots from the headless probe: `docs/parity-v3/part4-record-strip.png` (strip, 2× pixels —
**before** the 2026-09-25 UI-review fixes; current look: `docs/reviews/2026-09-25-ui-fixes/recording-strip-*.jpg`)
and `docs/parity-v3/part4-settings-recording.png` (Settings card).

Terms: *dBFS* = decibels relative to digital full scale (0 = loudest possible sample, silence → −∞);
*dshow* = DirectShow, the Windows capture API ffmpeg uses for the port's microphone/loopback inputs;
*WASAPI* = Windows Audio Session API (Core Audio); *Continuity Camera* = an iPhone used wirelessly as a
Mac camera/microphone.

macOS files: `App/Recording/RecordStripController.swift` (strip), `App/Settings/SettingsView.swift`
(`sourceMenus`), `App/Settings/SettingsHelp.swift`, and in `Packages/RecordingKit/Sources/RecordingKit/`:
`RecordingConfig.swift`, `DeviceChoice.swift` (pure), `DeviceCatalog.swift`, `MicLevel.swift` (pure),
`MicCapturer.swift`, `CameraBubbleController.swift`, `ScreenRecorder.swift`.

### Layout (exact, as built — 964 × 164 pt; same height in every state)

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
│ [🖥 Full Screen] [⬚ Area…] [▭ Window…]                      Format (MP4|GIF)   FPS (30|60)     ⊗ │
│ ──────────────────────────────────────────────────────────────────────────────────────────────── │
│ 🎙 Microphone  ▮▮▮▮▮▯▯▯▯▯▯  🔊 System audio               📹 Camera                  ↖ Mouse cursor │
│ [MacBook Air Mic       ⌃⌄]  [All apps except BetterScreenshot⌃⌄] [FaceTime HD Camera  ⌃⌄] [Shown ⌃⌄] │
│ ──────────────────────────────────────────────────────────────────────────────────────────────── │
│ ⓘ Pick what to record, then choose Full Screen, Area or Window.                                  │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

- **Window:** borderless, floating, non-activating (never steals focus), on all desktops, draggable by
  its background, no title / close buttons. It can still become the key window when clicked (macOS:
  an `NSPanel` subclass with `canBecomeKey = true`), so Tab moves keyboard focus between its controls
  with focus rings. Background = the app's **shared dark HUD** (macOS `RecordingHUDStyle`: vibrant-dark
  `.hudWindow` blur + a **black 40 %** tint + a **1 px white 10 %** border, **12 pt** corner radius;
  WPF: the existing `Theme.CardBrush` card with a 12 px corner radius and the 1 px 10 % white border).
  Primary text white, secondary text **white 60 %**. Placement: horizontally centred on the work area
  of the monitor under the pointer, bottom edge **60 pt** above the work area's bottom. Measured after
  the menus are filled.
- **Content:** one vertical stack, padding **top 14 · left 16 · bottom 12 · right 16**, **12 pt**
  between rows: top row · separator · sources row · separator · hint row. Every row is exactly
  **932 pt** wide (= the four columns + three 16 pt gaps). Separators are the standard 1 px hairline.
- **Top row** (horizontal, 8 pt spacing), left → right:
  1. Button **"Full Screen"**, icon `display` (SF Symbol) on the left of the label.
  2. Button **"Area…"**, icon `rectangle.dashed`.
  3. Button **"Window…"**, icon `macwindow`.
     Buttons are standard rounded push buttons at the *large* size (≈ 28 pt tall).
  4. Flexible space.
  5. Label **"Format"** (12 pt, white 60 %) + 6 pt + choice control **(MP4 | GIF)**.
  6. 20 pt gap. Label **"FPS"** + 6 pt + choice control **(30 | 60)**.
     *Choice control* (replaces a segmented control, whose selected segment was barely lighter than
     the rest whenever the panel isn't key — i.e. almost always): a track with white 10 % fill, corner
     radius 7, 2 pt padding and 2 pt between options; each option a borderless 40 × 22 button, corner
     radius 5, 13 pt text — chosen: **accent-colour fill**, white semibold; other: no fill, white 60 %
     regular. Accessibility: radio group named "Format" / "Frame rate", options as radio buttons.
  7. 16 pt gap. Close button: borderless icon `xmark.circle.fill` at 16 pt, white 60 % (white while
     hovered/focused), tooltip **"Close without recording"**, accessible name "Cancel".
- **Sources row** (horizontal, **16 pt** gaps, top-aligned) — four columns, each a vertical stack
  (6 pt spacing) of: header row as wide as the column (icon 12 pt medium weight · 5 pt · caption 12 pt
  medium, both white 60 % · flexible space · optional right-aligned accessory) → dropdown (regular
  size, **fixed width**). No footer line (it left an empty band when the mic was Off). Column widths:
  Microphone, System audio and Camera share **252** (fits "All apps except BetterScreenshot", 251 pt,
  untruncated); Mouse cursor **128**:

  | Column | Icon | Caption | Width | Menu items (top → bottom) |
  |---|---|---|---|---|
  | 1 | `mic` | Microphone | 252 | `Off` · every connected microphone by name |
  | 2 | `speaker.wave.2` | System audio | 252 | `Off` · `All apps` · `All apps except BetterScreenshot` |
  | 3 | `video` | Camera | 252 | `Off` · every connected camera by name · separator · `Camera Size ▸` submenu `Small` / `Medium` (✓ on the current one) |
  | 4 | `cursorarrow` | Mouse cursor | 128 | `Shown` · `Hidden` |

  Menu-item tooltips (verbatim): Off → "No system sound in the recording."; All apps → "Every sound
  your Mac plays, including BetterScreenshot's own."; All apps except BetterScreenshot → "Every sound
  except BetterScreenshot's own, like its capture sound."; Shown → "The mouse cursor is recorded as it
  moves."; Hidden → "The video shows no mouse cursor."
  Dropdown titles always start at the dropdown's normal **12 pt** left inset, truncated or not (macOS'
  popup cell squeezes it to 5 pt for a title that doesn't fit; the strip keeps 12).
- **Microphone header accessory** (right-aligned in the Microphone header, same line as the caption):
  either the **level meter** — **120 × 6 pt**, 16 segments, 2 pt gaps, 1.5 pt corner radius; lit
  segments are green for the first 70 % of the bar, yellow up to 90 %, red above; unlit = white at
  14 % — or the link **"Allow microphone access…"** (11 pt, link colour, borderless, 15 pt tall), or
  nothing (see Behaviour). The header is the same height in all three cases, so the strip never
  changes size.
- **Hint row:** icon `info.circle` (12 pt, white 60 %) · 6 pt · one line of 12 pt text that fills the
  rest of the row (tail-truncates, but every string below fits: the longest measured 532 pt of ~914 pt
  available). The idle text is white 60 %; while it explains a hovered/focused control it's **white**,
  and that control's group caption (icon + caption, or the Format / FPS label, or the ✕) turns white
  too.
- **Icons in the port** (`windows/src/BetterScreenshot.App/Resources/Icons.xaml`): reuse `icon-mic`,
  `icon-speaker`, `icon-video`, `icon-cursor`, `icon-close-circle`; **add** a monitor (`display`), a
  dashed rectangle (`rectangle.dashed`), a window (`macwindow`) and an info-circle icon.

### Hint line — texts (verbatim) and rules

| Pointer over / focus on | Hint |
|---|---|
| nothing (idle) | Pick what to record, then choose Full Screen, Area or Window. |
| nothing (idle) while Format = GIF | GIFs have no sound. Switch Format to MP4 to record audio. |
| Full Screen | Full Screen: records everything on this screen. |
| Area… | Area: drag over the part of the screen you want, then recording starts. |
| Window… | Window: click a window to record just that window, even as it moves. |
| "Format" label or its control | Format: MP4 is a video with sound. GIF is a silent, looping animation. |
| "FPS" label or its control | Frame rate: 60 looks smoother, 30 makes smaller files. |
| ✕ | Close this strip without recording. |
| Microphone column (MP4) | Microphone: records your voice from the selected input. Choose "Off" to skip it. |
| System audio column (MP4) | System audio: records the sound your Mac plays, like videos and calls. Choose "Off" to skip it. |
| Microphone or System audio column while Format = GIF | GIFs have no sound. Switch Format to MP4 to record audio. |
| Camera column | Camera: shows your webcam in a round bubble on the recording. Set its size in the menu. |
| Mouse cursor column | Mouse cursor: choose whether it appears in the video. |
| "Allow microphone access…" link, access never asked | Click to let BetterScreenshot use the microphone. macOS asks once. |
| same link, access denied | Microphone access is off. Click to open System Settings and turn it on for BetterScreenshot. |

(Windows: say "Windows" / "Settings" instead of "macOS" / "System Settings", and "your PC" for
"your Mac".) A **column's hover area is the whole column** (header + dropdown), so hovering
the caption explains it too. Areas can nest (the link sits inside the Microphone column): the most
recently entered area wins, and leaving it falls back to whichever area the pointer is still in, else
idle. With no hover, a **keyboard-focused** control (Tab) shows its hint. Hover never changes anything.

### Behaviour

- **Every choice saves immediately** into the recording settings (same values the Settings window
  edits); no Apply button. Target buttons start the recording flow exactly as before.
- **Device lists** are read fresh each time the strip opens and **rebuilt live** when a device is
  plugged in or removed while it is open (macOS: `AVCaptureDevice.wasConnected/wasDisconnected`
  notifications). Microphones = built-in, USB, AirPods, iPhone (Continuity) and virtual inputs;
  cameras = built-in, external, iPhone (Continuity Camera). Two devices with the same name are shown as
  "Name", "Name (2)", "Name (3)".
- **What the dropdown shows** (pure `DeviceList.choice`, see Pure logic): `Off` when the source is off;
  otherwise the device that will actually record — the saved one while connected, else the system
  default, else the first listed; `Off` if no device exists at all. An unplugged saved device is *not*
  overwritten: when it comes back it is used again.
- Choosing `Off` keeps the last device id; choosing a device turns the source on and saves its id.
- **Camera Size** submenu sets Small/Medium without changing the selected camera row.
- **Format = GIF** disables (dims) the Microphone and System audio dropdowns (their values are kept),
  hides the meter, and the recording ignores both (GIFs have no sound — no mic prompt, no mic in use).
- **Mic level meter** runs only while all of these hold: strip visible, Format = MP4, a microphone is
  selected, and microphone permission is **already granted**. Opening the strip must never trigger the
  OS permission prompt. When a mic is selected but access isn't granted, the Microphone header shows
  **"Allow microphone access…"**: if access was never asked, clicking it asks (the OS prompt), then the
  meter starts; if it was denied, clicking opens the OS privacy settings for the microphone
  (macOS `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`; Windows
  `ms-settings:privacy-microphone`). The meter stops when the strip hides or the choice changes.
  It reads the device's average power per audio buffer (~47 updates/s) through `MicLevel`.
- **Long device names** truncate with "…" at the end; hovering the dropdown then shows the full name
  as a tooltip (only when truncated).
- **Mouse cursor = Hidden** records without the pointer.

### Settings window — Recording + In the video cards (same choices, same stored values)

Since the fixes for the 2026-09-25 UI review (`docs/reviews/2026-09-25-ui-review.md`, items T3/T5) the
old single Recording card is two cards, and the Settings window's three columns are
**Capture · Quick Access Overlay · Pin to Screen** | **Recording · Startup** | **In the video · History ·
Save location** (so the three columns end at about the same height).

**RECORDING** rows in order: Format · Frame rate · Countdown before recording · divider · **Microphone**
(dropdown: Off + mics) · **System audio** (dropdown: the three modes; when Format = GIF both audio
dropdowns are dimmed/disabled and a sub-label reads "GIFs have no sound. Switch Format to MP4 to record
audio.") · **Camera** (dropdown: Off + cameras) · Camera size [Small | Medium] (disabled while Camera =
Off). **IN THE VIDEO** rows: **Mouse cursor** (dropdown: Shown | Hidden — the record strip's name and
choices) · Highlight mouse clicks · Show keystrokes · Show recording controls in the video.
The three old switches ("Record system audio", "Record microphone", "Show camera bubble")
are gone. Dropdowns are full-width, label above (the existing "field label + ⓘ" idiom). ⓘ texts
(title — explanation — example, verbatim):
- **Microphone** — "Which microphone records your voice, or Off for none. If the chosen mic is
  unplugged, your Mac's default mic is used instead. The record strip shows a live level meter for
  it." — "Pick your AirPods or a USB mic to narrate a tutorial."
- **System audio** — "The sound your Mac plays — videos, calls, music, alerts — recorded along with the
  screen. "All apps except BetterScreenshot" leaves out this app's own sounds, like its capture sound.
  GIF recordings never have sound." — "All apps to capture a video call's audio along with the screen."
- **Camera** — "Shows your webcam in a round bubble on screen while you record, so it ends up in the
  video. Pick which camera (including an iPhone via Continuity Camera), or Off." — "Turn on for a
  face-cam picture-in-picture during a walkthrough video."
- **Mouse cursor** — "Shown draws the mouse pointer into the recording as it moves. Hidden gives a clean
  video without the pointer." — "Choose Hidden when recording a slideshow or video you won't be clicking
  through."

(macOS also fixed the shared `MonoComboField` so dropdowns draw as the styled full-width field — the
port's ComboBox style already does.)

### Data (persisted recording keys — flat string dictionary, same as the port's `RecordingConfig.ToDictionary`)

| Key | Values | Default | Legacy / notes |
|---|---|---|---|
| `systemAudioMode` | `off` · `all` · `excludeSelf` | `all` | **New.** If missing or unknown, derive from the old `systemAudio` Bool: `"true"` → `all`, `"false"` → `off`, missing → `all`. |
| `systemAudio` | `true`/`false` | `true` | **Still written** (= mode ≠ off) so an older build reads a sensible value. In code it is now a view of the mode: setting true when Off picks `all`; setting true when already on keeps the mode. |
| `microphone` | `true`/`false` | `false` | Unchanged meaning: mic on/off. |
| `microphoneDeviceID` | device id string | absent | **New.** Absent or `""` = "system default". Old `microphone = true` with no id → the default device. |
| `camera` | `true`/`false` | `false` | Unchanged. |
| `cameraDeviceID` | device id string | absent | **New**, same rules as the mic id. |
| `cameraSize` | `small`/`medium` | `small` | Unchanged; now set from the Bubble Size submenu too. |
| `showsCursor` | `true`/`false` | `true` | **New** ("Mouse cursor": Shown = `true`, Hidden = `false`). |

Device ids are platform-specific (macOS: `AVCaptureDevice.uniqueID`; Windows: see Platform notes) —
never compare them across platforms.

### Pure logic to port 1:1 (with the macOS test cases)

`DeviceList { devices: [(id, name)], defaultID }` (`DeviceChoice.swift`):
- `resolvedID(saved)` = saved if it's in `devices`; else `defaultID` if it's in `devices`; else the
  first device's id; else null.
- `choice(enabled, saved)` = `Off` if not enabled or `resolvedID` is null; else `Device(resolvedID)`.
- `options` = `[(Off, "Off")]` + one row per device in list order; the n-th repeat of a name is titled
  `"Name (n)"`.
- `RecordingConfig.setMicrophone(choice)` / `setCamera(choice)`: `Off` → source off, **id kept**;
  `Device(id)` → source on + id saved.

`SystemAudioMode`: titles `Off` / `All apps` / `All apps except BetterScreenshot`; `excludesOwnAudio`
is true only for `excludeSelf`.

`MicLevel` (`MicLevel.swift`): `floor = −60 dB`; `fraction(dB) = clamp((dB + 60) / 60, 0, 1)`, and
non-finite (−∞ silence, NaN) → 0; `smoothed(prev, target) = target ≥ prev ? target : max(target,
prev − 0.06)` (fast attack, slow release per ~20 ms update); `litSegments(fraction, n) =
clamp(round(fraction · n), 0, n)`. (The floor was measured: a quiet room reads −88…−64 dBFS on a
MacBook Air mic, so it stays dark; speech ≈ −35…−20 lights about half.)

Tests (`Packages/RecordingKit/Tests/RecordingKitTests/DeviceChoiceTests.swift`,
`RecordingConfigTests.swift`) — recreate these:
- resolvedID: devices [BuiltInMic, AirPods-1, USB-7], default BuiltInMic → saved AirPods-1 → AirPods-1;
  saved "Gone-9" → BuiltInMic; saved nil → BuiltInMic; devices [AirPods-1, USB-7] with default
  "Aggregate-3" (unlisted) → AirPods-1; no devices → null.
- choice: disabled → Off; enabled+AirPods-1 → AirPods-1; enabled+nil → BuiltInMic; enabled+"Gone-9" →
  BuiltInMic; enabled with no devices → Off.
- options: [MacBook Pro Microphone, USB Audio CODEC, USB Audio CODEC] → titles "Off", "MacBook Pro
  Microphone", "USB Audio CODEC", "USB Audio CODEC (2)"; no devices → ["Off"].
- apply: mic Device(AirPods-1) → on + id; then Off → off, id still AirPods-1; same for camera.
- config defaults: mode `all`, ids null, showsCursor true; round-trip with `excludeSelf` / `off`,
  mic + camera ids, showsCursor false; `{showsCursor:"false"}` → false; `{microphoneDeviceID:""}` → null.
- legacy: `{systemAudio:"true"}` → all; `{systemAudio:"false"}` → off; `{microphone:"true",
  camera:"true"}` → both on, ids null; `{systemAudio:"true", systemAudioMode:"excludeSelf"}` →
  excludeSelf; `{systemAudio:"false", systemAudioMode:"bogus"}` → off; written dictionary has
  `systemAudio` "true" for excludeSelf and "false" for off.
- Bool view: mode excludeSelf → systemAudio true; set true → still excludeSelf; set false → off; set
  true → all.
- MicLevel: fraction(0)=1, (6)=1, (−30)=0.5, (−60)=0, (−72)=0, (−∞)=0, (NaN)=0; smoothed(0.2→0.9)=0.9,
  (0.9→0.1)=0.84, (0.03→0)=0; litSegments(0,12)=0, (0.5,12)=6, (0.04,12)=0, (1,12)=12, (1.7,12)=12.

### Where it goes in the port

- Strip: rebuild `windows/src/BetterScreenshot.App/Recording/RecordStripWindow.xaml(.cs)` (today one
  horizontal `ControlRow` with "Record Full Screen / Record Window… / Record Area…" text buttons, an
  MP4/GIF toggle and three `IconToggle`s) into the layout above: a `Grid`/`StackPanel` stack, WPF
  `ComboBox`es for the dropdowns, a small meter control, and a `TextBlock` hint line driven by
  `MouseEnter`/`MouseLeave` + `GotKeyboardFocus` on each area.
- Config: `windows/src/BetterScreenshot.Recording/RecordingConfig.cs` — add `SystemAudioMode`,
  `MicrophoneDeviceId`, `CameraDeviceId`, `ShowsCursor` with the keys/legacy rules above (keep writing
  `systemAudio`).
- Pure logic: new `DeviceList.cs` and `MicLevel.cs` next to `DshowDeviceList.cs` in
  `windows/src/BetterScreenshot.Recording/`, tests in `windows/tests/BetterScreenshot.Tests/`.
- Devices: `windows/src/BetterScreenshot.Platform/DshowAudioDevices.cs` — expose the enumerated list
  for the menu (it is cached today; invalidate it when the strip opens or on device-change), and make
  `ResolveAsync` use the saved mic (via `DeviceList.resolvedID`) instead of always
  `DshowDeviceList.PickMicrophone` (that heuristic stays as the "default device" fallback when the OS
  default can't be read).
- Engine: `windows/src/BetterScreenshot.Recording/FfmpegArgs.cs` — `-draw_mouse` becomes
  `ShowsCursor ? "1" : "0"` (it is hard-coded `"1"`);
  `windows/src/BetterScreenshot.App/Recording/RecordingCoordinator.cs` skips audio for GIF.
- Camera: `windows/src/BetterScreenshot.App/Recording/CameraBubbleWindow.xaml.cs` — pass the chosen
  camera as `MediaCaptureInitializationSettings.VideoDeviceId` (today it takes the first colour source).
- Settings: `windows/src/BetterScreenshot.App/Settings/SettingsWindow.xaml(.cs)` — replace the
  `SysAudioCheck` / mic / camera switches with ComboBoxes + the "Mouse cursor" (Shown | Hidden) ComboBox,
  split into the Recording + In the video cards described above.

### Platform notes

- **Device ids on Windows.** Mics: the dshow device name the port already uses (or better, the dshow
  "Alternative name" device path, which survives renames — `DshowDeviceList.Parse` currently drops
  those lines). System default mic: Core Audio `IMMDeviceEnumerator::GetDefaultAudioEndpoint(eCapture,
  eConsole)` friendly name, matched to the dshow name. Cameras: `DeviceInformation.FindAllAsync(
  DeviceClass.VideoCapture)` → `Id` (what `MediaCapture` takes) + `Name`; default = first. Device
  changes: `DeviceWatcher` (or `WM_DEVICECHANGE`).
- **Mic level meter on Windows.** Needs a live capture while the strip is open — ffmpeg isn't running
  yet. Open a shared-mode WASAPI capture on the chosen endpoint (or `Windows.Media.Audio.AudioGraph`
  with a device input node) and compute peak/RMS in dBFS per buffer, feeding `MicLevel`. (Core Audio's
  `IAudioMeterInformation` on a capture endpoint only reports while some stream is capturing, so it
  still needs that capture open.) Check access first with
  `DeviceAccessInformation.CreateFromDeviceClass(DeviceClass.AudioCapture).CurrentStatus` so opening the
  strip never prompts.
- **System audio modes on Windows.** The port records system audio from a dshow loopback device
  ("Stereo Mix" / virtual cable, `DshowDeviceList.PickSystemLoopback`), which is always *all* audio —
  `All apps` maps directly. **`All apps except BetterScreenshot` can't be done with a dshow loopback
  device**; it needs WASAPI *process loopback* (`ActivateAudioInterfaceAsync` with
  `AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK`, `PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE`
  on the app's own PID; Windows 10 build 20348+ / Windows 11), piped into ffmpeg as raw PCM. If that's
  out of reach, show the item disabled with the tooltip "Needs Windows 11" or omit it on Windows — and
  keep `excludeSelf` readable (treat it as `all`) so a synced/ported settings file still loads.
- **"Only this app" was probed and dropped on macOS** (spec §7 / risk 3). ScreenCaptureKit's per-app
  audio (a single-window filter, or a display filter including one app) hears only that app's *own
  process*: a WebKit web view in the probe app played audio that an all-apps stream heard at peak 0.36
  but the app-only and window filters recorded as 0.00 — browsers, Electron apps and anything else that
  plays sound from a helper process would record silence. Don't add it to the port either (parity),
  even though Windows process loopback *could* include a process tree.
- **macOS window-recording audio fix (no Windows equivalent needed).** Before this part, macOS window
  recordings took system audio from the window's own filter and so captured only that app's main
  process (usually silence for a browser). They now use a second, audio-only display-wide stream,
  verified on real MP4s: another app's sound peak 0.20 (was 0.00), BetterScreenshot's own sound
  excluded in `All apps except BetterScreenshot`, audio and video tracks both start at 0. The port's
  gdigrab + loopback design always hears all apps, so it doesn't have this bug.
- **Cursor:** gdigrab/ddagrab `-draw_mouse 0/1` (macOS: `SCStreamConfiguration.showsCursor`).

---

## Part 5 — Live recording pill v2 (mute, switch window, restart, discard)

**What it is.** While a recording runs, the floating recording pill (the "timer · Pause · Stop" pill from
§A) is now **expanded by default** with live controls: mute the microphone, mute system audio, show/hide
the camera bubble, switch the recorded window/area, restart, discard, pause, stop. A chevron collapses it
back to the compact pill. macOS files: `App/Recording/RecordingControlsController.swift` (the pill),
`App/Recording/RecordingCoordinator.swift` (what each control does), and in `Packages/RecordingKit/`:
`ScreenRecorder.swift` (mute, retarget, pause fixes), `SilenceFill.swift`, `LetterboxFit.swift`,
`CameraBubbleController.swift` (`setHidden`). Snapshots (2× PNGs from the headless probe) are in
`docs/parity-v3/part5-pill-*.png`.

### Layout (exact)

**Window.** Borderless, non-activating floating panel (never takes focus — clicks must land without
activating the app: WPF `WS_EX_NOACTIVATE` + first-click-through), topmost (`.statusBar` level), on all
desktops, shadow on, draggable by its background. Capsule height **40**, corner radius **20**.
Background: the app's shared dark HUD (macOS `RecordingHUDStyle`: vibrant dark `.hudWindow` blur) + a
**black 40 %** tint over it (keeps white text readable on bright backdrops) + a **1 px border, white
10 %**. The capsule is sized to its content (width changes with expand/collapse and Switch shown/hidden
only, see below). **Hover hint bubble:** hovering any control shows its hint (the "Hint" column below)
at once in a small bubble drawn **in the pill's own window** (so it's excluded from the recording with
the pill; the window grows to hold it and the rest of the window is transparent/click-through): same
dark HUD, corner radius **7**, height **24**, text 12 pt medium white, 10 pt padding each side,
**6 pt above** the capsule — **below** when there's no room above — centred on the hovered control and
kept **8 pt** inside the screen's work area (narrowed + tail-truncated if wider than the screen).
It replaces tooltips (they appeared late, if at all, while the app is inactive). Disabled controls show
their hint too (that's where the "why" is).

**Expanded — order, left → right (all sizes in pt):**

| # | Item | Size | Spacing after |
|---|---|---|---|
| — | left inset | 14 | — |
| 1 | status dot (circle) | 10 × 10 | 8 |
| 2 | timer column, fixed width 46: timer label, monospaced digits 14 pt semibold, left-aligned; while paused a **"Paused"** label (10 pt semibold, white) sits above it, both vertically centred as a pair | 46 | 10 |
| 3 | separator (vertical line, white 16 %) | 1 × 18 | 10 |
| 4 | **Mic** toggle (icon + label) | 58 × 28 | 2 |
| 5 | **System audio** toggle (icon + label) | 121 × 28 | 2 |
| 6 | **Camera** toggle (icon + label) | 87 × 28 | 10 |
| 7 | separator | 1 × 18 | 10 |
| 8 | **Switch Window…** / **Switch Area…** (icon + label) | 140 × 28 | 10 |
| 9 | separator | 1 × 18 | 10 |
| 10 | Restart (icon) | 35 × 28 | 2 |
| 11 | Discard (icon) | 35 × 28 | 2 |
| 12 | Pause / Resume (icon) | 28 × 28 | 2 |
| 13 | Stop (icon, red) | 28 × 28 | 6 |
| 14 | chevron (icon, white 55 %) | 20 × 28 | — |
| — | right inset | 6 | — |

Total **715** wide on macOS. Items 8 + its separator (7) are **hidden for full-screen recordings** (554
wide). All vertically centred. Restart and Discard are **35** wide (not 28) so that either confirm label
fits their combined **72 pt** slot (`RecordingPillLayout.confirmPairButtonWidth`, see Pure logic).

**Buttons.** Borderless, height **28**, corner radius **7**. Icon buttons: SF Symbol 14 pt semibold,
centred (chevron: 11 pt). Labelled toggles (items 4–6, 8): SF Symbol 13 pt semibold, then the label in
system font **12 pt medium**, icon leading and hugging the text, **8 pt padding each side**; each
labelled button's width is **locked to its widest state** (widest icon × widest label + 16) so toggling
never shifts the pill (macOS widths: 58 / 121 / 87 / 140 — recompute with Segoe UI). Glyph + text colour
white; **disabled → white 30 %**. **Hover** (tracked even while the app is inactive): fill white 12 %;
on a button that already has a fill, the fill blended 15 % toward white. Every **filled (red) chip** —
muted Mic/System audio, the confirm capsule — has a **1 px white 50 % ring**, so it stays distinct over
red content.

**Collapsed** (chevron clicked): only dot · timer · Pause · Stop · chevron remain, same metrics and
spacings (timer → Pause 10, Pause → Stop 2, Stop → chevron 6) = **178** wide.

**ASCII mockups (as built).** `[ ]` = a 28 pt control, `▓…▓` = red chip, `░…░` = greyed/disabled.
```
Recording a window (expanded, default):
╭──────────────────────────────────────────────────────────────────────────────────────────────╮
│ ●  1:23   │ [🎙 Mic] [🔊 System audio] [📷 Camera]┄ │ [▭ Switch Window…] │ [↺] [🗑] [⏸] [■]  › │
╰──────────────────────────────────────────────────────────────────────────────────────────────╯
(┄ = camera off: outline icon + label at white 60 %, no slash, no chip)
Mic + System audio muted, camera bubble showing:
│ ●  1:23   │ ▓🎙̸ Mic▓ ▓🔊̸ System audio▓ [📷 Camera] │ [▭ Switch Window…] │ [↺] [🗑] [⏸] [■]  › │
Area recording, no mic track, paused (grey dot, "Paused" over the grey timer, ▶ instead of ⏸):
│ ○ Paused  │ ░🎙̸ Mic░ [🔊 System audio] [📷 Camera]┄ │ [⬚ Switch Area…]   │ [↺] [🗑] [▶] [■]  › │
│    1:24   │
Countdown (engine not started yet): grey dot, "0:00", Switch/Restart/Discard/Pause greyed, Stop live:
│ ○  0:00   │ [🎙 Mic] [🔊 System audio] [📷 Camera]┄ │ ░▭ Switch Window…░ │ ░↺░ ░🗑░ ░⏸░ [■]  › │
First click on Restart — the capsule fills Restart's and Discard's slot (Discard hides), same width:
│ ●  12:07  │ … │ [▭ Switch Window…] │ ▓ Restart? ▓ [⏸] [■]  › │
First click on Discard — Restart hides, the capsule sits in the same slot:
│ ●  12:07  │ … │ [▭ Switch Window…] │ ▓ Discard? ▓ [⏸] [■]  › │
Hovering Stop (bubble above the pill, centred on the button):
                                                                     ╭────────────────╮
                                                                     │ Stop recording │
                                                                     ╰────────────────╯
Full screen (no Switch group):
│ ●  12:07  │ [🎙 Mic] [🔊 System audio] [📷 Camera]┄ │ [↺] [🗑] [⏸] [■]  › │
Collapsed:
╭──────────────────────────╮
│ ●  12:07   [⏸] [■]  ‹ │
╰──────────────────────────╯
```
Snapshots: `part5-pill-expanded.png`, `-muted.png`, `-area-no-mic.png`, `-countdown.png`,
`-confirm-restart.png`, `-collapsed.png`, `-hover.png` (Sound and Discard hovered) — all **before** the
2026-09-25 UI-review fixes; current look: `docs/reviews/2026-09-25-ui-fixes/recording-pill-*.jpg`.

**States of each item (icons are SF Symbol names → port icon keys below):**

| Item | State | Icon | Look | Hint (verbatim) |
|---|---|---|---|---|
| Dot | recording | — | systemRed | — |
| Dot | paused / countdown | — | systemGray | — |
| Timer | recording | — | white, "m:ss" (minutes unbounded, e.g. "12:07") | — |
| Timer | paused / countdown | — | white 60 %; countdown shows "0:00"; paused adds "Paused" above | — |
| Mic | on | `mic.fill` | white | "Mute microphone — the video keeps a silent gap, stays in sync" |
| Mic | muted | `mic.slash.fill` | **red chip**: fill systemRed 85 %, white icon + text | "Unmute microphone" |
| Mic | not recorded | `mic.slash.fill` | disabled (30 %) | "Mic wasn't on when this recording started — there's no mic track to mute" |
| System audio | on | `speaker.wave.2.fill` | white | "Mute system audio — the video keeps a silent gap, stays in sync" |
| System audio | muted | `speaker.slash.fill` | red chip | "Unmute system audio" |
| System audio | not recorded | `speaker.slash.fill` | disabled | "System audio wasn't on when this recording started — there's no system audio track to mute" |
| Camera | bubble showing | `video.fill` | white | "Hide camera bubble" |
| Camera | bubble hidden / never shown | `video` (outline, **no slash**) | white 60 %, **no chip** (camera-off is the normal state, not a warning; a slash now always means muted or unavailable) | "Show camera bubble" |
| Camera | no camera | `video.slash.fill` | disabled | "No camera found" |
| Camera | permission denied | `video.slash.fill` | disabled | "Camera access is off — allow BetterScreenshot in System Settings › Privacy & Security › Camera" (Windows: "…in Settings › Privacy & security › Camera") |
| Switch | window recording | `macwindow`, "Switch Window…" | white | "Record a different window — it's scaled to fit this video's frame" |
| Switch | area recording | `rectangle.dashed`, "Switch Area…" | white | "Record a different area — it's scaled to fit this video's frame" |
| Switch | countdown | as above | disabled | "Available once recording starts" |
| Restart | normal | `arrow.counterclockwise` | white | "Restart — delete what's recorded so far and start over" |
| Restart | confirming | no icon, text "Restart?" | **red capsule**: fill systemRed, white 12 pt semibold text, white 50 % ring, width = the Restart + Discard slot (72); Discard hidden | "Click again to restart — what's recorded so far is deleted" |
| Discard | normal | `trash` | white | "Discard — stop and delete this recording" |
| Discard | confirming | text "Discard?" | red capsule in the same 72 pt slot; Restart hidden | "Click again to delete this recording" |
| Restart/Discard | countdown | icon | disabled | "Available once recording starts" |
| Pause | recording / paused / countdown | `pause.fill` / `play.fill` | white; disabled during countdown | "Pause recording" / "Resume recording" / "Available once recording starts" |
| Stop | recording / countdown | `stop.fill` | systemRed glyph | "Stop recording" / "Cancel recording" |
| Chevron | expanded / collapsed | `chevron.right` / `chevron.left` | white 55 % | "Collapse to timer, Pause and Stop" / "Show all controls" |

**Resizing & position.** Whenever the width changes (expand/collapse, Switch shown/hidden — a confirm
no longer changes it) the capsule keeps its **bottom-right corner fixed** (the chevron stays under the
pointer), then is clamped 8 pt inside the screen's work area. The hint bubble never moves the capsule;
the window around it grows and shrinks instead. First show with no saved position: bottom-centre of the recording's
screen, bottom edge 20 pt above the work area's bottom. Dragging saves the position.

### Items & behaviour

- **Mic / Sound (mute).** Toggle. Muting does **not** drop the audio track: the recorder keeps writing
  it but with every sample set to silence, so the track stays continuous and in sync (dropping audio
  leaves gaps some players mishandle). Only works for tracks that exist — they're fixed when the
  recording starts; a source that was off (or whose permission was denied) is greyed with the tooltip
  above. During the countdown the buttons already work (the flag is applied from the first sample).
  **Mute states reset at the start of every new recording session and carry over a Restart.**
  Security rule: if a silent buffer can't be made, the buffer is dropped — a muted source must never
  leak sound.
- **Camera.** If the bubble exists, hides/re-shows it **where the user dragged it** (the camera itself
  stops while hidden so its light goes off). If the camera was off when recording started, the first
  click asks for camera permission if needed and shows the bubble (same size setting, same corner rule
  as at start) — it's recorded simply by being on screen.
- **Switch window… / Switch area…** (window / area recordings; full screen has none).
  1. If recording (not already paused), **pause** — the picker overlay must not be recorded and the
     picking time is cut from the video. 2. Show the same picker used to start: the hover-to-highlight
     **window picker** (all on-screen windows except our own) or the drag-to-select **area selection**
     (any display). 3. On pick, re-point the running capture at the new window/area **without stopping**.
     The video's pixel size stays what it was at the start; the new content is **scaled to fit and
     centred with black bars** (`LetterboxFit`, small windows scale up). The pill stays excluded from the
     video after the switch (area: rebuild the exclusion). 4. Resume (only if step 1 paused), and hand
     focus back: to the picked window's app (window switch) or to the app that was frontmost before
     (area switch / Esc). Esc / clicking nothing = cancel → just resume. On failure show the HUD
     "Couldn't switch — still recording the previous window" / "…previous area" and keep recording the
     old target. A later **Restart** uses the switched-to target.
- **Restart** (two clicks, see Confirm). Stops the engine, **deletes the file recorded so far**, and runs
  the normal start path again on the current target with the same settings — **including the countdown**
  if one is configured. The pill, camera bubble, click/keystroke overlays stay up; the timer shows 0:00
  (greyed controls) until the new take starts.
- **Discard** (two clicks). Stops, **deletes the file**, tears everything down, **no Quick Access card**
  (the post-capture thumbnail card) **and no History entry**, then shows the toast "Recording discarded".
- **Confirm (Restart/Discard).** First click turns the button into the red "Restart?"/"Discard?" capsule
  for **3 s**; a second click within that time performs it. It reverts after 3 s, or immediately when
  Switch, Pause, Stop or the chevron is used or the recording stops (the Mic/System audio/Camera toggles
  don't cancel it). While one confirms, the other of Restart/Discard is hidden — the capsule takes its
  space so the pill keeps its size. Deliberately **not a dialog** — a modal would steal focus from the
  app being recorded.
- **Pause / Stop** as before (Stop during the countdown cancels the recording).
- **Chevron** toggles expanded/collapsed; the state persists.
- Hover hints: every control has one (table above), shown in the hint bubble — no tooltips.

### Data (persisted)

| Key | Type | Default | Meaning |
|---|---|---|---|
| `recordingPillCollapsed` | Bool | `false` (expanded) | chevron state, survives restarts of the app |
| `recordingPillAnchor` | String `"{x, y}"` | absent → bottom-centre | the pill's **bottom-right corner** in global screen coords (macOS: bottom-left origin, points). Used only if that spot is still on a connected screen. Windows: store right/bottom edges in DIPs (top-left origin). |

Nothing added to `RecordingConfig`. Mute / camera / target state is per session, not persisted.

### Pure logic to port 1:1 (with the macOS test cases)

**`SilenceFill`** (`Packages/RecordingKit/Sources/RecordingKit/SilenceFill.swift`, tests
`Tests/RecordingKitTests/SilenceFillTests.swift`). `silentSample(format)` → the bytes of one silent
sample, or null if the format isn't linear PCM (or has < 8 bits): float and signed-integer silence = all
zero bytes; **unsigned** = the midpoint (0x80 for 8-bit, 0x8000 for 16-bit …) placed in the format's
byte order. `fill(bytes, sample)` repeats the sample over the buffer from offset 0. `silentCopy(buffer)`
= a new buffer with the same format, sample count and timestamp whose data is all silence (the source is
never modified). Because every sample in a buffer has the same width, filling the whole data block works
for interleaved *and* per-channel (planar) layouts. Test cases:
- float32 → `[0,0,0,0]`; float64 → 8 zeros; int16 → `[0,0]`; int24 → `[0,0,0]`.
- uint8 → `[0x80]`; uint16 little-endian → `[0x00,0x80]`; uint16 big-endian → `[0x80,0x00]`.
- AAC (not LPCM) → null; 0-bit PCM → null.
- fill `[0x55 ×6]` with `[0x00,0x80]` → `[0x00,0x80,0x00,0x80,0x00,0x80]`.
- interleaved int16 stereo, 480 frames of 0x7F → one buffer of 1920 bytes, all 0.
- planar float32 stereo, 960 frames of 0x3F (the macOS system-audio shape) → two buffers of 3840 bytes, all 0.
- mono float32, 320 frames timestamped 2.0 s → same timestamp, same duration, 320 samples, same format; the source
  buffer still reads 0x3F.

Formats actually seen on macOS (probed 2026-09-24): system audio **48 kHz stereo float32 non-interleaved,
960 frames/buffer**; microphone (AVCaptureAudioDataOutput, Bluetooth headset) **16 kHz mono float32
non-interleaved, 320 frames/buffer**. On Windows, WASAPI shared-mode loopback/mic is normally 32-bit float
interleaved (`WAVE_FORMAT_IEEE_FLOAT`/extensible) — silence is zero bytes.

**`LetterboxFit`** (`LetterboxFit.swift`, tests `LetterboxFitTests.swift`). `rect(content, output)` → the
rectangle (output pixels, top-left origin) where content of size `content` lands when scaled to fit
`output` keeping its aspect ratio, centred: `scale = min(outW/cW, outH/cH)`, `w = min(outW,
round(cW·scale))`, `h = min(outH, round(cH·scale))`, `x = floor((outW−w)/2)`, `y = floor((outH−h)/2)`;
zero/negative content → the whole output. Test cases:
- 640×400 into 1280×800 → (0, 0, 1280, 800).
- 300×520 into 1280×800 → (409, 0, 462, 800).
- 1600×400 into 800×600 → (0, 200, 800, 200).
- 100×50 into 1000×500 → (0, 0, 1000, 500) (scales **up**).
- 0×0 or 10×0 into 1280×800 → (0, 0, 1280, 800).

**`RecordingPillLayout`** (`RecordingPillLayout.swift`, tests `RecordingPillLayoutTests.swift`).
`confirmPairButtonWidth(confirmWidths, spacing, minimum)` = `max(minimum, ceil((max(confirmWidths) −
spacing) / 2))` — the Restart/Discard icon-button width; `confirmSlotWidth(buttonWidth, spacing)` = `2 ·
buttonWidth + spacing`. `hintFrame(size, anchorX, pill, visible, gap, margin)` → the bubble rect
(bottom-left-origin screen coords): above the pill (`y = pill.maxY + gap`) if `pill.maxY + gap +
height ≤ visible.maxY`, else below (`y = pill.minY − gap − height`); `width = min(size.width,
visible.width − 2·margin)`; `x = round(clamp(anchorX − width/2, visible.minX + margin, visible.maxX −
margin − width))`. Test cases:
- confirm widths [66, 68], spacing 2, minimum 28 → 33, slot 68; [40, 30] → 28; [] → 28; [69] → 34 (slot 70).
- pill (400, 100, 600×40), visible (0, 0, 1470×900), size 200×24, anchorX 700, gap 6, margin 8 → (600, 146, 200, 24).
- pill at y 850 in the same screen → bubble y 820 (below), x 600.
- anchorX 20, pill (8, 100, 180×40) → x 8; anchorX 1460, pill (1280, 100, 182×40) → maxX 1462.
- visible (100, 0, 300×900), size 500×24, anchorX 250 → width 284, x 108.

### Engine behaviour (macOS `ScreenRecorder`) — what the port must reproduce

- `setMicMuted(bool)`, `setSystemAudioMuted(bool)`: flags read on the sample thread; while set, each
  buffer of that track is replaced by `SilenceFill.silentCopy` before it's written. Flags survive
  stop/start (the coordinator resets them per session).
- `retarget(filter, sourceRect)`: `SCStream.updateContentFilter` + `updateConfiguration` with
  `destinationRect = LetterboxFit.rect(new content size, output size)`, `scalesToFit = true`,
  `preservesAspectRatio = true`. Probed: window 640×400 → 300×520 → 200×120 → back, and area → area
  (different shapes): ~0.1 s per retarget, content centred with black bars, pill still excluded.
- `currentOutputURL` lets Restart/Discard delete the file even if finalizing fails.
- **Pause fixes found while building this** (both matter to Switch, which pauses):
  1. The newest frame that arrives while paused is kept and, restamped to the resume moment, becomes
     the first frame after resume — a static window switched to during the pause otherwise never sends
     a frame, and the video stayed on the old window.
  2. The resume gap is anchored on the **end of the last audio written** (or the pause moment when
     there's no audio), never earlier than the last video frame. The old anchor (last video frame only)
     put post-resume video **~0.9 s ahead of its audio** after pausing over static content (measured
     with a screen flash + a click sound: video ran 0.85–0.89 s ahead before the fix; after it the
     offset is 7–20 ms, the same as a recording without a pause, 2–19 ms).
  The port's segment-per-span pause doesn't have these PTS (presentation timestamp) problems — each
  segment is its own contiguous recording — but see the platform notes.

### Where it goes in the port

- Pill: the recording-controls window from §A (if §A named it differently, extend that one), e.g.
  `windows/src/BetterScreenshot.App/Recording/RecordingControlsWindow.xaml(.cs)` — a horizontal
  `StackPanel` with the metrics above; persist the two keys in
  `windows/src/BetterScreenshot.Platform/SettingsStore.cs`.
- Actions: `windows/src/BetterScreenshot.App/Recording/RecordingCoordinator.cs` — add `ToggleMicMute`,
  `ToggleSoundMute`, `ToggleCamera` (keep the `CameraBubbleWindow` instance, `Hide()`/`Show()` it in place),
  `SwitchTargetAsync` (reuse `_picker` / `_selection` exactly as `BeginWindow` / `BeginArea` do),
  `RestartAsync`, `DiscardAsync`; keep the current target (region + kind) for Restart.
- Engine: `windows/src/BetterScreenshot.App/Recording/RecordingEngine.cs` — `SetMuted(track, bool)`,
  `Retarget(PxRect)`, `Discard()`; `windows/src/BetterScreenshot.Recording/FfmpegArgs.cs` —
  `BuildRecording` gains an output size (scale + pad) and per-track mute (below).
- Pure logic: `windows/src/BetterScreenshot.Recording/LetterboxFit.cs`, `RecordingPillLayout.cs` (+
  `SilenceFill.cs` only if audio is captured in-process, option C below); tests in `windows/tests/BetterScreenshot.Tests/RecordingTests.cs`
  (or new `LetterboxFitTests.cs` / `SilenceFillTests.cs`).
- Icons (`windows/src/BetterScreenshot.App/Resources/Icons.xaml`): reuse `icon-mic`, `icon-speaker`,
  `icon-video`, `icon-trash`, `icon-play`, `icon-undo` (restart ↺); **add** mic-slash, speaker-slash,
  video-slash, pause, stop (filled square), window (`macwindow`), dashed rectangle (`rectangle.dashed`),
  chevron-left, chevron-right.

### Platform notes (where Windows must differ)

The port records with **one ffmpeg process per active span** (`gdigrab` region + `dshow` audio inputs →
H.264/AAC MP4 segment), pausing = end the segment, resuming = start a new one, and **concatenating the
segments with `-c copy` at stop**. A running ffmpeg can't change its inputs or region, so:

- **Switch window / area → new segment.** The macOS flow already pauses around the picker, so it maps
  directly: *pause* (end segment) → pick → *resume* with the new region. Concat with `-c copy` requires
  every segment to have the **same resolution and codec parameters**, so every segment must be encoded
  at the **first segment's even output size**: add
  `-vf scale=W:H:force_original_aspect_ratio=decrease:flags=lanczos,pad=W:H:(ow-iw)/2:(oh-ih)/2:black,setsar=1`
  (W×H = first segment's size; this is exactly `LetterboxFit`, centred black bars, scales small windows
  up). Keep identical `-r`, `-pix_fmt yuv420p`, encoder settings and the **same audio track layout** in
  every segment. The window picker's result on Windows is a rect (`WindowEnum.FrameBounds`), so a
  switched window is recorded as that rect (as today at start).
- **Mute → options, pick one:**
  - **A. New segment per toggle (simplest, fits the engine).** On toggle, end the segment and start a
    new one where the muted track's `dshow` input is replaced by a silent source with the same shape,
    e.g. `-f lavfi -i anullsrc=r=48000:cl=stereo`, still mapped to the same output track index and
    encoded with the same `-c:a aac -b:a 128k -ar 48000 -ac 2` (the track count must not change or
    `-c copy` concat breaks). Cost: each toggle loses the ~0.3–1 s it takes ffmpeg to restart (screen
    content in that moment isn't captured), unlike pause where that time is meant to be skipped.
  - **B. Runtime volume (no gap).** Build each audio input through a named filter
    (`[1:a]volume@sys=1[a1]`) and change it live with ffmpeg's `azmq` filter (needs an ffmpeg build with
    libzmq; check `ffmpeg -filters | findstr zmq`) → `volume@sys volume 0`. Exact parity, no restart.
  - **C. In-process audio (exact parity, most work).** Capture system audio (WASAPI loopback) and mic
    (WASAPI capture) in C# (e.g. NAudio), zero muted buffers with a C# `SilenceFill`, write one WAV per
    track, and mux them with the video at stop (`ffmpeg -i video.mp4 -i sys.wav -i mic.wav -map 0:v -map
    1:a -map 2:a -c:v copy -c:a aac …`). Pause then drops audio buffers the same way it drops segments.
  Recommendation: **A** first (small change, matches how pause works), B if the owner notices the gaps.
- **Restart** = stop the current ffmpeg, delete all segments of this session (don't concat), start a new
  session on the same region/config (countdown again). **Discard** = stop, delete segments, no concat,
  no history, no card, HUD "Recording discarded".
- **Excluding the pill from the video.** `gdigrab` captures the desktop DC, so the pill needs
  `SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)` (Windows 10 2004+) unless "Show recording
  controls in the video" is on — verify with a probe recording that it hides the window from `gdigrab`; if not, fall
  back to `ddagrab` (Desktop Duplication honours it). It's per-window, so it survives a switch.
- **Focus.** The pill must never activate (`WS_EX_NOACTIVATE`, `ShowActivated=false`, handle
  `WM_MOUSEACTIVATE` → `MA_NOACTIVATE`). Test that the hover hint bubble and hover highlights still
  appear while another app is focused (macOS needed hover tracking that is active even when the app
  isn't). Draw the bubble inside the pill's own window (or give its window the same
  `WDA_EXCLUDEFROMCAPTURE`) so it never shows up in the video.
- **Camera bubble show/hide:** keep the `CameraBubbleWindow` instance and `Hide()`/`Show()` it so a
  dragged position survives; stop the camera while hidden.

---

## Part 6 — Video editor v2 (cut, per-segment speed/mute, GIF export)

**What it is.** The recording trim window (opened by a recording's Quick Access card ✂ **Trim** button,
or History's **Edit Video…**; MP4 only) is now a small video editor. It replaces AVKit's single-range "yellow
handles" trim mode with our own filmstrip timeline: split the clip at the playhead, delete segments,
drag segment edges, give each segment a speed (1× / 1.5× / 2× / 4×) or mute it, undo / redo, and export
as a copy, as a GIF, or over the original. Nothing touches the original file until an export. The Part 0
card-restore rule applies to every way the window closes.

**Terms.** *Source time* = seconds in the original recording. *Output time* = seconds in the exported
video (kept segments back to back; a 2× segment lasts half as long). *Timeline time* = what the timeline
draws: kept segments at their output length, cuts at their source length. *Cut list* = the ordered kept
segments (the model, `CutList`). *Passthrough* = copying the compressed video without re-encoding
(lossless, instant, but can only start on a *keyframe*); *re-encode* = decode + encode every frame
(exact on any frame, takes seconds).

### Layout (exact)

Snapshots from the headless probe (1× PNGs): `docs/parity-v3/part6-editor.png` (two segments, a cut, the
second segment at 2× and auto-muted), `part6-edge-drag.png` (dragging segment 1's end edge — the preview
shows the frame under the handle), `part6-exporting.png` (progress bar), `part6-min-size.png` (minimum
window size, one segment). Those predate the 2026-09-25 UI-review fixes (time ruler, progress slot in the
hint line, `Mute whole video`, error state, Replace Original disabled until an edit); the current look is in
`docs/reviews/2026-09-25-ui-fixes/video-01-ruler-cuts-2x.jpg` … `video-05-broken-file.jpg` (Retina JPEGs;
the big timestamps inside the thumbnails are the test clip's own burned-in frame times, not app labels).

```
┌─ Edit Video — Recording 2026-09-24 at 12.00.00.mp4 ──────────────────────────────────────────┐
│                                                                                              │
│                 video preview — black letterbox, aspect-fit; click = play / pause            │
│                                                                                              │
│ ╭──────────────────────────────────────────────────────────────────────────────────────────╮ │
│ │ ▶  0:05.0 / 0:10.5   [✂ Split] [🗑 Delete] │ [↶] [↷]                  🔍−  ──●──────  🔍+ │ │
│ │ |0:00 |0:01 |0:02 |0:03 |0:04           ●0:05 |0:06 |0:07  (time ruler · ● playhead)     │ │
│ │ ╭────────────────────────╮░░░░░░░✂░░░░░░░▐▌[2×][🔇] filmstrip — selected (yellow)   ▐▌ │ │
│ │ │ filmstrip (segment 1)  │░ cut, dimmed ░│▐▌                                        ▐▌ │ │
│ │ ╰────────────────────────╯░░░░░░░░░░░░░░░▐▌━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━▐▌ │ │
│ │ Segment 2 of 2  0:09.0 – 0:20.0    Speed [ 1× | 1.5× | 2× | 4× ]   ☑ Mute segment       │ │
│ │ ⓘ Sped-up segments are muted so the audio doesn't sound rushed — untick Mute segment …   │ │
│ ╰──────────────────────────────────────────────────────────────────────────────────────────╯ │
├──────────────────────────────────────────────────────────────────────────────────────────────┤
│ 0:10.5 kept of 0:20.0   ☐ Mute whole video           [Cancel] [Save as Copy │▾] [Replace Original] │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Window.** Title `Edit Video — <file name>`. Content 960 × 720 pt at open (centred), resizable, minimum
frame 780 × 560 pt. Always dark (dark appearance); window background `#171717` (white 0.09).
Only one editor window exists at a time (opening another file closes the current one — Part 0).

**Preview** (top, full width, down to 12 pt above the card; min height 200): plays the edit exactly as it
will export (removed parts skipped, speeds applied, muted segments silent). No player controls on it; a
click toggles play / pause.

**Card** (dark HUD panel: translucent dark material, corner radius 12, 1 px border white 10%), inset 12 pt
from the window's left/right edges and 12 pt above the action bar. Padding 12 top/bottom, 14 left/right;
rows 10 pt apart (8 pt between the segment row and the hint line). Four rows:

1. **Transport / edit row** (≈ 28 pt tall, items 8 pt apart, left to right):
   | Item | Look | Tooltip (verbatim) | Shortcut | Enabled when |
   |---|---|---|---|---|
   | Play / Pause | borderless icon, `play.fill` ↔ `pause.fill`, 15 pt semibold, white 85% (30% when disabled), 29 pt wide | `Play (Space)` / `Pause (Space)` | Space | loaded, not exporting |
   | Time | `0:05.0 / 0:10.5` = playhead / edit length (output time), 12 pt monospaced-digit medium, white 85%, min width 116 | `Playhead / length of the edit` | — | — |
   | (10 pt gap) | | | | |
   | **Split** | rounded push button, `scissors` 12 pt + "Split" | `Split the segment at the playhead (S or ⌘B)` | S, ⌘B | the playhead is ≥ 0.1 s inside a segment |
   | **Delete** | rounded push button, `trash` + "Delete" | `Delete the selected (yellow) segment (⌫)` | ⌫ / Delete | more than one segment |
   | divider | 1 × 18 pt, white 15% | | | |
   | Undo | rounded push button, icon only `arrow.uturn.backward` | `Undo (⌘Z)` | ⌘Z | something to undo |
   | Redo | rounded push button, icon only `arrow.uturn.forward` | `Redo (⇧⌘Z)` | ⇧⌘Z | something to redo |
   | (flexible space) | | | | |
   | Zoom out | borderless `minus.magnifyingglass` 12 pt, 26 pt wide, white 85% (30% when disabled) | `Zoom out the timeline` | — | zoom > 1 (÷ 1.5 per click) |
   | Zoom slider | small slider, 110 pt wide, 1…12 (1 = fit to width), continuous | `Timeline zoom` | — | loaded |
   | Zoom in | borderless `plus.magnifyingglass` 12 pt, white 85% (30% when disabled) | `Zoom in the timeline` | — | zoom < 12 (× 1.5 per click) |
2. **Timeline** — 74 pt tall (a 14 pt time ruler over the track), full card width, scrolls horizontally when zoomed (overlay scroller, no
   bounce). Tooltip: `Click to move the playhead and pick a segment · drag a yellow edge to trim · right-click for speed and mute`.
   Drawing spec below.
3. **Selected-segment row** (items 8 pt apart): `Segment 2 of 3` (11 pt semibold, white 90%) ·
   `0:09.0 – 0:20.0` (the segment's **source** range; 11 pt monospaced-digit, white 50%; tooltip
   `Where this segment comes from in the original recording`) · 14 pt gap · `Speed` (11 pt, white 60%) ·
   small segmented control `1×` `1.5×` `2×` `4×` (each 40 pt wide; tooltip
   `Play this segment faster (sped-up segments start muted)`) · 10 pt gap · small checkbox
   `Mute segment` (11 pt; tooltip `Silence this segment's audio (the rest keeps its sound)`; shown ticked
   and disabled while whole-file **Mute whole video** is on).
4. **Hint line**: `info.circle` 11 pt (white 45%) + one sentence, 11 pt white 55%, truncated at the end if
   too long. Text (first match wins, verbatim):
   1. exporting → `Exporting — the original stays untouched until it's done.`
   2. Mute whole video ticked → `Mute whole video is on: the saved video will have no sound at all.`
   3. selected segment sped up and muted → `Sped-up segments are muted so the audio doesn't sound rushed — untick Mute segment to keep it.`
   4. selected segment sped up, not muted → `Sped-up audio keeps its pitch but plays faster.`
   5. only one segment → `Move the playhead, then press S (or ⌘B) to split · drag the yellow edges to trim · I / O set in / out`
   6. otherwise → `Click a segment to select it · ⌫ deletes it · right-click for speed and mute · Space plays the edit`

   **Export progress** has its own slot at the right end of the hint line (after a flexible space),
   shown only while an export runs: a small bar, 160 pt wide, then the percentage `42%` (11 pt
   monospaced-digit, white 60%, 34 pt wide, right-aligned). A passthrough copy shows the bar
   indeterminate (animating) and no percentage. The hint row is fixed at 16 pt tall, so showing the
   progress moves nothing — not the hint, not the card, not the action bar.

**Action bar** (bottom, 52 pt tall, standard header material, 1 px separator on top; row inset 16 pt,
items 10 pt apart): kept label (12 pt monospaced-digit, secondary colour; tooltip
`Length of the saved video / length of the recording`; stays visible while exporting) · 4 pt gap ·
checkbox `Mute whole video` (tooltip `Save without any sound`) · flexible space · **Cancel** (tooltip
`Close without saving`; reads **Done** with tooltip `Close the editor` after Replace Original, and
**Close** with the same tooltip when the file can't be opened) · **Save as Copy ▾** — a split
button: the main part saves a copy, the ▾ opens a menu with one item `Export as GIF` (tooltip on the
button `Save the edit as a new file next to the original — the ▾ menu exports a GIF`; on the item
`Save the edit as an animated GIF next to the original (10 fps, up to 960 px wide)`) · **Replace
Original** (accent-tinted, deliberately **no** Return shortcut; tooltip
`Overwrite the original recording with the edit`). Replace Original is enabled only when the video would
differ from the file — the cut list isn't the untouched whole recording, or Mute whole video is ticked —
so it's disabled on a fresh open and right after a replace; while disabled for that reason its tooltip
is `Make an edit first — the original already matches this video`.

Kept label texts (verbatim; times are `m:ss.t`, rounded to tenths — `TrimRange.timestamp`):
`Loading…` · (empty when the file can't be opened) · `Whole recording · 0:45.0` (nothing edited)
· `0:31.2 kept of 0:45.0` · and one-off notes that stay until the next edit: `Edited ✓ original replaced · 0:31.2`,
`GIF saved ✓ <gif file name>`, `Couldn't export the edit — original untouched`,
`Couldn't export the GIF — nothing was changed`.

**Error state** (the file is missing, or can't be read as a video): the preview and the whole card are
hidden and a centred block fills their space (window background, everything above the action bar):
`exclamationmark.triangle` 34 pt (white 60%) · 14 pt · title 15 pt semibold white · 6 pt · message 12 pt
white 60%, centred, wrapping at 400 pt · 18 pt · **Show in Finder** (rounded button, tooltip
`Select the file in a Finder window`; selects the file in Finder). Texts (verbatim):
- file missing → `This recording can't be found` / `It may have been moved, renamed or deleted. Close this
  window, then open the recording again from its new place.` (no Show in Finder button);
- otherwise → `This video can't be opened` / `The file may be damaged or still being saved. Close this
  window and try again in a moment, or check the file in Finder.`

The action bar stays: kept label empty, Mute whole video / Save as Copy / Replace Original disabled,
Cancel reads **Close**.

**Icons** (SF Symbol → port icon key in `windows/src/BetterScreenshot.App/Resources/Icons.xaml`):
`play.fill` → `icon-play`; `trash` → `icon-trash`; `arrow.uturn.backward` / `.forward` → `icon-undo` /
`icon-redo`. **New glyphs to author:** `pause.fill` → `icon-pause`, `scissors` → `icon-scissors`,
`minus.magnifyingglass` / `plus.magnifyingglass` → `icon-zoom-out` / `icon-zoom-in`, `info.circle` →
`icon-info`, `speaker.slash.fill` → `icon-speaker-off`.

### Timeline — drawing spec

- 12 pt inset at both ends. Scale (pt per timeline second) = (view width − 24) ÷ timeline length; view
  width = visible width × zoom. Track: y 18 … height − 6 (50 pt of a 74 pt view); behind it a rounded
  rect (radius 8, black 35%) 2 pt in from the sides and 3 pt beyond the track top/bottom.
- **Time ruler** (y 0 … 14, above the track): ticks at round **output** times — the edit's clock, the
  same one the playhead readout uses — over the kept segments only (cuts aren't in the output, so they
  get no ticks). Label step = the smallest of 0.1 · 0.2 · 0.5 · 1 · 2 · 5 · 10 · 15 · 30 s · 1 · 2 · 5 ·
  10 · 15 · 30 · 60 min whose widest label + 3 + 12 pt fits between two ticks; minor ticks divide each step
  into 2 · 2 · 5 · 4 · 4 · 5 · 5 · 3 · 6 · 4 · 4 · 5 · 5 · 3 · 6 · 4 parts and are left out when closer than
  4 pt. A segment covers output times [start, end) — where two segments meet, their shared time is ticked
  once. Major tick: 1 pt, white 30%, y 1 … 14; minor: white 18%, y 11 … 14. Label: 9 pt monospaced-digit
  medium, white 55%, drawn at (tick + 3, 0); `0:05` / `1:30` for whole-second steps, `0:04.5`
  (`TrimRange.timestamp`) for finer ones. Labels are placed left to right and a label is left off (its
  tick stays) if it would start < 12 pt after the previous label ends or end past the view's right edge
  − 2 pt — so labels never overlap, repeat or get clipped. Pure logic: `TimeRuler` (below).
- **Kept segment**: its rect inset 1 pt left/right (so adjacent segments show a 2 pt gap), radius 6,
  filled with the filmstrip, 1 px border white 22%.
- **Filmstrip**: tiles `track height × video aspect` wide (clamped 24…160 pt), starting at each block's
  left edge; each tile aspect-fills the thumbnail nearest to the **source** time at the tile's centre
  (so a 2× segment shows twice the footage per tile). Thumbnails (`FilmstripFrames`): enough that fully
  zoomed-in tiles don't repeat a frame — `count = min(max(⌈screen width × 12 ÷ narrowest tile⌉, 12), 400,
  max(12, ⌊duration × 30⌋))`, narrowest tile = a cut's (track height − 8) × aspect, clamped 24…160 — at
  `(k + 0.5) × duration / count`, max 200 × 200 px, loaded in the background **coarse to fine** (every 8th
  frame first, then every 4th, every 2nd, the rest; each tile shows the nearest frame loaded so far);
  until the first arrives tiles are grey 22%. (20 s clip on a 1728 pt screen: 263 frames in 0.7 s.)
- **Cut** (removed range): its rect inset 1 pt left/right and 4 pt top/bottom, radius 4; filmstrip, then
  black 66%, then 45° hatch lines (white 9%, 1.5 pt, every 7 pt), and a centred `scissors` glyph (11 pt,
  white 45%) if the block is ≥ 22 pt wide. Cuts before the first and after the last segment are drawn too.
- **Badges** (top-left of a kept segment, 5 pt from its left, 4 pt from the top): 16 pt-tall fully rounded
  pills, black 70%, 5 pt side padding, 4 pt apart: the speed (`1.5×`, `2×`, `4×`; 10 pt bold white) when
  not 1×, then `speaker.slash.fill` (9 pt bold white) when muted. A badge that doesn't fit is skipped.
- **Selection** (exactly one segment is always selected): system-yellow 2.5 pt border (radius 6) plus two
  solid yellow handles, 10 pt wide (or a third of the segment if narrower), radius 4, each with a centred
  2 × 14 pt grip (black 55%).
- **Playhead**: 8 pt white circle knob at y 9.5 (just under the ruler labels, so it never covers one) and
  a 2 pt white line from the knob to the bottom, soft
  shadow (black 60%, blur 2). While playing, the view scrolls so the playhead stays visible (re-anchored
  at 15% from the left when it leaves).
- **Cursor**: left-right resize cursor within ±7 pt of any kept segment's edge.

### Behaviour

**Mouse on the timeline.**
- Click a kept segment → select it and move the playhead to that point; keep dragging to scrub.
- Click a cut → the playhead jumps to the start of the next kept segment (or the end if none); drag scrubs.
- **Edge drag** (press within ±7 pt of a kept segment's edge; if two edges are in reach, the selected
  segment's wins, otherwise the one on the pointer's side of the shared boundary). The segment becomes
  selected, playback pauses, and the preview switches to the plain source showing the frame at the edge
  (start edge: the new first frame; end edge: the frame 1/60 s before the new end). The scale is frozen
  during the drag so the edge stays under the pointer: start edge → `newStart = previousKeptEnd (or 0) +
  (pointerTimeline − displayStartOfTheCutBefore)`; end edge → `newEnd = start + (pointerTimeline −
  segmentDisplayStart) × speed`; then clamped by `CutList.setStart/setEnd` (can't cross a neighbour, ≥ 0.1 s
  long). Dragging an edge into a cut brings that footage back. Release = **one** undo step; the preview is
  rebuilt with the playhead at the segment's new start (start edge) or 1/60 s before its end (end edge).
- Right-click a kept segment → selects it and shows: `Speed ▸` (`1× (normal)`, `1.5×`, `2×`, `4×`, current
  one checked) · `Mute Segment` (checked when muted; disabled while Mute whole video is on) · separator ·
  `Split at Playhead ⌘B` (enabled like the Split button) · `Delete Segment ⌫` (disabled with one segment).

**Edits** (each is one undo step; a refused edit beeps and changes nothing):
| Edit | Trigger | Rule | Selection after | Playhead after |
|---|---|---|---|---|
| Split | S, ⌘B, Split, menu | splits the segment under the playhead into two with the same speed + mute; refused within 0.1 s of a segment edge | the **left** half (so "split, move, split, ⌫" removes the middle) | unchanged |
| Delete | ⌫ / Delete key, button, menu | removes the selected segment; the last one can't be removed | the segment now at that position (or the new last) | where the deleted segment began |
| In point | I | drops everything before the playhead | first segment | 0 |
| Out point | O | drops everything after the playhead | last segment | 1/60 s before the end |
| Speed | segmented control, menu | 1× → faster also **mutes** the segment; back to 1× **unmutes**; changing between faster speeds keeps the current mute | same | same source frame |
| Mute segment | checkbox, menu | toggles the selected segment's audio | same | unchanged |
| Undo / Redo | ⌘Z / ⇧⌘Z, buttons | whole cut-list states | clamped to the segment count | same source frame if still kept, else 0 |

Other keys: **Space** play / pause (restarts from 0 when at the end); **← / →** pause and step one frame.
Plain-key shortcuts are ignored while a ⌘/⌥/⌃ modifier is held and while exporting. The whole-file
**Mute whole video** box mutes the preview immediately and makes the export drop all audio.

**Exports** (all controls, Cancel and the close box are disabled while one runs; failures leave the
original untouched and show the note above):
- **Save as Copy** → `<stem> (trimmed).mp4` next to the original (`TrimmedFileName`, " 2", " 3"… on
  collision). The window closes; the copy gets its own Quick Access card + History entry; the original's
  card comes back (Part 0).
- **Export as GIF** → renders the edit (always without sound) to a temporary MP4, converts it with the
  existing GIF exporter (10 fps, ≤ 960 px wide, loops) to `<stem> (edited).gif` next to the original
  (uniquified). The window **stays open**; the kept label shows `GIF saved ✓ <name>`; the GIF gets a card +
  History entry. Progress: first half = render, second half = GIF frames.
- **Replace Original** → export to a temp file on the same volume, then an atomic swap. The window stays
  open and reloads the new file: a fresh single-segment cut list (undo history cleared), Mute whole video
  unticked, Replace Original disabled until the next edit, Cancel reads **Done**, note `Edited ✓ original replaced · <new length>`; a HUD says
  `Recording edited`.
- **Passthrough or re-encode:** passthrough (lossless, instant) when the cut list is one contiguous
  stretch at 1× with a single mute state — a plain start/end trim (adjacent split pieces count as
  contiguous; all-muted = whole-file mute). Everything else — a middle cut, any speed change, mixed
  per-segment mute — is **re-encoded**: H.264 highest quality at the source's frame rate (clamped 30…60
  fps), AAC audio, sped audio time-stretched with its pitch kept. A recording with two audio tracks
  (system audio + microphone) keeps both as separate tracks in either path (probed), exactly like the
  original recording.
- **Recording change:** new recordings get a keyframe at least every 0.5 s (was the encoder default),
  so passthrough trims start close to the chosen frame.

**Timing (probe, M3 MacBook, macOS 26.6, other builds running):** 60 s 1080p60 source, keep
[0,20] [25,45] [50,60] (50 s): passthrough trim 0.06 s; re-encode **14.3 s** (PSNR 56–60 dB vs the source
— visually lossless); same with the middle segment at 2× (40 s out) 14.2 s.

**macOS-specific findings** (why the mac code looks the way it does — not needed on Windows, but explains
the rules): `AVAssetExportPresetHighestQuality` does **not** re-encode a plain cut composition — it copies
the samples and hides the extra frames behind an MP4 edit list (3 edit-list entries, 0.07 s), which only
edit-list-aware players honour, so the mac export always renders through a video composition to force a
real re-encode; and a sped-up segment followed by the next stretch of the same source fails to export
(AVFoundation error -16364) without one.

### Data

No new persisted settings. `RecordingConfig.keyFrameInterval = 0.5` (seconds) is a constant, not a user
setting.

### Pure logic to port 1:1 (with the macOS tests)

`CutList` (`Packages/RecordingKit/Sources/RecordingKit/CutList.swift`), a value type:
- `duration` (source seconds); `segments: [CutSegment]` — never empty, ordered, non-overlapping; a
  segment = `start`, `end` (source seconds), `speed` (one of `speeds = [1, 1.5, 2, 4]`), `muted`.
  `length = end − start`; `outputLength = length / speed`. `minimumSegment = 0.1`; comparisons use ε = 1e-6.
- `init(duration:)` → one segment `[0, duration]`; `init(range:duration:)` → the single-segment case of a
  plain trim (`TrimRange`).
- `keptDuration` = Σ outputLength. `outputStart(of: i)` = Σ outputLength before i.
  `segmentIndex(atOutput: t)` — a boundary belongs to the later segment, the very end to the last.
  `sourceTime(forOutput:)`, `segmentIndex(containingSource:)` (shared boundary → later segment; the
  last segment's end is inclusive), `outputTime(forSource:)` (nil inside a cut).
- `passthrough` → `(range, muted)` when all segments are adjacent (|a.end − b.start| ≤ ε), all at 1×, all
  with the same mute; else nil.
- Edits return false and change nothing when they can't apply: `split(atSource:)` (needs t within
  [start + 0.1, end − 0.1] of a segment; both halves keep speed + mute) · `remove(at:)` (not the last
  segment) · `setStart(_:of:)` clamped to [previous end or 0, own end − 0.1] · `setEnd(_:of:)` clamped
  to [own start + 0.1, next start or duration] · `setSpeed(_:of:)` (only listed speeds; 1× → faster sets
  muted; → 1× clears it) · `setMuted(_:of:)` · `trimBefore(source:)` (in point: drop segments ending ≤ t,
  clip the first to start at t but keep ≥ 0.1 s) · `trimAfter(source:)` (out point, mirrored).
- Timeline: `timeline` = items in order — a `removed` item for every gap > ε (including before the first
  and after the last segment) with display length = its source length, and a `kept(i)` item with display
  length = the segment's output length. `timelineLength`, `timelinePosition(forOutput:)`,
  `outputTime(forTimelinePosition:)` (inside a cut → the next kept segment's output start, or
  `keptDuration` if none), `sourceTime(forTimelinePosition:)` (cuts 1:1, kept at × speed — for the filmstrip).
- `CutHistory`: `current`, undo and redo stacks of whole `CutList` values. `commit(list)` pushes the
  current value only if `list` differs and clears redo; `apply(edit)` = edit a copy, commit on success;
  `undo()` / `redo()` return false when empty. An edge drag edits a working copy and commits once on release.

Test cases (`Tests/RecordingKitTests/CutListTests.swift`; re-create them): whole recording is one segment
(kept 45, passthrough [0,45] unmuted) · `TrimRange` is the single-segment case · split at 3 then 7 of 10 →
[0,3][3,7][7,10] · split keeps speed / mute · split refuses 0.05, 9.95, 0 and an existing split point ·
split inside a cut fails · remove the middle → kept 7, can't remove index 5 or the last segment · kept
duration with speeds ([0,2] + [4,8] at 2× = 4; 8 s at 4× = 2; at 1.5× = 5.333…) · speed mutes by default
and an explicit unmute survives 2×→4×, back to 1× unmutes, 3× is refused, no-op returns false · edge drags
clamp to neighbours and the minimum ([0,3][6,10]: start 4 ok, start 1 → 3, end 9.99 refused, end 0 → 0.1,
start 99 → 9.9) · in/out ([0,3][3,6][6,10]: in 4 → [4,6][6,10]; out 8 → [4,6][6,8]; out 6 → [4,6]; in at
9.99 of a fresh list → start 9.9) · output/source mapping on [0,2] + [4,8]@2× (output 1 → 1, 3 → 6, 4 → 8;
source 6 → output 3, source 3 → nil; output 2 → segment 1) · passthrough: a split alone → [0,10]; both
muted → muted; mixed mute, a middle cut, 1.5× → nil; start 1 / end 9 → [1,9] · timeline of [0,2] + [4,8]@2×
of 10 s = kept(0) 0–2, removed 2–4, kept(1) display 4–6, removed display 6–8 (length 8); output 3 ↔
timeline 5; a click at 3 → output 2, at 7.5 → output 4; source at timeline 3 → 3, at 5 → 6 · history:
split, remove, refused remove adds no step, undo ×2, redo, a committed drag is one step and clears redo.

`TrimmedFileName` gained a suffix and an extension: `name(forOriginal:suffix:ext:)` /
`unique(forOriginal:suffix:ext:exists:)`, suffix `trimmed` (default) or `edited`; an existing
` (trimmed)` or ` (edited)` suffix, with or without ` N`, is stripped first. Tests:
`Recording 2026-09-24 at 10.00.00.mp4` → `… (edited).gif`; `Rec (trimmed).mp4` and `Rec (trimmed) 2.mp4` →
`Rec (edited).gif`; `Rec (edited).mp4` → `Rec (trimmed).mp4`; with `Rec (edited).gif` taken →
`Rec (edited) 2.gif` (plus the existing `(trimmed)` cases).

AV tests on a generated MP4 (10 fps, grey level 8·i in frame i, optional 440 Hz tone): a 3-segment cut
([0,1] [1.5,2] [2.5,3]) is 2 s with video + audio and each sampled output frame matches the source frame
it maps to (grey level within 3) even off-keyframe; [0,2] at 2× + [2,3] is 2 s with audio and frame-exact;
a muted first segment is silent (RMS < 0.01) while the rest keeps its tone (> 0.1); a start/end trim plus
a split stays passthrough (1.5 s, audio kept); GIF of the 3-segment cut ≈ 20 frames, named
`Recording (edited).gif` then `Recording (edited) 2.gif`, no temp file left; Replace Original with cuts
leaves only the original, now 2 s; a failed export leaves the original's bytes unchanged.

`TimeRuler` (`Packages/RecordingKit/Sources/RecordingKit/TimeRuler.swift`, UI-review fix 2026-09-25): input
= the kept segments as drawn (`Span`: x, width in pt, output time at the left edge), points per second,
the right limit `maxX`, and a label-width function; output = ticks left to right (`time`, `x`, `major`,
`label` or none). Rules exactly as in the drawing spec (step table, minor divisions, half-open spans,
greedy label drop). Tests (`TimeRulerTests.swift`, labels measured at 6 pt per character): formats
`0:05` / `1:05` / `60:00` / `0:04.5`, 3 × 0.1 → `0:00.3`; step at 50 pt/s → 1 s, 38 → 2 s, 520 → 0.1 s, an
hour at 936 pt → 5 min; 20 s over 1000 pt → labels 0…19 (not 20), 60 minor ticks; a 4 s cut → no ticks
over it, 0:05 at the next segment's left edge; a split at 5 s (±1e-9 noise) ticks 5 once; a 0:02 tick
right under the 0:01 label keeps its tick but drops its label; the last label is dropped rather than
clipped; 12× zoom → 200 unique, evenly spaced labels; nothing loaded → no ticks.

`FilmstripFrames` (`FilmstripFrames.swift`): `count(duration:timelineWidth:tileWidth:)` and
`times(duration:count:)` as in the drawing spec. Tests: 20 s, 1728 × 12 pt, 80 pt tiles → 260; an hour on
5120 pt → 400; 1 s → 30; 0.2 s and 0 s → 12; 16 frames of 16 s → every `k + 0.5` once, order starting
0.5, 8.5, 4.5, 12.5.

### Where it goes in the port

- Pure: `windows/src/BetterScreenshot.Recording/CutList.cs` (+ `CutHistory`), `TrimRange.cs`,
  `TrimmedFileName.cs`, and `FfmpegArgs.BuildCutExport(...)` / `BuildPassthroughTrim(...)` next to
  `BuildGifConversion` in `windows/src/BetterScreenshot.Recording/FfmpegArgs.cs` (unit-test the strings).
- UI: new `windows/src/BetterScreenshot.App/Recording/VideoEditorWindow.xaml(.cs)` + a custom-drawn
  `CutTimeline` `FrameworkElement` (OnRender) in the same folder; dark theme from `Resources/Theme.xaml`,
  the card from `Controls/DarkSection.cs`-style chrome.
- Entry points: `QuickAccessActions.OnTrim` (`Overlays/QuickAccessTypes.cs`) + a Trim button on MP4
  recording cards (`Overlays/QuickAccessWindow.xaml`), wired in `Capture/CaptureCoordinator.ShowRecordingCard`
  with the Part 0 `restoreCard`; an `Edit Video…` command in `History/HistoryWindow.xaml(.cs)`. Copy / GIF
  results go through `CaptureCoordinator.OnRecordingFinished(path, thumbnail)`.
- Running ffmpeg: `windows/src/BetterScreenshot.Platform/FfmpegRunner.RunAsync` (add a progress callback
  that parses `-progress pipe:1` output); GIF via `Recording/GifExporter.ConvertAsync` (it deletes its
  source MP4 on success — fine for the temp render).

### Platform notes (ffmpeg instead of AVFoundation)

- **Passthrough trim** (plain start/end, 1×): `ffmpeg -y -ss <start> -to <end> -i in.mp4 -c copy
  -avoid_negative_ts make_zero -movflags +faststart out.mp4` (add `-an` for Mute whole video). `-ss` before `-i`
  with `-c copy` starts on the keyframe at or before `start` — hence the 0.5 s keyframes below.
- **Re-encode** (cuts / speed / per-segment mute) — one `filter_complex`, one segment per `trim`/`atrim`
  pair, speed via `setpts` + `atempo` (pitch-preserving; chain `atempo=2,atempo=2` for 4× on ffmpeg builds
  that cap one `atempo` at 2.0), mute via `volume=0` (keeps the audio stream continuous), then `concat`.
  Example — keep [0,20], [25,45] at 2× (auto-muted), [50,60]:
  ```
  ffmpeg -y -i in.mp4 -filter_complex "
   [0:v]trim=start=0:end=20,setpts=PTS-STARTPTS[v0];
   [0:a]atrim=start=0:end=20,asetpts=PTS-STARTPTS[a0];
   [0:v]trim=start=25:end=45,setpts=(PTS-STARTPTS)/2[v1];
   [0:a]atrim=start=25:end=45,asetpts=PTS-STARTPTS,atempo=2,volume=0[a1];
   [0:v]trim=start=50:end=60,setpts=PTS-STARTPTS[v2];
   [0:a]atrim=start=50:end=60,asetpts=PTS-STARTPTS[a2];
   [v0][a0][v1][a1][v2][a2]concat=n=3:v=1:a=1[v][a]"
   -map "[v]" -map "[a]" -r <source fps, 30…60> -c:v h264_nvenc -preset p5 -cq 19 -pix_fmt yuv420p
   -c:a aac -b:a 128k -movflags +faststart -progress pipe:1 -nostats out.mp4
  ```
  Use `h264_nvenc` when available (the owner's PC has an RTX 3060 Ti), else `libx264 -preset veryfast
  -crf 18`. Mute whole video: no `atrim` chains, `concat=n=N:v=1:a=0`, `-an`. Two audio tracks
  (system + mic — the port records them as separate dshow tracks too): run the `atrim…` chain on
  `[0:a:0]` and `[0:a:1]` for every segment, use `concat=n=N:v=1:a=2`, and `-map` both audio outputs so
  the result keeps two tracks like the mac export. The progress fraction =
  `out_time_ms / (keptDuration × 1e6)`.
- **Export as GIF**: render the edit as above (with `-an`) to a temp MP4, then
  `FfmpegArgs.BuildGifConversion(temp, "<stem> (edited).gif")`.
- **Keyframes while recording**: add `-g <fps / 2>` (or `-force_key_frames "expr:gte(t,n_forced*0.5)"`)
  to the H.264 output in `FfmpegArgs.BuildRecording`.
- **Preview**: WPF's `MediaElement` can't play a cut list; play the source and skip through the list
  (at a segment's end jump to the next segment's start; set `SpeedRatio` per segment; set `IsMuted` for
  muted segments), and step frames with pause + position ± 1/fps. For the edge-drag preview just seek to
  the edge time. Thumbnails: one ffmpeg pass `-vf "fps=<count/duration>,scale=-2:100"` to numbered PNGs
  in a temp folder, or `-ss t -frames:v 1` per tile.

---

## Window placement — centred, reopens as last closed (owner request 2026-09-25)

**Why:** the annotation editor was created at screen position (0, 0) and never centred, so it opened in
the **bottom-left corner**; the other windows used AppKit's `center()`, which sits about a third of the
way down, not in the middle. The owner wants every window **exactly centred**, and a window that was last
**full screen** (or covering the whole screen) to come back that way.

**Behaviour (macOS, as built):**
- Every app window — Annotate, Edit Video, History, Settings, Welcome — opens **exactly centred** in
  the *visible* area (screen minus menu bar and Dock) of the screen **under the mouse pointer**, shrunk to
  fit that area if it's bigger. A window that's already open is just brought forward, not moved.
- **Annotate, Edit Video and History** (the resizable ones) also reopen the way the **last window of that
  kind was closed**:
  - closed at some size → the same size, centred (never below the window's minimum size);
  - closed covering the whole visible screen (zoomed/Fill, or dragged to the edges — within 8 pt on
    both axes) → covers the whole visible screen of the screen it opens on;
  - closed in **full screen** (green button) → opens, then goes full screen; leaving full screen
    returns it to the centred size it had before full screen.
  - Nothing remembered yet → the window's own default size (the editor's default still comes from the
    image's real size, as in Part 1), centred.
- Settings and Welcome are fixed-size: centred only.

**Data:** per window kind, UserDefaults key `windowPlacement.<kind>` (`annotate`, `editVideo`, `history`)
= JSON `{"width": <pt>, "height": <pt>, "mode": "normal" | "fill" | "fullScreen"}` — width/height are
the window's outer size outside full screen. Saved when the window closes.

**Pure logic to port 1:1:** `Packages/CaptureKit/Sources/CaptureKit/WindowPlacement.swift` —
`centred(size, in: visible)`, `opening(remembered:defaultSize:minSize:visible:)` →
`(frame, enterFullScreen)`, `memo(frameSize:normalSize:isFullScreen:visible:)`; tests in
`Packages/CaptureKit/Tests/CaptureKitTests/WindowPlacementTests.swift` (13 cases — port them as-is).
The AppKit glue is `App/Lifecycle/WindowPlacer.swift` (`place(window, rememberAs:)`, called right
before each window is shown).

**Windows / WPF notes:**
- Visible area = `System.Windows.Forms.Screen.FromPoint(Cursor.Position).WorkingArea`, converted from
  device pixels to WPF DIPs (divide by the monitor's DPI scale). Set `WindowStartupLocation = Manual` and
  `Left/Top/Width/Height` from `opening(...)`'s frame (WPF's y goes **down** — flip from AppKit's
  bottom-up maths, or compute top = visible.Top + (visible.Height − h) / 2 directly).
- Windows has no macOS-style full-screen Space. Map `fullScreen` **and** `fill` to
  `WindowState.Maximized` (with `RestoreBounds` = the centred remembered size); on close, save
  `RestoreBounds` size + `mode = "fill"` when `WindowState == Maximized`. A borderless true full screen
  is not wanted.
- Save in the port's settings store under the same keys and JSON shape.

---

## Part 7 — Interactive guided tours and ⓘ help on every window

Design: v3 spec §14 + §14.9 (`docs/superpowers/specs/2026-09-24-betterscreenshot-editor-recording-v3-design.md`).
Code: `Packages/TourKit/` + `App/Tours/`. Each subsection is filled by the lane that builds it.

### 7.1 Who gets tours — new users only, asked first (lane 7A)

**The owner's rule (verbatim intent):** tours are *only* for new users. Someone who already used the app
must never be prompted or shown a tour by itself — not on the update that adds tours, not later, not when
a tour is changed. New users are asked once ("do you want a tour?") and only a yes turns tours on.
**When in doubt, treat the user as existing** — a missed new user loses nothing, a nagged existing user
is exactly what the owner forbade.

**Step 1 — classify once, first thing at launch (macOS: top of `applicationDidFinishLaunching`).**
If the stored `tourAudience` is absent, gather the signals, run the pure classifier, store the result as
`"new"` or `"existing"`, and never compute it again. This must run **before anything writes a
preference** (on macOS the status item, the `didRegisterLaunchAtLogin` flag and window frames all write
into the app's preferences, and would make every new user look existing). A probe confirmed a fresh macOS
app domain is empty at that point and has keys after one run.

The user is **existing** if *any one* of these is true (checked in this order; else **new**):
1. The running app isn't the real one — bundle id ≠ `com.betterscreenshot.mac` (can't trust what we read).
2. The app's **own** preferences hold any key other than the five tour keys below (only the app's own
   domain via `persistentDomain(forName: bundleID)` — never the global domain).
3. `~/Library/Application Support/BetterScreenshot/` exists and has **any** entry (file or folder, even an
   empty `History/`). A path that exists but isn't a folder, or can't be listed, counts as content (doubt).
4. Screen Recording permission is already granted (a fresh install never has it).

Stored value parsing is fail-safe too: absent → not classified yet; exactly `"new"` → new; **anything
else** (`"New"`, `""`, garbage) → existing.

**Windows mapping.** The port keeps everything in `%APPDATA%\BetterScreenshot\` (`settings.json` +
`History\`). Classify at the very start of the port's startup (its `App` startup handler) **before the
first `SettingsStore.Save()`**. Signals: (1) always
the real app — pass the known id; (2) the top-level property names present in an existing
`settings.json` (excluding the five tour keys); (3) `%APPDATA%\BetterScreenshot\` has any entry other than
`settings.json` (e.g. `History\`); (4) always `false` (Windows has no screen-capture permission). An
existing `settings.json` from any earlier version always has non-tour properties, so every current port
user classifies as existing.

**Step 2 — ask new users once.** The Welcome window's last page ("You're all set!", with the shortcut
grid) shows, **only when** `tourAudience == "new"` **and** `tourQuestionAnswered` is not true, this block
**in place of** the "Start Capturing" button (screenshot: `docs/parity-v3/part7-welcome-question.png`):

- a 300 pt horizontal separator line, 16 pt gap;
- **"Want a quick tour?"** — 15 pt semibold, centred; 4 pt gap;
- **"We'll point out each part the first time you use it. You can skip any time."** — 13 pt, secondary
  label colour, centred, wraps at 360 pt; 16 pt gap;
- two large rounded buttons side by side, 12 pt apart: **No Thanks** (Esc) · **Show Me Around** (default
  button, Return).

Page width stays 440 pt; the window grows in height to fit (about 432 pt). Existing users (and new users
who already answered) see the page exactly as before: "Start Capturing".

| Action | Writes | Then |
|---|---|---|
| **Show Me Around** | `firstUseToursEnabled = true`, `tourQuestionAnswered = true` | The page re-renders with "Start Capturing" in place of the question, **then** the Welcome tour starts over this window (re-render first, so the tour's anchors are the final views). If none of its steps can be shown there yet, it waits (queued) for the Welcome window's next appearance. |
| **No Thanks** | `firstUseToursEnabled = false`, `tourQuestionAnswered = true` | Window closes. |
| **Closing the window while the question is showing** | same as No Thanks | — |
| Closing after answering | nothing | — |

**When the Welcome window opens at launch** (unchanged except the last condition): no Screen Recording
permission → the permission page (as before); else, if we just relaunched after the grant **or** the user
is new and hasn't answered → straight to the "You're all set!" page (which then asks). The second
condition catches a new user whose permission got granted outside our flow. On Windows (no permission
pages): at launch, if `tourAudience == "new"` and not answered → show the Welcome window, which asks.

**After that, what starts by itself.** A tour starts automatically only if `firstUseToursEnabled` is
`true` (**absent = false**) **and** the user hasn't seen this version of it (`toursSeen[id] < version`, or
missing). The audience never turns tours on — it only decides whether the question is asked. So existing
users (flag absent) never get an automatic tour, even after a tour's version is bumped. Everyone can still
run any tour on purpose from the ⓘ buttons or **Help & Tours** (§7.8), and existing users can opt in with
Settings → Tours & tips.

**Pure logic to port 1:1** (`Packages/TourKit/Sources/TourKit/TourAudience.swift`, `TourRules.swift`;
tests `Tests/TourKitTests/TourAudienceTests.swift`, `TourRulesTests.swift`):
- `classify(signals)` — cases: the owner's real key set (`didRegisterLaunchAtLogin`, `captureSettings`,
  `hotkeyBindings`, `recordingConfig`, `saveDirectory`, `editorDefaultStyle`, `editorRecentColors`,
  `windowPlacement.annotate`, `NSStatusItem Preferred Position Item-0`, `NSWindow Frame NSColorPanel`) →
  existing; same plus the tour keys → existing; nothing → new; only tour keys → new; each single app key
  (incl. `RelaunchedAfterPermissionGrant`, `windowPlacement.history`, `NSStatusItem VisibleCC Item-0`,
  any unknown key) → existing; folder content alone → existing; permission alone → existing; bundle id
  nil / `com.betterscreenshot.app` / `""` → existing.
- stored parsing — nil → nil; `"new"` → new; `"existing"`, `"New"`, `""` → existing.
- `shouldAskQuestion(audience, answered)` — true only for (new, false); nil audience → false.
- `shouldOpenWelcomeOnLaunch(audience, answered, permissionGranted)` — true only for (new, false, true).
- `shouldAutoStart(tour, firstUseToursEnabled, seen)` — (true, unseen) → true; false or **nil** → false;
  seen at ≥ version → false; version 2 with seen 1 → true only when the flag is true.

### 7.2 Engine, catalog format, events, anchors, persistence keys (lane 7A)

**Persistence (all five keys, nothing else).** macOS UserDefaults; on Windows add them to `settings.json`
with the same names.

| Key | Type | Meaning |
|---|---|---|
| `tourAudience` | string `"new"` \| `"existing"` | Written once at the first launch with tours (§7.1). Never rewritten — Reset All Tours doesn't touch it. |
| `tourQuestionAnswered` | bool | The Welcome question was answered (or closed). |
| `firstUseToursEnabled` | bool, **absent = false** | Tours start by themselves. The Welcome answer or the Settings switch sets it. |
| `toursSeen` | map tour id → int version | Finished or skipped (Skip tour) at that catalog version. |
| `toursPaused` | map tour id → int step index | Where to resume; removed when the tour resumes, finishes or is skipped (the key is removed when the map is empty). |

**Data model** (`Packages/TourKit/Sources/TourKit/TourModel.swift`):
- `TourID` (persisted raw values — never rename): `welcome, quickAccess, editor, text, redaction,
  highlighter, spotlight, firstRecording, recordingPill, videoEditor, settings, history`.
- `TourSurface` (a window a tour runs on): `welcome, quickAccess, editor, recordStrip, recordingPill,
  videoEditor, settings, history`.
- `Tour { id, version (default 1), surface, trigger, steps, handsOverTo? }`; `trigger` is
  `surfaceShown(surface)` · `event(TourEvent)` · `startedByApp` (only Welcome: started by Show Me Around,
  hand-over or replay).
- `TourStep { anchor, kind, title, body }`; `kind` = **Explain** (advances on Next) or **Try(advanceOn:
  event)** (advances when that exact event is posted, or on Skip step).
- `TourEvent`: `captureTaken` · `toolSelected(name)` · `annotationAdded(name)` · `styleChanged(field)` ·
  `menuOpened(anchor)` · `choiceMade(anchor)` · `action("<surface>.<verb>")` (e.g. `quickAccess.edit`,
  `video.split`). Two events are equal only if kind and string match exactly.
- Catalog (`Catalog/*.swift`, one file per area; `TourCatalog.all`) — steps are filled by lanes 7S/7E/7R
  (§7.4–7.7). Welcome → hands over to Quick Access → hands over to Editor; First recording → Recording pill.

**Anchors.** Every highlighted control carries a stable id `"<surface>.<name>"` (e.g.
`editor.inspector.colour`). macOS stores it as the view's accessibility identifier (`view.tourAnchor =
"…"`, SwiftUI `.tourAnchor("…")`) and finds it with `window.view(forTourAnchor:)`, which searches the
whole window including the title bar and treats hidden views as missing. **WPF:** set
`AutomationProperties.AutomationId` to the same id and search the window's visual tree; an element that
isn't `IsVisible` counts as missing.

**Event bus** (`TourEvents.swift`): surfaces call `post(event)` when the user does something,
`surfaceShown(surface, window)` right after a surface's window is on screen, and `replay(tourID, window?)`
from an ⓘ (window) or the menu (nil). With no handler installed every call is a no-op. The app's
coordinator sets the three handlers at launch. **WPF:** a static class with three `Action<…>?` fields.

**Engine — pure state machine, port 1:1** (`TourEngine.swift`; 19 tests in `TourEngineTests.swift`).
State: `status` (idle · running · paused · finished · skipped), `current` step index, and `observed` —
every event posted while running. Each call returns an effect for the caller to carry out:
`none` · `show(step)` · `finished(handsOverTo)` · `skipped` · `paused(at)` · `nothingToShow`.
- `start(at: i, isPresent)` (idle or paused only): out-of-range `i` → 0; show the first step at or after
  `i` that is **presentable** — its anchor is present **and** it isn't a Try step whose event is already in
  `observed`. None → `nothingToShow` and **nothing changes** (a surface without its anchors yet never
  burns a tour).
- `next` — only on an Explain step (ignored on Try); advance to the next presentable step; past the end →
  `finished(handsOverTo)`.
- `skipStep` — any step; same advance.
- `handle(event)` — running only; add to `observed`; if the current step is Try and the event equals its
  `advanceOn` → advance, else `none`.
- `skipIfAnchorMissing` — current anchor gone → advance, else `none`.
- `skipTour` (running or paused) → `skipped`. `pause` (running) → `paused(at: current)`. `resume`
  (paused) → like `start(at: current)`, and stays paused on `nothingToShow`.
Test cases to port: starts at first step · Next walks Explain steps · Next ignored on Try · Try advances
only on its exact event (other tool, other event kinds ignored) · events do nothing on Explain steps ·
event seen during an Explain step makes the later Try step skip silently · Skip step leaves a Try step ·
missing anchors skipped at start and on Next · anchor vanishing mid-step skips it · nothing present /
empty tour → `nothingToShow`, status stays idle · Next on last step → `finished(handsOverTo)`, then Next
does nothing · Try event on last step finishes with hand-over · trailing missing anchors finish · Skip tour
from running and from paused · pause keeps index, paused ignores events and Next, resume returns there ·
resume skips steps now missing · resume with nothing present stays paused at the same index · start at a
persisted index; 99 and -1 → 0 · pause/resume when not running → `none`.

**Shortcut placeholders** (`TourText`): a body may contain `{shortcut:<HotkeyAction raw value>}`
(`captureArea`, `captureWindow`, `captureFullscreen`, `captureText`, `pinFromClipboard`, `record`,
`openHistory`, `restoreRecentlyClosed`, `pauseResumeRecording`). The coordinator replaces each with the
user's **current** combo exactly as the Welcome grid and menus show it (macOS `HotkeyCheatSheet.keys(for:
in:)` → `HotkeyCombo.displayString`, e.g. `⇧⌘4`; Windows: the port's own combo display string, e.g.
`Ctrl+Shift+4`); an unbound action shows its title ("Capture Area"). Unknown names or an unclosed
placeholder are left as typed. Tests: one and two placeholders resolve; no placeholder unchanged;
`{shortcut:nope}` and `{shortcut:captureArea` (no brace) unchanged; names listed in order.

**Catalog lint** (`CatalogLintTests.swift`, runs on the real catalog + on bad samples so it's known to
bite): title 1–4 words; body 1–20 words (a "word" is a whitespace token with a letter or digit, so "—"
doesn't count; a placeholder is one word); body ≤ 2 sentences (split on `. ! ? …`); a Try body must not
start with `this/these/that/the/your/a/an/here/it/you` (start with a verb); anchor matches
`^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)+$`; `menuOpened`/`choiceMade`/`action` names match the same;
`toolSelected`/`annotationAdded`/`styleChanged` names match `^[a-z][A-Za-z0-9]*$`; every placeholder names
a real action; no `{`/`}` outside placeholders or in titles; no two Try steps in one tour wait for the
same event.

**Coordinator behaviour** (`App/Tours/TourCoordinator.swift` — port as the WPF app's `TourCoordinator`):
- **surfaceShown(surface, window)**: remember the window for that surface; then start, in priority order,
  (1) a queued tour for that surface (from step 0), else (2) a paused tour for that surface (at its
  `toursPaused` index), else (3) the first tour triggered by `surfaceShown(surface)` that may auto-start
  (§7.1). The tour already running is never restarted this way.
- **post(event)**: feed the running tour; a completed Try step shows the tag's brief "done" state for
  **0.8 s**, then the next step. If the event didn't complete it, re-check the current anchor on the next
  UI turn (the action may have hidden it). Then, **only if no tour was running**, start a queued or
  auto-startable tour whose trigger is `event(thisEvent)`, in the focused window of its surface (else the
  newest visible one). Event-triggered tours never interrupt a running tour; they stay eligible.
- **replay(id, window)**: with a window → start there from step 0 (restarting it if it's the running tour);
  without (menu) → start now if the tour's surface is visible, else queue it and open that surface if the
  app can (Welcome — permission page if not granted, else the all-set page; Settings; History), otherwise
  show the HUD note **"<Menu title> starts the next time you use it"** (e.g. "Editor Tour starts the next
  time you use it"). Replays and hand-overs ignore `firstUseToursEnabled` and `toursSeen`.
- **One tour on screen.** Starting a tour while another runs pauses the other (persisted in `toursPaused`,
  remembered with its window) — except that a tour **on its last step** (running or paused) whose
  `handsOverTo` is the starting tour is marked seen instead (so the capture that ends Welcome and the Quick
  Access card that follows work in either order). When a tour ends, the newest interrupted tour resumes if
  its window is still visible.
- **Host window closed, hidden or minimised → pause** (close notification + a 0.5 s check while a tour
  runs; macOS panels are ordered out, not closed). The same check skips a step whose anchor disappeared.
- **Finish** → `toursSeen[id] = max(old, version)`, clear its pause, hide the tag, then the hand-over tour:
  queued immediately, started now if its surface is visible. **Skip tour** → seen, no hand-over.
- The tag (lane 7B, §7.3) gets the step, the body with placeholders resolved, and "number of total"
  (`index + 1` of `steps.count`); its buttons call Next / Skip step / Skip tour.
- A tour with no presentable step (e.g. empty in the catalog) is never started and never marked seen.

**Where it goes in the port.** Pure logic: a new `BetterScreenshot.Tours` project (no WPF references) with
`TourModel`, `TourAudience`, `TourRules`, `TourText`, `TourEngine` + a test project with the cases above.
App side: `windows/src/BetterScreenshot.App/Tours/TourCoordinator.cs`, created in `App.OnStartup` right
after classification; keys added to `SettingsStore`'s DTO.

### 7.3 The tag overlay and the ⓘ button — exact layout (lane 7B)

**What it is.** While a tour runs, the control a step talks about gets a **red outline box**, a **red tag
bubble** next to it says what it is (or what to do), a **leader line** joins the two, and the rest of the
window is dimmed slightly. A tour step is either **Explain** ("this is X" — the user presses **Next**)
or **Try** ("do X" — it advances by itself when the user does it; **Skip step** is offered). The user keeps
using the real window underneath — clicks go straight through the dim and the box to the real controls
(that's how Try steps work: the user clicks the real thing). Only the tag bubble takes clicks, and nothing
about the overlay ever takes keyboard focus: the host stays the **key window** (macOS term for the window
receiving keystrokes — Windows: the active/foreground window) and its **first responder** (the control
with keyboard focus) is untouched. Every window also gets a small **ⓘ** button that replays its tour and
lists its keyboard shortcuts.
macOS files (all in `Packages/TourKit/Sources/TourKit/`): `Overlay/TagOverlayController.swift` (the
controller — implements `TourTagPresenting`, which the tour engine calls), `Overlay/TagViews.swift` (the
windows + drawing), `Overlay/TagStyle.swift` (**every number, colour and string below**),
`Overlay/TagLayout.swift` + `Overlay/TagKeys.swift` (pure logic — port 1:1, tests in
`Tests/TourKitTests/TagLayoutTests.swift`: `tagLayoutTests`, `tagKeysTests`, `tagStyleTests`),
`Help/InfoButton.swift` (the ⓘ). Snapshots from the headless probe:
`docs/reviews/2026-09-25-tours/overlay-*.jpg` (01 the owner's mock — tag left of the editor's Colour row ·
02 light window, no room on the left → right, Try step · 03 record strip, tag above the whole panel ·
04 menu-bar icon, tag below · 05 screen corner: last step "Done", then the completed state · 06 the ⓘ in
the editor's title bar + the Keyboard Shortcuts list).

The engine calls three things: `show(step, body, number, total, anchor, host)` (replaces whatever is
shown), `showCompleted()` (a Try step was just done), `hide()`. The tag calls back `onNext`, `onSkipStep`,
`onSkipTour`.

#### The tag — exact layout (points = WPF DIPs)
Tour colour **#FF453A** (sRGB 255, 69, 58) for the box, the leader line and the tag fill.

| Part | Spec |
|---|---|
| **Outline box** | Rounded rect = the control's bounds grown by **4** on every side, corner radius **6**; a **2**-thick stroke drawn *outside* that edge (it covers 4–6 from the control; outer corner radius 8). No fill. |
| **Dim** | Black **20 %** over the host window's **whole frame** (title bar included), clipped to the window's rounded outline, with a hole = the box's outer edge (radius 8). Window corner radius: titled windows 16 on macOS 26 (10 on macOS 14/15) — **on Windows use 8 (Windows 11) or 0 (Windows 10)**; borderless panels use their own background's radius (record strip 12, recording pill 20). No dim when the control is in the menu bar / tray. |
| **Leader line** | **2**-thick, round caps, from the tag's edge to the box's outer edge; **24** long when straight. Its end on the tag stays ≥ 12 from the tag's corners, its end on the box ≥ 6 from the box's corners (it goes diagonal only when the tag had to slide along its side to stay on screen). |
| **Tag bubble** | Filled #FF453A, corner radius **12**, system drop shadow. Width = widest of (title, body on one line, footer) + 24, clamped to **200 … 260**. Padding **12** left/right, **10** top, **10** bottom. |
| Title | **13 pt semibold** white, one line, truncated with "…". |
| Body | **2** below the title; **12 pt regular** white, wraps, at most **2 lines** (the last one truncated with "…"). The body's `{shortcut:…}` placeholders arrive already replaced. |
| Footer row | **8** below the body, **20** tall. Left: step counter **"2 of 7"** (11 pt medium, white 80 %). Right-aligned: **"Skip tour"** (plain text link, 11 pt semibold, white 80 %) · gap **4** · the primary button. |
| Primary button | Height **20**, capsule (radius 10), label **11 pt semibold**, **8** padding each side. **Explain** step: **"Next"** — **"Done"** on the last step — white fill, red (#FF453A) label. **Try** step: **"Skip step"** — no fill, **1**-thick white border, white label. Pressed: 70 % opacity. |
| Done state (`showCompleted`) | Counter and buttons hidden; the footer shows a white **check-in-a-circle** icon (13 pt, in a 16 × 16 box) + **4** gap + **"Done"** (11 pt semibold white). The next step's `show` replaces it. |
| Strings | `Next`, `Done`, `Skip step`, `Skip tour`, `"<n> of <total>"`, completed `Done`. |

**Screen reader.** When a tag appears it announces **"<title>. <body> Step <n> of <total>."**; the done
state announces **"Done"** (macOS: `NSAccessibility` announcement, high priority). The bubble is a group
labelled "Tour: <title>"; its buttons carry their visible labels. **WPF:** `AutomationPeer.RaiseNotificationEvent(
AutomationNotificationKind.Other, AutomationNotificationProcessing.ImportantMostRecent, text, "TourTag")` on
the tag window's peer.

#### Placement (`TagLayout.place` — pure, port 1:1)
Works in screen coordinates. **macOS is y-up** ("below" = smaller y); in WPF (y-down) either flip into a
y-up space first or swap the below/above arithmetic — the tests say which side each case must pick.
1. `box` = control rect grown by 4; `outer` = box grown by 2. If the control touches the screen edge (a
   menu-bar/tray icon filling the bar's height), `box` is first clipped to the **screen** bounds shrunk by 2
   so the whole outline stays visible.
2. `area` = the **working area** (macOS `visibleFrame`: screen minus menu bar and Dock; Windows
   `Screen.WorkingArea`: minus the taskbar) of the screen containing the control's centre, shrunk by **8**.
3. **Side order:** left, right, below, above — the owner's mock has the tag on the left. **Vertical first**
   (below, above, left, right) when the control's **direct parent** is a bar at least **3× as wide as
   tall** (a toolbar row, the record strip, the pill), so the tag doesn't cover the controls beside it.
4. **Keep-out:** when the host window has **no title bar** (record strip, recording pill, status/tray
   icon) the tag first tries to sit outside the **whole host window**, not just the box — so it never
   covers the panel's other controls (the leader line then crosses the panel to the box). If nothing fits
   that way, retry with only the box as keep-out.
5. For each side in order: put the tag **24** beyond the keep-out on that side, centred on the box along the
   other axis, then slide it along that axis to stay inside `area`. The side **fits** if the tag is fully
   inside `area` *and* still overlaps the box's span on the sliding axis (so the leader stays short).
   First side that fits wins. Round the tag's origin to whole points.
6. Nothing fits (a huge control on a full-screen window) → **over**: the tag sits inside the box's top-left
   corner (inset 12), kept inside `area`, no leader line.

#### Windows and focus (the risky part — proven on macOS by probes, see below)
Two borderless, transparent windows per tag, both **owned by / children of the host window** so they move,
minimise, hide and z-order with it (and never float over *other* apps covering the host):
- **decor** — the dim, box and leader line; spans the host frame ∪ box ∪ tag (+2). **Ignores the mouse
  entirely**: every click, scroll and hover goes to whatever is under it.
- **tag** — just the bubble. Takes clicks. **Can never become the key/active window**, and clicking it never
  activates the app or moves keyboard focus.

Order: host < decor < tag. The overlay follows the host when it moves or resizes (immediately on resize),
and re-checks the control's position/visibility every **100 ms** (also while menus are open); if the
control or window goes hidden/closed/minimised, both windows hide, and come back when it's visible again.
A control in the **menu bar** (status item; on Windows the **tray icon**, via `Shell_NotifyIconGetRect`)
gets top-level windows at the menu-bar/topmost level instead of owned ones, and no dim.

**WPF recipe:**
- Both windows: `WindowStyle=None`, `AllowsTransparency=True`, `Background=Transparent`,
  `ShowInTaskbar=False`, **`ShowActivated=False`**, `Focusable=False`, `ResizeMode=NoResize`; never call
  `Activate()`/`Focus()`. `Owner = host` for the decor, and **`Owner = decor` for the tag** (an owned
  window always stays above its owner, so the chain gives host < decor < tag). In `SourceInitialized`, add
  extended styles with `SetWindowLongPtr(hwnd, GWL_EXSTYLE, …)`: **`WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW`** on
  both, plus **`WS_EX_TRANSPARENT | WS_EX_LAYERED`** on the decor (that's what makes it click-through; also
  set `IsHitTestVisible=False` on its content).
- Tag window: also handle `WM_MOUSEACTIVATE` in an `HwndSource` hook and return **`MA_NOACTIVATE`**, so a
  click on Next doesn't activate it; buttons `Focusable=False`. Its fully transparent corners are
  click-through automatically (layered window).
- Owned windows **don't move with their owner on Windows** (unlike macOS child windows): subscribe to the
  host's `LocationChanged` / `SizeChanged` / `StateChanged` and re-run the layout; a 100 ms
  `DispatcherTimer` covers the control moving inside the window. Tray host: `Topmost=True`, no owner.
- Keep tags out of the user's screenshots/recordings: `SetWindowDisplayAffinity(hwnd,
  WDA_EXCLUDEFROMCAPTURE)` on both windows (Windows 10 2004+). (macOS: screenshots exclude
  `TagOverlayController.allWindowNumbers` — see §7.4 "Tags never appear in a screenshot"; recordings leave
  every tag window out of the stream's filter and keep a new tag transparent until the filter covers it —
  `TourTagRecordingGate`, see §7.6.)

#### Keys (`TagKeys.action` — pure, port 1:1)
Handled only for key-downs aimed at the **host window** (any of the app's windows when the host is the
menu-bar/tray icon), and only while a tag is showing and not in the done state:
- **Return** (and numpad **Enter**) = **Next**, on **Explain** steps only (on Try steps it passes through).
- **Esc** = **Skip tour**.
- Everything passes through untouched when: any modifier is held (⌘ ⌥ ⌃ ⇧ / Ctrl Alt Shift Win), the key
  is an auto-repeat, or the focused control is an **editable text field** (typing a label in the editor,
  a search box…). Caps Lock / numpad flags don't count as modifiers.
- **Esc is left to the host while it claims it** (the editor: while it's on a drawing tool or has a
  selection, Esc goes back to Select / clears it first — details §7.5; macOS `TourEscapeClaiming`).
- A key is swallowed only when it did something. macOS: a local key-down monitor (sees the app's events
  without being focused). **WPF:** a `PreviewKeyDown` handler on the host window (`e.Handled = true` only
  when acted on); editable = focused element is a `TextBox`/`RichTextBox`/`PasswordBox` with
  `IsReadOnly=False`.

#### The ⓘ button (`InfoButton`)
- **Look:** borderless icon button, **26 × 22**, the system "info in a circle" glyph (macOS SF Symbol
  `info.circle`; Windows Segoe Fluent Icons **Info**, U+E946), default title-bar icon colour; tooltip and
  accessible name **"Tour & Keyboard Shortcuts"**.
- **Titled windows** (`InfoButton.install(in: window, tour:, shortcuts:)`): its own title-bar accessory at
  the **top-right**, **6** from the window's right edge, vertically centred in the title bar, and the
  **rightmost** item — the editor's existing Undo · Redo · panel-toggle group stays to its left (that group
  ends with a 10 inset, so the gap is ~10). Installing twice updates and returns the same button.
  **Windows:** the caption buttons (– □ ×) own the top-right corner, so put the ⓘ **immediately left of
  the caption buttons** (right of any other title-bar buttons), same size, vertically centred.
- **Untitled panels** (the record strip): the same 26 × 22 button placed by the surface (next to its ✕),
  tinted to match the dark HUD.
- **Press → menu** (opens on mouse-down, **4** below the button), every item with an icon:
  **Replay Tour** (icon: play in a circle; SF `play.circle`, Segoe **Play** U+E768) → asks the tour system
  to replay this window's tour now (`TourEvents.replay(tour, in: window)`); **Keyboard Shortcuts** (icon:
  keyboard; SF `keyboard`, Segoe **KeyboardClassic** U+E765) — shown only when the window has shortcuts.
- **Keyboard Shortcuts** opens a small transient popover (WPF: `Popup` with `StaysOpen=False`) anchored
  below the ⓘ: title **"Keyboard Shortcuts"** 13 pt semibold; then one row per shortcut — the **action**
  on the left (12 pt regular, secondary text colour), the **keys** on the right, right-aligned (12 pt
  medium, primary colour); rows **6** apart, **24** between the columns, **10** between title and rows;
  insets **12** top/bottom, **14** left/right; sized to fit. Each window passes its own (keys, action)
  list; on Windows write keys the Windows way ("Ctrl+Z").

#### How it was verified on macOS (probe, 2026-09-25)
A headless probe (synthetic events, windows parked behind the owner's) checked: clicks on the boxed
control, on a control under the dim and on the leader line are all routed by the window server to the
**host** window and its real button (never the overlay); clicks on the tag's Next / Skip step / Skip tour
reach the tag and fire the callbacks; the host keeps its key status and first responder and the app is
never activated; the same over a non-activating floating panel (record strip), where the real button's
action also fired; the menu-bar case puts the tag below the icon with no dim; a pop-up menu opened on the
boxed control and closed again leaves the tag in place, and `menuOpened`/`choiceMade` can be posted from
the menu; moving/resizing the host, hiding the control and closing/reopening the host all behave as above;
Return/Esc and every pass-through case in the key table.

### 7.4 Welcome + Quick Access tours (lane 7S)

**What the user sees.** A new user who pressed **Show Me Around** (§7.1) gets the **Welcome** tour over the
Welcome window at once; it ends by asking for a real screenshot. That screenshot's **Quick Access card**
(the floating thumbnail in the screen corner) then gets the **Quick Access** tour, which ends by asking the
user to click **Edit** — and the **Editor** tour (§7.5) takes over in the editor window. Each hand-over is
the engine's `handsOverTo` (§7.2). Snapshots: `docs/reviews/2026-09-25-tours/shell-welcome.jpg` (step 3),
`shell-quickaccess.jpg` (step 4).

macOS files: steps in `Packages/TourKit/Sources/TourKit/Catalog/WelcomeTours.swift`; anchors and events
in `App/MenuBar/OnboardingController.swift` (Welcome window), `App/MenuBar/MenuBarController.swift`
(status item), `App/Capture/CaptureCoordinator.swift` (`captureTaken`, screenshot exclusion),
`Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift` +
`QuickAccessStackController.swift` (the card), `Packages/CaptureKit/Sources/CaptureKit/CaptureService.swift`
(exclusion); two small additions to `App/Tours/TourCoordinator.swift` (below).

In the tables, **E** = Explain (the tag's button says **Next**, or **Done** on the last step), **T** = Try
(advances by itself on the event; the tag's button says **Skip step**). `{shortcut:x}` is replaced with the
user's current combo for `HotkeyAction` `x` (§7.2 "Shortcut placeholders"); with the default bindings the
Welcome bodies read "⇧⌘4 area, ⇧⌘8 window, ⇧⌘6 full screen" (Windows: "Ctrl+Shift+4 …" per the port's own
display strings). Strings are verbatim — copy them exactly.

**Welcome tour** — id `welcome`, version 1, surface `welcome`, trigger `startedByApp` (Show Me Around,
Help & Tours → Take the Welcome Tour, or a replay), hands over to `quickAccess`.

| # | | Anchor → the control it outlines | Title | Body | Advances on |
|---|---|---|---|---|---|
| 1 | E | `menuBar.icon` → the menu-bar status item's button (Windows: the tray icon) | Your menu bar icon | Everything lives here: captures, recordings, History and Settings. | Next |
| 2 | E | `welcome.shortcuts` → the shortcut grid on the "You're all set!" page | Capture shortcuts | These work in any app: {shortcut:captureArea} area, {shortcut:captureWindow} window, {shortcut:captureFullscreen} full screen. | Next |
| 3 | T | `welcome.captureArea` → the keys label of the grid's Capture Area row ("⇧⌘4") | Take a screenshot | Press {shortcut:captureArea} now and drag across anything on screen. | `captureTaken` |

- `welcome.shortcuts` is the grid view itself; `welcome.captureArea` is set on the keys label of the row
  whose keys equal Capture Area's current combo. Capture Area unbound → no such row → step 3 is skipped
  and the tour ends after step 2 (still handing over to Quick Access).
- Step 1's anchor is **not** in the Welcome window — see "The menu-bar step" below. When the status item
  isn't on screen the step is skipped and the tour starts at 2 of 3.
- The Welcome page's own "Start Capturing" button (Return) closes the window; the tag's Return = Next
  wins on Explain steps because the tag's key handler runs first (§7.3 Keys). Closing the window pauses the
  tour (§7.2); the first screenshot card then finishes it anyway if it was on step 3 (the "last step
  hands over" rule), else it simply stays paused and the Quick Access tour starts by itself.

**Quick Access tour** — id `quickAccess`, version 1, surface `quickAccess`, trigger
`surfaceShown(quickAccess)` (the first screenshot card, or a hand-over/replay), hands over to `editor`.

| # | | Anchor → the control it outlines | Title | Body | Advances on |
|---|---|---|---|---|---|
| 1 | E | `quickAccess.card` → the whole card | Your screenshot | Each capture waits here as a card until you use it or close it. | Next |
| 2 | T | `quickAccess.card` | Drag it anywhere | Drag the card into any app — a chat, an email, a folder. | `action("quickAccess.dragged")` |
| 3 | E | `quickAccess.actions` → the overlaid button row (Copy · Edit · Save · ✕) | Copy, Edit, Save | Copy to the clipboard, Edit, or Save to your Screenshots folder. | Next |
| 4 | T | `quickAccess.edit` → the Edit (pencil) button | Mark it up | Click Edit to draw arrows, add text or blur things out. | `action("quickAccess.edit")` |

**Where each event is posted** (post at the moment the action already happens; no UI was added):

| Event | Posted by | When |
|---|---|---|
| `captureTaken` | `CaptureCoordinator.run` | right after a screenshot's pixels are captured (Capture Area, Capture Window, Capture Full Screen) and **before** the card appears |
| `captureTaken` | `CaptureCoordinator.runCaptureText` | right after Capture Text's pixels are captured (no card follows; the Quick Access tour then waits for the next card) |
| `action("quickAccess.dragged")` | the card's drag source (`DraggableImageView.onDragEnded`) | a drag out of the card ended **on a drop target** (a cancelled drag doesn't count) |
| `action("quickAccess.edit")` | the card's Edit button | on click, **before** the card closes and the editor opens — so the tour finishes and queues the editor tour before the editor window reports itself |
| `action("quickAccess.copy")`, `action("quickAccess.save")` | Copy / Save buttons | on click (no step waits for these yet) |
| `surfaceShown(quickAccess, card)` | `QuickAccessStackController.present` | after the card has moved into its final stack slot — **screenshot cards only** (a recording's card has no Edit button, so it never runs this tour) |

Not new captures, so no `captureTaken`: the editor's **Stack** button and **Restore Recently Closed** (their
cards still report `surfaceShown`, so a queued Quick Access tour can run on them).

**The card stays up while its tour runs.** The card normally closes after a drop, and optionally after an
auto-dismiss countdown (Settings → Quick Access Overlay → Auto-dismiss after; default Never). While a tour
tag is attached to the card: (1) when the countdown runs out it simply restarts (exactly like hovering the
card), and (2) a drop does **not** close the card — step 2 asks for that drop and the tour carries on over
the same card. Once the tour ends (finished, skipped, or moved on), the normal rules apply again — the
next countdown closes it. macOS detects "a tag is attached" as: the card's child windows include one of
`TagOverlayController.allWindowNumbers`. **WPF:** ask the tour coordinator whether its running tour's host
window is this card (or check whether a tag window's `Owner` chain leads to the card).

**The menu-bar step (status item / tray icon).** The coordinator looks a step's anchor up only in the
tour's host window, but the status item's button lives in the status bar's own window. Added to
`TourCoordinator` (source-compatible, default empty): `var extraAnchorWindows: () -> [NSWindow]`. The
coordinator searches the host first, then each extra window **that is visible and intersects a screen**;
when the anchor is found there, the tag is attached to *that* window (the overlay treats a status-bar window
as a menu-bar host: top-level panels at status-bar level, tag **below** the icon, **no dim**), while pausing
and resuming still follow the tour's real host (the Welcome window). `AppDelegate` sets it to
`[menuBar.iconWindow]` (`statusItem.button?.window`); `MenuBarController` sets
`statusItem.button?.tourAnchor = "menuBar.icon"`. An icon hidden by a menu-bar manager, or never placed by
macOS, counts as missing → step skipped. **WPF:** the tray icon has no WPF element. Get its rectangle with
`Shell_NotifyIconGetRect` (Windows 7+); if that fails, or the icon sits in the overflow flyout (the
rectangle is the flyout chevron's or off the taskbar), treat the anchor as missing and skip the step.
Otherwise give the overlay that rectangle as the anchor with a tray host: tag above the taskbar icon when the
taskbar is at the bottom (use the §7.3 placement with the working area), `Topmost=True`, no owner, no dim.

**Tags never appear in a screenshot.** The Welcome tour asks for a screenshot *while its tag is on screen*,
so every screenshot path leaves the tag windows out:
- `CaptureCoordinator.tourTagWindowIDs` = `TagOverlayController.allWindowNumbers` (every visible tag
  window — the decor with the dim/box/leader line and the tag bubble — from any overlay), read at capture
  time, is passed to `CaptureService.capture(target, excludingWindowIDs:)` by **every** screenshot call
  (Capture Area, Capture Window, Capture Full Screen, Capture Text). CaptureKit doesn't depend on TourKit, so
  the app passes plain window numbers.
- `CaptureService` maps them to ScreenCaptureKit (SCK — Apple's screen-capture framework) windows from the
  same `SCShareableContent` snapshot. **Full screen and area** (Capture Text is an area capture):
  `SCContentFilter(display:excludingWindows:)` with those windows.
- **Window capture** uses `SCContentFilter(desktopIndependentWindow:)`, which records the window **together
  with its child windows** — and a tag is a child window of the window it explains, so Capture Window on the
  Welcome window (or a tagged editor) included the tag. When any excluded window belongs to the captured
  window's app, the capture sets `SCStreamConfiguration.includeChildWindows = false` (macOS 14.2+; on
  14.0/14.1 that one case can still include the tag). Other apps' windows are captured exactly as before.
- **WPF:** set `SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)` on both tag windows (Windows 10
  2004+). The system then leaves them out of every capture API (GDI `BitBlt`/`CopyFromScreen`, DXGI Desktop
  Duplication, `Windows.Graphics.Capture`), including the port's own area/full-screen/window captures — no
  list to pass around. A window capture via `PrintWindow` never includes owned windows anyway. On older
  Windows, `WDA_MONITOR` would show black instead; there, hide both tag windows (`Opacity = 0`) for the
  duration of a capture and restore them after.

**Tag copy must fit.** The 20-word limit doesn't guarantee a body fits the tag's two lines.
`Packages/TourKit/Tests/TourKitTests/TagFitTests.swift` measures every Welcome / Quick Access / Settings /
History body in the tag's body label at its widest inner width (260 − 2 × 12 = 236 pt, 12 pt system font),
with placeholders resolved to "⇧⌘4" and to a long "⌃⌥⇧⌘4". Port it: measure with the WPF `TextBlock`
the tag uses (`TextWrapping=Wrap`, same font/width) and require ≤ 2 lines.

**How it was verified on macOS (probe, 2026-09-25, 78/78 checks).** A headless probe compiled the real App
sources with the real `TourCoordinator` and `TagOverlayController` (own `UserDefaults` suite; every window
parked behind the owner's). New user → Welcome page asks → Show Me Around (the real button action) → tag
1/3 below a stand-in status-bar window, no dim → Next (the tag's real button) → 2/3 with "⇧⌘4 area, ⇧⌘8
window, ⇧⌘6 full screen" → 3/3 → a **real** `CaptureCoordinator.captureFullscreen()` posted `captureTaken`
→ done state → Quick Access 1/4 on the new card (Welcome marked seen) → Next → the card's real drag-end
callback with a drop → 3/4, **card still up** → Next → a synthetic mouse-down/up on the real Edit button →
editor tour started in the editor window (a one-step stand-in; lane 7E owns the real one), Quick Access
marked seen, card gone. Menu replay with no card → HUD note "Quick Access Tour starts the next time you use
it", starts on the next card. A 1 s auto-dismiss card outlived 2.5 s of tour and closed within a second of
Skip tour (a card without a tour closed after 1 s). Exclusion, with the Welcome tour's step-3 tag up: a
control capture (other apps' windows left out so the parked windows show, tag windows kept) had 91 120
tour-red (#FF453A) pixels; the same full-screen and area captures with the tag windows excluded had **0**
at the tag's position and in the whole image, with the Welcome window intact; a window capture of the
Welcome window had 44 671 red pixels before the child-window fix and **0** after.

### 7.5 Editor tours — intro, Text, Redaction, Highlighter, Spotlight (lane 7E)

**What it is.** Five tours run on the annotation editor window (tour surface `editor`). The **Editor** tour
walks a new user through the window the first time an editor opens; four short tours explain a tool the
first time it's chosen. Words used below: a **tour** is a list of **steps**; each step outlines one real
control (its **anchor**, a stable id string) with a red tag. **Explain** steps advance when the user presses
**Next** (or Return/Enter); **Try** steps advance by themselves when the user does the thing — the app
reports it as a **tour event** — or on **Skip step**. How the engine, coordinator, tag and ⓘ work: §7.1–§7.3.
macOS files: catalog `Packages/TourKit/Sources/TourKit/Catalog/EditorTours.swift`; anchors + events in
`Packages/EditorKit/Sources/EditorKit/` (`EditorWindowController.swift`, `EditorInspectorView.swift`,
`EditorCanvasView.swift`); the editor reports itself in `App/Capture/CaptureCoordinator.swift` →
`presentEditor`. Snapshots (headless probe, 2026-09-25): `docs/reviews/2026-09-25-tours/editor-01-intro-colour.jpg`
(Editor tour step 4 — the owner's mock), `editor-02-text-resize.jpg`, `editor-03-redaction-strength.jpg`,
`editor-04-highlighter-width.jpg`, `editor-05-spotlight-dim.jpg`.

**Adapted to the editor as built** (vs the spec §14.3 table): the editor always opens with the **Arrow**
already chosen, so the table's "T Choose the Arrow" would wait for something already done — the intro starts
by drawing one instead; a last step points at the ⓘ so users know how to replay. "E Stroke & Opacity" is one
step outlining the Stroke section. The Text tour's "E Styles / Background / Effects" is three steps (one idea
each).

#### Triggers (all `version` 1, all on surface `editor`)

| Tour id (persisted) | Starts by itself when (only with first-use tours on, §7.1) | Menu title |
|---|---|---|
| `editor` | the editor window is shown (`surfaceShown(editor)`), or handed over from the Quick Access tour | Editor Tour |
| `text` | event `toolSelected("text")` | Text Tool Tour |
| `redaction` | event `action("editor.redactionToolChosen")` — posted when **Blur or Pixelate** is chosen (one event, so one trigger covers both) | Blur & Pixelate Tour |
| `highlighter` | event `toolSelected("highlighter")` | Highlighter Tour |
| `spotlight` | event `toolSelected("spotlight")` | Spotlight Tour |

Event-triggered tours never interrupt a running tour (§7.2): choosing Text during the Editor tour does
nothing, and the Text tour starts the next time Text is chosen after that.

#### Steps — verbatim (E = Explain, T = Try)

On Windows replace the macOS key names in bodies: `⌘-scroll` → `Ctrl+scroll`, `⌘0` → `Ctrl+0`, `⌘1` → `Ctrl+1`,
`⇧` → `Shift`, `⌥` → `Alt`, `Return` → `Enter` (the port's own key names, as its editor shows them). The ⓘ
glyph stays `ⓘ`. **Every body must fit the tag's 2 lines** (236 pt of text at 12 pt system font — 260 tag
width minus 2 × 12 padding); the 20-word lint limit alone doesn't guarantee it (an 18-word body was cut off
with "…"). After translating, re-check with the port's font (Segoe UI 12) — see the test below.

**Editor** (`editor`, 9 steps):

| # | Kind | Anchor | Title | Body | Advances on |
|---|---|---|---|---|---|
| 1 | E | `editor.toolbar` | Your tools | Every tool is here. Hover one to see its key — A is Arrow, T is Text. | Next |
| 2 | T | `editor.canvas` | Draw an arrow | Drag on the image. The arrow points to where you let go. | `annotationAdded("arrow")` |
| 3 | E | `editor.inspector` | The side panel | Settings for the current tool — or for the object you select. | Next |
| 4 | T | `editor.inspector.colour` | Pick a colour | Click any swatch. It colours what's selected and what you draw next. | `styleChanged("strokeColor")` |
| 5 | E | `editor.inspector.stroke` | Width and opacity | Set the line width. Opacity, just below, makes it see-through. | Next |
| 6 | E | `editor.hint` | The hint line | It says what the current tool does and which keys help. | Next |
| 7 | E | `editor.zoom` | Zoom | Pinch or ⌘-scroll to zoom. ⌘0 fits the image, ⌘1 shows it at real size. | Next |
| 8 | E | `editor.actions` | Finish up | Copy it, Save it as a file, or Stack it bottom-right. Done closes. | Next |
| 9 | E | `editor.info` | Replay any time | Click ⓘ to see this tour again or list the keyboard shortcuts. | Next ("Done") |

**Text** (`text`, 6 steps):

| # | Kind | Anchor | Title | Body | Advances on |
|---|---|---|---|---|---|
| 1 | T | `editor.canvas` | Click to type | Click anywhere on the image, type, then press Return. | `annotationAdded("text")` (the text is committed) |
| 2 | E | `editor.canvas` | Or drag a box | Drag instead of clicking to make a text box — the words wrap inside it. | Next |
| 3 | T | `editor.canvas` | Resize your text | Drag a round corner of the text to make it bigger or smaller. | `action("editor.textScaled")` |
| 4 | E | `editor.inspector.styles` | Styles | One click gives your text a ready-made look. | Next |
| 5 | E | `editor.inspector.background` | Background | Put a box behind the text: Solid in any colour, or Auto for contrast. | Next |
| 6 | E | `editor.inspector.effects` | Effects | An outline or shadow keeps text readable on busy images. | Next ("Done") |

**Redaction** (`redaction`, 3 steps):

| # | Kind | Anchor | Title | Body | Advances on |
|---|---|---|---|---|---|
| 1 | T | `editor.canvas` | Hide something | Drag over anything private — it's hidden when you let go. | `action("editor.redactionAdded")` |
| 2 | T | `editor.inspector.strength` | Change the strength | Drag the Strength slider until it can't be read. | `styleChanged("strength")` |
| 3 | E | `editor.inspector.redaction` | Three ways to hide | Switch any time. Black-out is the safest — nothing can be recovered. | Next ("Done") |

**Highlighter** (`highlighter`, 2 steps):

| # | Kind | Anchor | Title | Body | Advances on |
|---|---|---|---|---|---|
| 1 | T | `editor.canvas` | Highlight something | Drag across text like a marker pen. Hold ⇧ for a straight line. | `annotationAdded("highlighter")` |
| 2 | E | `editor.inspector.highlighterStroke` | Marker width | The highlighter keeps its own colour and width, apart from other tools. | Next ("Done") |

**Spotlight** (`spotlight`, 2 steps):

| # | Kind | Anchor | Title | Body | Advances on |
|---|---|---|---|---|---|
| 1 | T | `editor.canvas` | Spotlight something | Drag over what matters — everything else dims. Hold ⌥ for an ellipse. | `annotationAdded("spotlight")` |
| 2 | E | `editor.inspector.spotlightDim` | Dim outside | Set how dark everything outside your spotlights gets. | Next ("Done") |

A step whose anchor isn't on screen is skipped (§7.2) — e.g. "Pick a colour" if the user switched to Blur
first (Blur has no Colour section), or "Change the strength" after switching to Black-out.

#### Anchors — which control carries which id

macOS sets `view.tourAnchor = "…"`; **WPF: `AutomationProperties.AutomationId` on the same element** (§7.2).
The anchor must sit on the element whose bounds should be outlined.

| Anchor | The control (macOS) | Notes |
|---|---|---|
| `editor.toolbar` | the floating tool pill (the frosted bar holding every tool button) | |
| `editor.tool.<tool>` | each tool button; `<tool>` = the tool's id: `select arrow line rectangle filledRectangle ellipse text counter highlighter blur pixelate spotlight crop` | no step uses them yet; set anyway |
| `editor.canvas` | the **scroll view** around the canvas (the whole image area), not the canvas itself | the canvas grows past the window when zoomed in; the scroll view never does |
| `editor.inspector` | the right-side panel | |
| `editor.inspector.<section>` | each section's box (caption + rows) inside the panel; `<section>` = the section id from Part 1: `styles colour stroke highlighterStroke font background effects redaction strength spotlightShape spotlightDim opacity cropHelp selectHelp` | set in the panel's rebuild, so a rebuilt section is anchored again |
| `editor.inspector.arrange` | the Arrange footer (Front / Back / Delete) | |
| `editor.hint` | the hint line (icon + sentence) above the bottom bar | |
| `editor.zoom` | the "Fit · 100% ▾" zoom pull-down | |
| `editor.imageSize` | the "1600 × 1000 px" label | |
| `editor.actions` | the Done · Stack · Save · Copy group | |
| `editor.done` `editor.stack` `editor.save` `editor.copy` | each of those buttons | |
| `editor.undo` `editor.redo` `editor.panelToggle` | the title-bar Undo, Redo and side-panel toggle | |
| `editor.info` | the ⓘ | |

#### Events — what the editor posts, and where

Post at the point the action already happens (§7.2 event bus). Nothing is posted while the editor window is
being built (the starting Arrow is not the user's choice).

| Event | Posted when | macOS place |
|---|---|---|
| `surfaceShown(editor, window)` | right after the editor window is shown | `CaptureCoordinator.presentEditor` (after `makeKeyAndOrderFront` / activate) |
| `toolSelected(<tool id>)` | every tool change the user makes (toolbar click, tool key, Esc → Select, the Redaction switch changing tool, double-clicking a text → Text) — after the side panel was rebuilt for the new tool | `EditorWindowController.selectTool` |
| `action("editor.redactionToolChosen")` | right after `toolSelected` when the tool is **Blur or Pixelate** | same |
| `annotationAdded(<tool id>)` | an object is committed to the document — named like the tool that draws it (`arrow line rectangle filledRectangle ellipse text counter blur pixelate blackout highlighter spotlight`; a redaction by its mode) | `EditorCanvasView.insert` (every new object goes through it; a text when its editing is committed) |
| `action("editor.redactionAdded")` | also for any new redaction (Blur, Pixelate or Black-out) | same |
| `action("editor.textScaled")` | a drag on a text's round **corner** handle that changed it ended | `EditorCanvasView.mouseUp` |
| `styleChanged(<field>)` | a side-panel edit; sliders only when **released** (a click on the track counts), so a drag is one event | `EditorInspectorView` handlers |

`styleChanged` field names: `strokeColor` (colour swatches, Recent, Custom well, Pick from Screen) ·
`textBackgroundColor` (the box colour swatches/well/eyedropper) · `textOutlineColor` · `lineWidth` (slider or
Thin/Medium/Thick) · `fontFamily` · `fontSize` · `textEmphasis` (the B I U S control) · `textAlignment` ·
`textPreset` (a Styles chip) · `textBackgroundMode` · `textBackgroundPadding` · `textBackgroundCornerRadius` ·
`textOutline` · `textShadow` · `textOutlineWidth` · `redactionMode` (Blur/Pixelate/Black-out switch) ·
`strength` (blur radius or pixel size) · `spotlightShape` · `spotlightDim` · `opacity`.

#### Keys while a tag is up (editor-specific)

The tag's keys (§7.3): Return/Enter = Next on Explain steps, Esc = Skip tour, both ignored while typing in a
text box. The editor adds one rule so its own Esc keeps working: **while Esc has a job in the editor — a
tool other than Select is active, or something is selected — Esc goes to the editor** (back to Select, then
clear the selection) and the tour stays. Only when the editor is on Select with nothing selected does Esc skip
the tour. So from the Arrow tool with an object selected: Esc → Select · Esc → nothing selected · Esc → Skip
tour. Typing a label (Return/Esc finish it), Delete (removes the selection) and the tool letter keys all pass
through untouched. macOS: the editor window adopts `TourEscapeClaiming` (TourKit, `Overlay/TagKeys.swift`) and
returns `tool != select || hasSelection`; `TagKeys.action(…, hostClaimsEscape:)` then returns nothing for Esc.
**WPF:** in the tag's `PreviewKeyDown` handler (§7.3), check the host editor's same condition before treating
Esc as Skip tour; if it's true, leave `e.Handled = false`.

#### The ⓘ in the editor

Installed by the editor itself (`InfoButton.install(in: window, tour: editor, shortcuts: …)` in
`EditorWindowController.buildTitlebarButtons`), as the **rightmost** title-bar item: Undo · Redo · panel toggle
stay to its left (layout §7.3; Windows: immediately left of the caption buttons). **Replay Tour** replays the
**Editor** tour in this window (the tool tours replay from the menu bar's Help & Tours). Its **Keyboard
Shortcuts** list, in this order (keys · action) — on Windows write ⌘ as Ctrl, ⇧ as Shift, ⌥ as Alt, ↩ as
Enter, ⌫ as Delete (`Ctrl+Z`, `Ctrl+Shift+Z`…):

| Keys | Action |
|---|---|
| V | Select |
| A | Arrow |
| L | Line |
| R | Rectangle |
| F | Filled Rectangle |
| O | Ellipse |
| T | Text |
| N | Counter |
| H | Highlighter |
| B | Blur |
| P | Pixelate |
| X | Black-out |
| S | Spotlight |
| C | Crop |
| Esc | Back to Select, then clear the selection |
| ⌫ | Delete the selection |
| ] / [ | Bring to front / Send to back |
| ⌘Z | Undo |
| ⇧⌘Z | Redo |
| ⌘+ / ⌘− | Zoom in / out |
| ⌘0 | Zoom to fit |
| ⌘1 | Actual size (100%) |
| ⌥⌘I | Show or hide the side panel |
| ↩ / ⇧↩ | Finish text / New line |
| ⇧⌘C | Copy |
| ⌘S | Save |
| ⌘W | Done — close the editor |

(The tool rows are generated from the tools' own names and keys in toolbar order, with Black-out — which has a
key but no button — after Pixelate.)

#### Tests to port (`Packages/EditorKit/Tests/EditorKitTests/EditorTourTests.swift`)
- every editor-tour body fits the tag's 2 lines (a wrapping label with the tag's body font at 236 pt: unlimited
  height ≤ 2-line height);
- every step's anchor exists on a real editor window, with the tour's tool chosen (Editor → Arrow, Text → Text,
  Redaction → Blur, Highlighter → Highlighter, Spotlight → Spotlight);
- every tool button and bottom-bar/title-bar control carries its anchor;
- the ⓘ is rightmost, replays `editor`, and lists every tool's key plus Undo/Redo/panel/zoom keys;
- opening the editor posts nothing; choosing Text posts `toolSelected("text")`; Blur and Pixelate each post
  `toolSelected(…)` then `action("editor.redactionToolChosen")`;
- inserting an arrow / text posts `annotationAdded("arrow"/"text")`; a Pixelate redaction posts
  `annotationAdded("pixelate")` then `action("editor.redactionAdded")`;
- a colour swatch posts `styleChanged("strokeColor")`; releasing the Strength slider posts `styleChanged("strength")`;
- the window claims Esc on Arrow, and not on Select with nothing selected.

#### How it was verified on macOS (probe, 2026-09-25)
A headless probe (a throwaway Swift package outside the repo that compiled the real `TourCoordinator` from
`App/Tours/` with the real tag overlay and a real editor window, all parked behind the owner's windows, using
its own preferences domain — never the app's) ran as a **new user who said yes**: the editor's `surfaceShown` started the Editor tour;
all 9 steps were shown in order with the right control outlined and no body cut off; each Try step advanced
only on the real action (a synthetic drag drew the arrow; a swatch click; a click, typing and Return/Esc
committed a text; a drag on the text's corner scaled it 24 → 49 pt; a blur drag; releasing the Strength
slider; a highlighter stroke; a spotlight drag). Choosing the Highlighter mid-Editor-tour didn't start its tour,
which then started when it was chosen afterwards. Text, Redaction, Highlighter and Spotlight each started on
their trigger and showed every step; each tour was marked seen once and never started again. While tags were
up: Return = Next on Explain steps and passed through on Try steps and while typing; Esc while typing finished
the text; Esc on Blur went back to Select and kept the tour; Delete removed the selected stroke and kept the
tour; from a spotlight with a selection it took 3 Escs (Select, clear, Skip tour). **Replay Tour** in the ⓘ
restarted the Editor tour; Help & Tours with no editor open showed "Editor Tour starts the next time you use it"
and started it in the next editor. An **existing user** got nothing by itself (surface shown, every tool
chosen, an object drawn — no tag, nothing marked seen), while the ⓘ still replayed the tour. 142 checks, all
passing.

### 7.6 First recording (strip) + recording pill tours (lane 7R)

**What it is.** Two tours for recording. **First recording** walks through every choice on the record
setup strip (Part 4) and ends by asking the user to start a recording; the moment they do, it hands over to
**Recording pill**, which explains the live recording controls (Part 5) *while the recording runs*. Terms
(tour, step, Explain/Try, anchor, event, surface, tag, ⓘ): §7.2–§7.3. A tag must **never** appear in the
user's recording — see "Tags are never recorded" below.
macOS files: steps `Packages/TourKit/Sources/TourKit/Catalog/RecordingTours.swift`; anchors and events
`App/Recording/RecordStripController.swift`, `App/Recording/RecordingControlsController.swift`,
`App/Recording/RecordingCoordinator.swift`; tags kept out of recordings `App/Recording/TourTagRecordingGate.swift`
(+ `ScreenRecorder.updateFilter` in RecordingKit); tests `Packages/RecordingKit/Tests/RecordingKitTests/RecordingTourTests.swift`
(every body fits the tag's 2 lines at its 260 pt max width, every Try step waits for an event a surface posts).
Snapshots: `docs/reviews/2026-09-25-tours/recording-01-strip-microphone-choices.jpg` (step 5, tag above the
strip) and `recording-02-pill-mute-mic-try.jpg` (step 2, tag above the pill).

#### First recording — tour id `firstRecording`, version 1
- **Surface** `recordStrip` (the strip panel). **Starts** the first time the strip appears (`RecordStripController.show`
  posts `surfaceShown(recordStrip)` as its last line) — only for users with first-use tours on (§7.1); the ⓘ
  and Help & Tours → "Recording Setup Tour" replay it. **Hands over to** `recordingPill`.
- Steps, verbatim (E = Explain, advances on Next; T = Try, advances on the event; strings use ’ and “ ”):

| # | Kind (event) | Anchor = control | Title | Body |
|---|---|---|---|---|
| 1 | E | `strip.targets` = the Full Screen · Area… · Window… group | What to record | Full Screen records this screen, Area a part you drag, Window just one window. |
| 2 | E | `strip.format` = "Format" caption + MP4/GIF picker | MP4 or GIF | MP4 is a video with sound. GIF is a silent, looping animation. |
| 3 | E | `strip.fps` = "FPS" caption + 30/60 picker | Frame rate | 60 frames per second looks smoother; 30 makes smaller files. |
| 4 | T `menuOpened("strip.microphone")` | `strip.microphone` = the Microphone dropdown | Open the Microphone menu | Click Microphone to see every input you can record from. |
| 5 | E | `strip.microphoneColumn` = the whole Microphone column (caption, level meter or "Allow microphone access…" link, dropdown) | Microphone choices | Pick a mic, or Off to skip it. The level meter above shows it can hear you. |
| 6 | T `menuOpened("strip.systemAudio")` | `strip.systemAudio` = the System audio dropdown | Open System audio | Click System audio to choose which sounds from your Mac are recorded. |
| 7 | E | `strip.systemAudio` | Sound choices | Off, every app’s sound, or every app except BetterScreenshot’s own sounds. |
| 8 | E | `strip.camera` = the Camera dropdown | Camera bubble | Adds your webcam in a round bubble. Camera Size sets Small or Medium. |
| 9 | E | `strip.cursor` = the Mouse cursor dropdown | Mouse cursor | Choose whether your pointer shows in the video. |
| 10 | E | `strip.hint` = the hint line (ⓘ icon + text) | Hints | Point at any control and this line explains it. |
| 11 | T `choiceMade("strip.targets")` | `strip.targets` | Start recording | Click Full Screen, Area or Window to start. The recording controls come next. |

- **GIF mode.** GIFs are silent, so the Microphone and System audio dropdowns are disabled; while Format is
  GIF the strip **removes** the anchors `strip.microphone`, `strip.microphoneColumn` and `strip.systemAudio`
  (whenever it rebuilds its menus), so steps 4–7 are skipped instead of asking the user to open a disabled
  menu. Back to MP4 → the anchors return.
- **Menus.** Steps 4 and 6 complete the moment the dropdown's menu opens. The tag stays where it is (a menu
  is drawn above it), shows its 0.8 s done state, then the next Explain step (5 / 7) describes the choices —
  while the menu is still open or after it closes.
- **Hand-over.** Step 11 completes on any of the three target buttons (the event is posted before the strip
  hides): First recording is marked seen and Recording pill is queued; it starts as soon as the pill appears
  (Full Screen: right away; Area/Window: once the user has picked). Closing the strip another way (✕, the
  record shortcut) pauses the tour; it resumes at that step the next time the strip opens.
- **Events the strip posts** (`TourEvents.post`, after the choice is saved): `menuOpened(<anchor>)` for each of
  its four dropdowns — `strip.microphone`, `strip.systemAudio`, `strip.camera`, `strip.cursor` — from the
  dropdown menu's `menuWillOpen` delegate (any way of opening: click, keyboard, VoiceOver); `choiceMade(<anchor>)`
  for `strip.format`, `strip.fps`, `strip.microphone`, `strip.systemAudio`, `strip.camera` (also for Camera
  Size) and `strip.cursor`; `choiceMade("strip.targets")` from Full Screen / Area… / Window…. **WPF:**
  `ComboBox.DropDownOpened` → `menuOpened`, `SelectionChanged` → `choiceMade`.
- **The strip's ⓘ.** `InfoButton(tour: firstRecording, shortcuts:)`, 26 × 22, tinted like the strip's secondary
  text (white 60 %), in the top row **16 pt after the FPS group and 2 pt before ✕** (the row's flexible spacer
  absorbs its width — the strip keeps its size). Hovering it brightens it and the hint line reads "Replay this
  tour, or see the keyboard shortcuts." Keyboard Shortcuts rows (keys = the user's current combos, a row is
  left out when that action is unbound): **Start/Stop Recording** combo → "Close this strip · stop a
  recording"; **Pause/Resume Recording** combo → "Pause or resume a recording". Defaults: only the first,
  ⇧⌘5 (Windows: the port's own combo string, e.g. Ctrl+Shift+5).
- **Anchor-only layout change.** The three target buttons are wrapped in their own horizontal stack (spacing
  8 = the row's), so the tour can outline them together; pixel-identical. WPF: a `StackPanel` around them.

#### Recording pill — tour id `recordingPill`, version 1
- **Surface** `recordingPill`. **Starts** the first time the pill appears — `RecordingControlsController.show`
  posts `surfaceShown(recordingPill)` as its last line, i.e. when a recording session starts (countdown
  included) — or at once after First recording hands over. No ⓘ (the pill is too small): Help & Tours →
  "Recording Controls Tour" replays it (while no recording runs it waits for the next one).
- Steps:

| # | Kind (event) | Anchor = control | Title | Body |
|---|---|---|---|---|
| 1 | E | `pill.timer` = the elapsed-time column | Recording time | How long you’ve been recording. Drag the pill anywhere you like. |
| 2 | T `action("pill.micMuted")` | `pill.mic` = Mic | Mute the mic | Click Mic to mute it — click again to unmute. The video stays in sync. |
| 3 | E | `pill.systemAudio` = System audio | System audio | Mutes the sound your Mac plays. It’s greyed out when that wasn’t recorded. |
| 4 | E | `pill.camera` = Camera | Camera bubble | Shows or hides your camera bubble while you record. |
| 5 | E | `pill.switch` = Switch Window… / Switch Area… | Record something else | Move the recording to another window or area without stopping. |
| 6 | E | `pill.restart` = ↺ | Restart | Deletes what’s recorded so far and starts again. Click twice to confirm. |
| 7 | E | `pill.discard` = 🗑 | Discard | Stops and deletes this recording. Click twice to confirm. |
| 8 | E | `pill.pause` = ⏸ | Pause | Pauses the recording. Press it again to carry on. |
| 9 | E | `pill.collapse` = the chevron | Fewer controls | Collapses the pill to the timer, Pause and Stop. Click again for all. |
| 10 | T `action("recording.stopped")` | `pill.stop` = ■ | Stop when done | Press Stop when you’re finished. Your video then opens in a card. |

- **Skipped by design** (a missing anchor = skipped step): **2** when the recording has no microphone track —
  the Mic button is greyed out, so the pill **removes its `pill.mic` anchor** rather than ask for a disabled
  click; **5** on full-screen recordings (no Switch button); **2–7** while the pill is collapsed (hidden).
  Explain steps on a greyed-out control (System audio / Camera when unavailable) still show — their bodies
  say so. The tag sits above (or below, at the top of the screen) the pill, never on it (§7.3 keep-out).
- **Events:** `action("pill.micMuted")` — `RecordingControlsController.micTapped` when Mic is clicked while
  audible (the muting click); `action("recording.stopped")` — the **first line of `RecordingCoordinator.stop()`**,
  before the pill hides, so every way of stopping completes step 10 (■, the record shortcut, the menu bar, a
  failed stream, quitting); `action("recording.started")` — `RecordingCoordinator.begin` once the engine runs
  (no step waits on it). Discard, Restart and cancelling the countdown post nothing (the tour pauses when the
  pill goes and resumes with the next recording).

#### Tags are never recorded — not even for one frame (owner)
A tag is two windows per overlay (decor = dim + box + leader line, and the bubble; §7.3). Recording pill runs
*during* a recording and First recording's last step starts one, so the recorder must never capture them.

**macOS (ScreenCaptureKit).** A display recording captures through an `SCContentFilter` whose left-out windows
are fixed when the filter is built or updated. `TourTagRecordingGate` (App) with `RecordingSafeTagPresenter`
(the app's tag presenter: TourKit's `TagOverlayController`, windows exposed by `TagOverlayController.windows`):
1. Every tag window is **registered with the gate the moment it's created** (before it's ever shown).
2. **Every display filter** the recorder builds — at start, on Switch Area…, and on updates — **leaves out every
   tag window that exists**. The recorder now fetches `SCShareableContent` with `onScreenWindowsOnly: false`,
   so tag windows that are ordered out at that moment are listed too; a left-out window stays left out when it's
   ordered out and back in (probed). In the usual flow (First recording → Recording pill) the tag windows
   exist before the recording starts, so they're covered from the first frame.
3. A tag window the running filter doesn't cover — only one shown for the **very first time** after the filter
   was built — is kept **fully transparent (alpha 0)** from registration on, and only made visible after the
   running stream's filter has been updated to leave it out: the gate calls `onNeedsExclusion`; the recorder
   rebuilds the filter, calls `willUse(tags)` (hides any tag window only the old filter covered),
   `SCStream.updateContentFilter`, waits 50 ms, then `didUse(tags)` (shows the covered ones). One update at a
   time; skipped during a Switch (that retarget builds its own filter the same way); the gate re-checks every
   0.25 s. A token stops an older update from showing windows after a newer filter was chosen.
4. After the stream has stopped (`tearDownPanels`), every tag is shown normally again.
Window recordings (a single-window filter) never contain the app's own windows and don't use the gate. The
pill is still left out only when "Show recording controls in the video" is off; tags are left out always.

**Windows (WPF).** Much simpler, because Windows has a per-window flag: call `SetWindowDisplayAffinity(hwnd,
WDA_EXCLUDEFROMCAPTURE)` on **both** tag windows in `SourceInitialized`, i.e. before they're ever shown (already
listed in §7.3). Every capture that goes through the Desktop Window Manager (DWM, Windows' compositor) honours
it — Desktop Duplication (ffmpeg's `ddagrab` input), Windows.Graphics.Capture, and ffmpeg's `gdigrab` (a GDI
BitBlt copy of the screen) — so no filter bookkeeping is needed. It needs Windows 10 version 2004 or later; on
older builds hide the tags while a recording runs instead. Verify with a probe like the one below: record a
clip while a tag is up and check the decoded frames for tour red (#FF453A) where the tag is.

**How it was verified on macOS (lane probe, 2026-09-25; the probe lived in a scratch folder, not the repo).**
A probe compiled from the real App sources
(`RecordingCoordinator`, strip, pill, `TourCoordinator` for a new user who said yes, the real tag overlay;
every window parked just above the desktop, behind the user's windows; the probe added the other apps' windows
to the filter's exclusions so its own low windows weren't hidden behind them in the capture):
- **Control:** a tag *not* left out, recorded 1.2 s → decoded frames show tour red in 88 % of the bubble's
  sample points and 85 % of the box outline's, in all 26 frames — the check does see tags.
- **Real run:** First recording walked step by step on the real strip → Full Screen → a real 8 s recording with
  Recording pill stepping through, plus a tag that was hidden when the recording started and shown again during
  it (visible at once), and a brand-new tag overlay first shown mid-recording (transparent, then visible 205 ms
  later after the filter update). 50 frames decoded, 20 tag regions (bubble + box outline of every pill step
  and both extra tags): **0 % tour red in every region of every frame**; the pixels there were the probe's
  green backdrop, i.e. the regions were in view of the capture.
- Tour checks on the same run: all 11 strip steps and the expected pill steps shown in order (2 and 5 skipped
  by design: no mic track, full screen); a standalone pill run with a mic track and an area recording showed all
  10; every Try step advanced on its real action (menu delegate, target button, Mic, ■); both tours ended
  "seen". Pop-up menus were driven through the strip's real menu delegate: on macOS 26 a real menu's window
  isn't in `NSApp.windows` when tracking begins, so a probe can't keep it off the owner's screen — don't open
  real menus in probes.

### 7.7 Video editor tour (lane 7R)

**What it is.** A tour of the Edit Video window (Part 6): the preview, the timeline, a real split and delete,
the per-part controls and the two ways to save. macOS files: steps
`Packages/TourKit/Sources/TourKit/Catalog/VideoEditorTours.swift`; anchors, events, ⓘ and the start signal
`Packages/RecordingKit/Sources/RecordingKit/TrimWindowController.swift`; tests `RecordingTourTests.swift`
(every step's anchor exists on a fresh window, the ⓘ and its keys). Snapshot:
`docs/reviews/2026-09-25-tours/video-01-split-try.jpg` (step 3).

- Tour id `videoEditor`, version 1, surface `videoEditor`. **Starts** when an Edit Video window has **loaded
  its recording and is on screen**: the window posts `surfaceShown(videoEditor)` once per window, from whichever
  comes last of "load succeeded" and `showWindow` — never over "Loading…" or the "can't be opened" state.
- Steps:

| # | Kind (event) | Anchor = control | Title | Body |
|---|---|---|---|---|
| 1 | E | `video.preview` = the video preview | Preview | Plays only the parts you keep. Click it, or press Space, to play. |
| 2 | E | `video.timeline` = the timeline's visible area (ruler + filmstrip) | The timeline | Click to move the playhead. Drag a part’s yellow edge to trim it. |
| 3 | T `action("video.split")` | `video.timeline` | Split the clip | Click the timeline to place the playhead, then press S or click Split. |
| 4 | T `action("video.segmentDeleted")` | `video.timeline` | Delete a part | Click a part to select it, then press ⌫ to cut it out. |
| 5 | E | `video.segment` = the selected-part row ("Segment n of m", its source range, Speed, Mute segment) | Selected part | Change its speed or mute just this part. Right-click a part for the same. |
| 6 | E | `video.saveCopy` = Save as Copy (with its ▾ menu) | Save a copy | Saves the edit as a new file. The ▾ menu exports a GIF instead. |
| 7 | E | `video.replace` = Replace Original | Replace the original | Overwrites the recording with this edit, then reloads it for more changes. |

- **Why step 3 outlines the timeline, not the Split button:** the tag placed under the button covered the very
  timeline the step asks the user to click (probe snapshot). `video.timeline` is the timeline's **scroll view**
  (what's visible), not its content view, which is wider when zoomed in.
- **Events** (`TourEvents.post`, only when the edit actually happened — a refused edit beeps and posts nothing,
  e.g. the playhead too close to a part's edge, or deleting the only part): `action("video.split")` from
  `splitAtPlayhead` (S, ⌘B, the Split button, the right-click menu); `action("video.segmentDeleted")` from
  `deleteSelected` (⌫ / Delete key, the Delete button, the right-click menu).
- **ⓘ:** `InfoButton.install(in: window, tour: .videoEditor, shortcuts:)` — the rightmost title-bar item (§7.3).
  Keyboard Shortcuts (keys → action), in this order: `Space` → Play or pause · `← →` → Step one frame ·
  `S or ⌘B` → Split at the playhead · `⌫` → Delete the selected part · `I` → Set the in point (cuts what's
  before) · `O` → Set the out point (cuts what's after) · `⌘Z` → Undo · `⇧⌘Z` → Redo. (Windows: Ctrl for ⌘,
  Backspace/Delete for ⌫, Ctrl+Shift+Z for redo — whatever the port's editor actually binds.)
- **macOS gotcha:** `NSComboButton` (Save as Copy) ignores `setAccessibilityIdentifier` — it reads back "" — so
  its anchor was invisible to the tour; a tiny subclass (`AnchoredComboButton`) keeps the id. WPF's
  `AutomationProperties.AutomationId` has no such issue.
- **Verified (probe, 2026-09-25):** on a real Edit Video window with a generated 4 s clip, all 7 steps shown in
  order; step 3 advanced after a click on the timeline + the S key sent through the window; step 4 after a click
  on a part + ⌫; Done on step 7 finished the tour; the ⓘ's Replay Tour restarted it at step 1; Skip tour hid the
  tag.

### 7.8 Settings + History tours, Help & Tours menu, Settings row (lanes 7S + 7A)

**Settings + History tours (lane 7S).** Both windows are SwiftUI on macOS; anchors are `.tourAnchor("…")`
(a transparent view behind the element, same frame — WPF: `AutomationProperties.AutomationId` on the
element). Steps in `Packages/TourKit/Sources/TourKit/Catalog/ShellTours.swift`; wiring in
`App/Settings/SettingsWindowController.swift` + `SettingsView.swift` and
`App/History/HistoryWindowController.swift`. Snapshots: `docs/reviews/2026-09-25-tours/shell-settings.jpg`
(step 3), `shell-history.jpg` (step 3). E/T and verbatim-string conventions as in §7.4.

Both windows report themselves with `surfaceShown(settings|history, window)` at the end of their `show()`,
**every** time they're shown (the coordinator decides: first time for a user with tours on, a queued
replay, or a paused tour). Their anchors already exist in that same run-loop turn (checked by the probe).

**Scrolling.** Before showing any step's tag, the coordinator scrolls the anchor into view
(`NSView.scrollToVisible(bounds)`; a no-op when it's visible or not in a scroll view) — added to
`TourCoordinator.present`. Needed here: the Settings content is 1246 pt tall in a window capped at 98 % of
the screen (847 pt on a 956 pt screen), and the Keyboard Shortcuts card is below the fold. **WPF:**
`element.BringIntoView()` before placing the tag.

**Settings tour** — id `settings`, version 1, surface `settings`, trigger `surfaceShown(settings)`, no hand-over.

| # | | Anchor → the element it outlines | Title | Body | Advances on |
|---|---|---|---|---|---|
| 1 | E | `settings.cards` → the three-column card grid (everything between the header and Keyboard Shortcuts) | Your settings | Related settings share a card. Changes apply right away. | Next |
| 2 | E | `settings.tip` → the ⓘ help icon next to "After a capture" (first row of the Capture card) | Tips on every row | Hover any ⓘ for a plain explanation of that setting and an example. | Next |
| 3 | E | `settings.shortcuts` → the full-width Keyboard Shortcuts card (scrolled into view) | Keyboard shortcuts | Click any shortcut, then press new keys to change it. Esc cancels. | Done |

On a 1470 × 956 screen the 960 pt window leaves no room beside it, so step 1's tag sits inside the box's
top-left corner (the §7.3 "over" fallback) and step 3's tag sits above the card.

**History tour** — id `history`, version 1, surface `history`, trigger `surfaceShown(history)`, no hand-over.

| # | | Anchor → the element it outlines | Title | Body | Advances on |
|---|---|---|---|---|---|
| 1 | E | `history.grid` → the grid's scroll area (or, when History is empty, the empty-state view) | Your capture history | Every screenshot and recording you take is kept here, newest first. | Next |
| 2 | T | `history.item` → the first (newest) capture's cell | Select a capture | Click any capture to select it. Double-click opens it instead. | `action("history.selected")` |
| 3 | E | `history.item` | Several at once | ⌘-click or ⇧-click to add more, then drag them into any app together. | Next |
| 4 | E | `history.actions` → the bottom action bar (count · Copy · Annotate · Pin · Edit Video… · Show in Finder · Delete · ⋯) | Actions | Copy, annotate, pin or delete the selection. Right-click does the same. | Done |

- `history.item` exists only while History has entries, so with an empty History the tour is steps 1 and 4.
- Events (`HistoryView` in `HistoryWindowController.swift`): `action("history.selected")` after any single
  click on a cell (plain, ⌘ or ⇧ — the selection has already changed; a double-click's first click posts it
  too); `action("history.dragged")` when a drag of one or more captures out of the grid starts (no step waits
  for it yet). **WPF:** Ctrl-click / Shift-click and write "Ctrl-click or Shift-click" in step 3's body.

**The ⓘ on both windows** (§7.3 look and menu): `InfoButton.install(in: window, tour:, shortcuts:)` when the
window is built (`makeWindow()`), the rightmost title-bar accessory. **Replay Tour** runs that window's tour
from step 1 now (for every user — existing users included). **Keyboard Shortcuts** lists:
- **Settings:** every *bound* global shortcut in `HotkeyAction` order as (keys, action title), then
  (**Esc**, **Cancel changing a shortcut**) — with the defaults: ⇧⌘4 Capture Area · ⇧⌘8 Capture Window ·
  ⇧⌘6 Capture Full Screen · ⇧⌘7 Capture Text · ⇧⌘5 Start/Stop Recording · Esc Cancel changing a shortcut.
  The list follows rebinds made while the window is open (it observes the bindings).
- **History:** ⌘-click — Add to or remove from the selection · ⇧-click — Select everything in between ·
  Double-click — Open (screenshots open in the editor) · Right-click — More actions (WPF: Ctrl-click /
  Shift-click).

**Verified (same probe as §7.4).** Settings: all three anchors present on first show; 1/3 → 2/3 (anchor
16 × 16, the ⓘ) → 3/3 with the Keyboard Shortcuts card scrolled fully into the window → Done → marked seen;
the ⓘ lists the defaults above plus Esc and updates after a rebind to ⌥⌘4; Replay Tour restarts at 1/3.
History (three synthetic captures in a scratch History folder): 1/4 → 2/4 → a synthetic click on the first
cell's click layer posted `history.selected` → 3/4 (cell selected) → 4/4 → Done → seen; the ⓘ lists 4
gestures; Replay Tour restarts. An **existing** user got no question, and Settings, History and a new card
started nothing — but both ⓘ Replay Tours worked. A new user who pressed **No Thanks** got nothing either.

**Help & Tours menu (lane 7A).** A submenu in the menu-bar menu (Windows: the tray menu), placed right
above **Settings…**, after the History group's separator. Every item has an icon (SF Symbol name given —
map to the port's icon set):

| Item | SF Symbol | Does |
|---|---|---|
| **Help & Tours ▸** (parent) | `questionmark.circle` | — |
| Take the Welcome Tour | `hand.wave` | replay `welcome` (opens the Welcome window: the all-set page, or the permission page if not granted) |
| — separator — | | |
| Quick Access Tour | `rectangle.on.rectangle` | replay `quickAccess` |
| Editor Tour | `pencil.and.outline` | replay `editor` |
| Text Tool Tour | `textformat` | replay `text` |
| Blur & Pixelate Tour | `eye.slash` | replay `redaction` |
| Highlighter Tour | `highlighter` | replay `highlighter` |
| Spotlight Tour | `flashlight.on.fill` | replay `spotlight` |
| Recording Setup Tour | `record.circle` | replay `firstRecording` |
| Recording Controls Tour | `capsule` | replay `recordingPill` |
| Video Editor Tour | `film` | replay `videoEditor` |
| Settings Tour | `gearshape` | replay `settings` (opens Settings) |
| History Tour | `clock.arrow.circlepath` | replay `history` (opens History) |
| — separator — | | |
| Reset All Tours | `arrow.counterclockwise` | clears `toursSeen` + `toursPaused`, HUD "Tours reset" |

"Replay" = §7.2 `replay(id, nil)`: start now if that window is open, otherwise wait for it (the HUD says
"<title> starts the next time you use it" when the app can't open that window itself). Titles and icons
come from `TourID.menuTitle` / `menuSymbol` (`Packages/TourKit/Sources/TourKit/TourNames.swift`).

**Settings → Startup → "Tours & tips" (lane 7A).** Screenshot: `docs/parity-v3/part7-settings-tours-row.png`.
Inside the **Startup** card, under "Launch at login", after a 1 pt divider line (same as the Recording
card's divider), 14 pt row spacing:
- field label **"Tours & tips"** + ⓘ (same style as "Mouse cursor"); its tip: title "Tours & tips", text
  "Short guided tours point out each part of the app — the editor, recording, History — the first time you
  use it. Each one runs once, and you can skip it any time. Reset All Tours lets them show again; Help &
  Tours in the menu bar replays any one of them.", example "Turn this on, then open the editor to be walked
  through its tools.";
- row title **"Show me around the first time I use each part"** (wraps to two lines) with the mono switch
  on the right — bound to `firstUseToursEnabled` (absent = off; new users see their answer, existing users
  off). The spec calls it a checkbox; it uses the Settings window's switch like every other boolean there;
- pill button **Reset All Tours** → clears `toursSeen` and `toursPaused` only (never `tourAudience`,
  `tourQuestionAnswered` or the switch); a small "Tours reset" note then appears beside the button.

To keep the three columns about equal in height, the Startup card moved to column 1 (under Quick Access
Overlay) and Pin to Screen to column 2 (under Recording). Columns are now: Capture · Quick Access Overlay ·
Startup | Recording · Pin to Screen | In the video · History · Save location.
