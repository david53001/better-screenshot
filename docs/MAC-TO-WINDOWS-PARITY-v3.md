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

### A.2 Floating recording pill (compact v1) + "Show stop button in recording"

(Part 5 turns this into the expanded pill — port Part 5's layout; the rules here still hold.)
- **When:** shown on the recording screen as soon as a recording is started — **before** the countdown —
  and hidden on stop, cancel, or failure. **Stop during the countdown cancels** the recording.
- **Layout v1:** borderless, non-activating, draggable pill 176×40 pt, fully rounded (radius 20), dark HUD
  material, drop shadow, always-on-top (macOS `.statusBar` level), positioned bottom-centre of the
  screen's visible area, 20 pt above its bottom. Left to right: red dot (10 pt, x = 16) · elapsed time
  (monospaced digits, 14 pt semibold, white; "m:ss") · Pause button (32×32, symbol `pause.fill` 15 pt,
  white) · Stop button (32×32, `stop.fill`, red). Buttons react on the first click without activating the
  app (macOS `acceptsFirstMouse`; WPF: `ShowActivated=false` + `WS_EX_NOACTIVATE`).
- **Paused:** the time freezes and turns secondary grey; Pause becomes `play.fill` "Resume recording".
  Tooltips: "Pause recording" / "Resume recording" / "Stop recording".
- **Setting:** Settings → Recording → **"Show stop button in recording"**, default **off**, persisted key
  `controlsInRecording` ("true"/"false" in the recording-config dictionary). Help text (verbatim):
  "While recording, a floating pill with the timer, Pause and Stop is always on screen. Off: it's hidden
  from the video itself. On: it's recorded like any other window." Example line: "Leave off for clean
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
- **Entry points:** a **Trim** button (`scissors`, tooltip "Trim") on the Quick Access card of **MP4**
  recordings only — the recording card becomes Copy file · Trim · Open · Show in Finder · Close (5 × 32 pt
  buttons; GIF cards keep 4) — and **"Trim…"** in the History window (action bar + right-click menu),
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
- Opening the window from the **History** window's **Trim…** passes no callback: nothing is restored
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
│  │                                                              │    │ RECENT ● ● ●         │ │ ← hidden if empty
│  │                 canvas (centred, Fit by default)             │    │ [▬] [⌖ Pick from Screen] ← colour well + eyedropper
│  │                                                              │    │ ──────────────────── │ │
│  │                                                              │    │ STROKE               │ │
│  │                                                              │    │ Width ──●────── 4 px │ │
│  │                                                              │    │ [Thin|Medium|Thick]  │ │
│  │                                                              │    │ ──────────────────── │ │
│  │                                                              │    │ OPACITY              │ │
│  │                                                              │    │ ───────────●─ 100%   │ │
│  └──────────────────────────────────────────────────────────────┘    └──────────────────────┘ │
├──────────────────────────────────────────────────────────────────────────────────────────────┤
│ ⓘ Drag to draw an arrow — it points to where you let go.                                      │ ← hint line
│ 1600 × 1000 px                          [Fit · 115% ⌄] │ Done  [Stack]  [Save]  [Copy]        │ ← action row
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Window.** Title "Annotate", transparent title bar. Minimum size **884 × 440** while the panel is shown
(600 canvas column + 8 gap + 264 panel + 12 margin), **600 × 440** while it is hidden. Initial content size:
`width = min(max(imageW' + 48, 600) + 264 + 20, screenW − 40)`, `height = min(max(imageH' + 112 + 84, 520),
screenH − 60)`, where `imageW' = min(image px width, 1200)` and `imageH'` keeps the aspect ratio; screen =
the main screen's visible area. Backdrop behind the canvas: white 12% (dark mode) / white 90% (light).

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
- Row labels: 12pt regular, white 88%. Value readouts: 11.5pt monospaced digits, white 55%, right-aligned,
  40pt wide. Controls use the small control size (≈22pt tall); slider rows are 24pt tall.

Section contents (top to bottom, only the sections listed in §1.2 appear):

| Section (caption) | Rows (exact) |
|---|---|
| **Colour** | ① 8 preset swatches spread evenly across 232pt: Red `#FF453B` (1.00, 0.27, 0.23), Orange (1.00, 0.62, 0.04), Yellow (1.00, 0.84, 0.04), Green (0.19, 0.82, 0.35), Blue (0.04, 0.52, 1.00), Purple (0.75, 0.35, 0.95), White, Black — sRGB; each 22×22 hit area with a 16pt circle, 1px white-22% outline, tooltip = colour name; the current colour gets a 2px white ring. ② "RECENT" caption (48pt wide) + up to 6 swatches 6pt apart, tooltip "Recent colour"; row hidden when there are none. ③ Colour well 44×24 (tooltip "Custom colour — opens the colour picker") + small rounded button **"Pick from Screen"** with SF `eyedropper` (tooltip "Eyedropper — click anywhere on screen to use that colour"). |
| **Stroke** | ① "Width" label (44pt) · slider 1…24 (whole px) · value "4 px". ② Segmented **Thin / Medium / Thick** = 2 / 4 / 7 px (tooltips "2 px", "4 px", "7 px"), equal widths, full row; no segment highlighted when the width is another value. |
| **Font** (Text) | ① Font pop-up, full width (tooltip "Font"): System, Rounded, Serif, Mono (each drawn in its own face), separator, every installed family. ② Size pop-up 84pt wide (tooltip "Font size"): 12, 14, 18, 24, 30, 36, 48, 64, 96 "pt" (+ the current size if it's another value) · Bold/Italic toggle pair (SF `bold`, `italic`, 30pt segments, tooltips "Bold", "Italic"). ③ Alignment, full width, three equal segments (SF `text.alignleft`, `text.aligncenter`, `text.alignright`; tooltips "Align left", "Align centre", "Align right"). |
| **Background** (Text) | Checkbox **"Contrasting box behind the text"** (tooltip "A dark or light box, whichever stands out against the text colour") = today's auto-contrast chip, `textBackground`. *Part 2 replaces this section with None / Solid / Auto + colour, padding, radius.* |
| **Redaction** (Blur/Pixelate tools) | Segmented **Blur / Pixelate**, full width (tooltips "Blur (B)", "Pixelate (P)"); switches the active tool. *Part 3 adds Strength here.* |
| **Opacity** | Slider 10…100 (no label) · value "100%" (tooltip "How see-through the object is"). |
| **Arrange** (Select with a selection) | Three equal small buttons, 6pt apart: **Front** (SF `square.3.layers.3d.top.filled`, port `icon-bring-front`, tooltip "Bring to front ( ] )"), **Back** (`square.3.layers.3d.bottom.filled`, `icon-send-back`, "Send to back ( [ )"), **Delete** (`trash`, `icon-trash`, "Delete (⌫)"). |
| *(note)* Crop | No caption. 12pt, white 62%: "Drag over the part of the image you want to keep. Undo (⌘Z) brings the rest back." |
| *(note)* Select, nothing selected | No caption: "Click an object on the image to change it here. Drag across empty space to select several." |

**Bottom bar** (84pt tall, standard header material, 1px separator line on top).
- **Hint line:** 10pt below the top, 16pt from the left: SF `info.circle` (12pt, tertiary label colour) +
  6pt + the sentence (12pt, secondary label colour, truncates at the right).
- **Action row:** 12pt above the bottom. Left (18pt in): image size "1600 × 1000 px" (11.5pt monospaced,
  secondary). Right (16pt in), 8pt apart: **zoom pull-down** (small) · 12pt · vertical separator (18pt) ·
  10pt · **Done** (borderless, secondary text, ⌘W) · **Stack** (SF `square.stack`, tooltip "Keep in the
  bottom-right stack") · **Save** (SF `square.and.arrow.down`, ⌘S) · **Copy** (accent-filled, white text,
  SF `doc.on.doc`, ⇧⌘C). Copy stays the rightmost, primary button.

**Title bar, right side:** Undo (SF `arrow.uturn.backward`, tooltip "Undo (⌘Z)"), Redo
(`arrow.uturn.forward`, "Redo (⇧⌘Z)"), 10pt gap, **panel toggle** (SF `sidebar.right`, an on/off button,
tooltip "Hide Inspector (⌥⌘I)" when shown / "Show Inspector (⌥⌘I)" when hidden). Buttons 26×22, borderless.

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
    than 1pt per image pixel** (the editor's old display size for small captures). Fit re-fits whenever the
    window resizes, the panel toggles, or a crop/undo changes the image size.
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
- **`ZoomMath`** (`ZoomMath.swift`) — percent ↔ magnification, `fitMagnification`, `clamp`, `steppedPercent`,
  `isFit` (within 0.5%), `anchoredOrigin(anchor, visibleOrigin, from, to)` = `anchor·k − (anchor − origin)`,
  `k = new/old`, `label`. Tests (`zoomMathTests`): percentIsPerScreenPixel (m 0.5 @2× = 100%) ·
  fitCoversBothDimensionsAndNeverUpscalesPastOnePointPerPixel (2000×1000 in 1000² → 0.5; 1000×3000 in
  1000×600 → 0.2; 200×100 → 1) · clampRangeIsFitToEightHundred (@2×: 10 → 4, 0.1 → fit 0.3, fit 1 lets 0.5
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

_(pending — filled when Part 2 lands)_

---

## Part 3 — Redaction strength, Highlighter, Spotlight

_(pending — filled when Part 3 lands)_

---

## Part 4 — Recording setup strip v2 (device menus, level meter, hint line)

**What changed.** The pre-record strip (shown by the Start/Stop Recording shortcut before a target is
picked) used to be one row of buttons with three unlabelled icon toggles (mic / speaker / camera).
It is now a labelled panel: the target buttons plus Format / FPS on top, one **column per source** (icon +
caption + dropdown), a **live microphone level meter**, and a **hint line** at the bottom that explains
whatever the pointer is over. The Settings window's Recording card got the same dropdowns. A **Show
mouse cursor** option was added. On macOS, window recordings also got a system-audio fix (see Platform
notes). Snapshots from the headless probe: `docs/parity-v3/part4-record-strip.png` (strip, 2× pixels)
and `docs/parity-v3/part4-settings-recording.png` (Settings card).

Terms: *dBFS* = decibels relative to digital full scale (0 = loudest possible sample, silence → −∞);
*dshow* = DirectShow, the Windows capture API ffmpeg uses for the port's microphone/loopback inputs;
*WASAPI* = Windows Audio Session API (Core Audio); *Continuity Camera* = an iPhone used wirelessly as a
Mac camera/microphone.

macOS files: `App/Recording/RecordStripController.swift` (strip), `App/Settings/SettingsView.swift`
(`sourceMenus`), `App/Settings/SettingsHelp.swift`, and in `Packages/RecordingKit/Sources/RecordingKit/`:
`RecordingConfig.swift`, `DeviceChoice.swift` (pure), `DeviceCatalog.swift`, `MicLevel.swift` (pure),
`MicCapturer.swift`, `CameraBubbleController.swift`, `ScreenRecorder.swift`.

### Layout (exact, as built — 892 × 182 pt)

```
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│ [🖥 Full Screen] [⬚ Area…] [▭ Window…]                 Format [MP4|GIF]   FPS [30|60]    ⊗ │
│ ────────────────────────────────────────────────────────────────────────────────────────── │
│ 🎙 Microphone           🔊 System audio                   📹 Camera               ↖ Cursor     │
│ [MacBook Air Mic   ⌃⌄]  [All apps except BetterScreenshot⌃⌄] [FaceTime HD Camera ⌃⌄] [Visible ⌃⌄] │
│ ▮▮▮▮▮▯▯▯▯▯▯▯▯▯▯▯                                                                           │
│ ────────────────────────────────────────────────────────────────────────────────────────── │
│ ⓘ Pick what to record, then choose Full Screen, Area or Window.                            │
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

- **Window:** floating, non-activating (never steals focus), on all desktops, draggable by its
  background, no title / close buttons. Background = the dark HUD material (dark translucent blur;
  WPF: the existing `Theme.CardBrush` card with a 12 px corner radius and the 1 px 10 % white border).
  Placement: horizontally centred on the work area of the monitor under the pointer, bottom edge
  **60 pt** above the work area's bottom.
- **Content:** one vertical stack, padding **top 14 · left 16 · bottom 12 · right 16**, **12 pt**
  between rows: top row · separator · sources row · separator · hint row. Every row is exactly
  **860 pt** wide (= the four columns + three 16 pt gaps). Separators are the standard 1 px hairline.
- **Top row** (horizontal, 8 pt spacing), left → right:
  1. Button **"Full Screen"**, icon `display` (SF Symbol) on the left of the label.
  2. Button **"Area…"**, icon `rectangle.dashed`.
  3. Button **"Window…"**, icon `macwindow`.
     Buttons are standard rounded push buttons at the *large* size (≈ 28 pt tall).
  4. Flexible space.
  5. Label **"Format"** (12 pt, secondary text colour) + 6 pt + segmented **[MP4 | GIF]**.
  6. 20 pt gap. Label **"FPS"** + 6 pt + segmented **[30 | 60]**.
  7. 16 pt gap. Close button: borderless icon `xmark.circle.fill` at 16 pt, secondary colour,
     tooltip **"Close without recording"**, accessible name "Cancel".
- **Sources row** (horizontal, **16 pt** gaps, top-aligned) — four columns, each a vertical stack
  (6 pt spacing) of: header (icon 12 pt medium weight, secondary colour · 5 pt · caption 12 pt medium,
  secondary colour) → dropdown (regular size, **fixed width**) → a **12 pt-tall footer line**
  (empty except under Microphone). Column widths (measured so their usual content never truncates —
  "All apps except BetterScreenshot" needs 251 pt, "David’s iPhone Microphone" 213 pt):

  | Column | Icon | Caption | Width | Menu items (top → bottom) |
  |---|---|---|---|---|
  | 1 | `mic` | Microphone | 216 | `Off` · every connected microphone by name |
  | 2 | `speaker.wave.2` | System audio | 252 | `Off` · `All apps` · `All apps except BetterScreenshot` |
  | 3 | `video` | Camera | 216 | `Off` · every connected camera by name · separator · `Bubble Size ▸` submenu `Small` / `Medium` (✓ on the current one) |
  | 4 | `cursorarrow` | Cursor | 128 | `Visible` · `Hidden` |

  Menu-item tooltips (verbatim): Off → "No system sound in the recording."; All apps → "Every sound
  your Mac plays, including BetterScreenshot's own."; All apps except BetterScreenshot → "Every sound
  except BetterScreenshot's own, like its capture sound."; Visible → "The pointer is recorded as it
  moves."; Hidden → "The video shows no mouse pointer."
- **Microphone footer:** either the **level meter** — 16 segments, 2 pt gaps, 6 pt tall, 1.5 pt
  corner radius, inset 2 pt left/right, vertically centred; lit segments are green for the first 70 %
  of the bar, yellow up to 90 %, red above; unlit = white at 14 % — or the link
  **"Allow microphone access…"** (11 pt, link colour, borderless), or nothing (see Behaviour).
- **Hint row:** icon `info.circle` (12 pt, secondary) · 6 pt · one line of 12 pt secondary text that
  fills the rest of the row (tail-truncates, but every string below fits: the longest measured
  532 pt of ~842 pt available).
- **Icons in the port** (`windows/src/BetterScreenshot.App/Resources/Icons.xaml`): reuse `icon-mic`,
  `icon-speaker`, `icon-video`, `icon-cursor`, `icon-close-circle`; **add** a monitor (`display`), a
  dashed rectangle (`rectangle.dashed`), a window (`macwindow`) and an info-circle icon.

### Hint line — texts (verbatim) and rules

| Pointer over / focus on | Hint |
|---|---|
| nothing (idle) | Pick what to record, then choose Full Screen, Area or Window. |
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
| Cursor column | Cursor: choose whether the mouse pointer appears in the video. |
| "Allow microphone access…" link, access never asked | Click to let BetterScreenshot use the microphone. macOS asks once. |
| same link, access denied | Microphone access is off. Click to open System Settings and turn it on for BetterScreenshot. |

(Windows: say "Windows" / "Settings" instead of "macOS" / "System Settings", and "your PC" for
"your Mac".) A **column's hover area is the whole column** (caption + dropdown + footer), so hovering
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
- **Bubble Size** submenu sets Small/Medium without changing the selected camera row.
- **Format = GIF** disables (dims) the Microphone and System audio dropdowns (their values are kept),
  hides the meter, and the recording ignores both (GIFs have no sound — no mic prompt, no mic in use).
- **Mic level meter** runs only while all of these hold: strip visible, Format = MP4, a microphone is
  selected, and microphone permission is **already granted**. Opening the strip must never trigger the
  OS permission prompt. When a mic is selected but access isn't granted, the footer shows
  **"Allow microphone access…"**: if access was never asked, clicking it asks (the OS prompt), then the
  meter starts; if it was denied, clicking opens the OS privacy settings for the microphone
  (macOS `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`; Windows
  `ms-settings:privacy-microphone`). The meter stops when the strip hides or the choice changes.
  It reads the device's average power per audio buffer (~47 updates/s) through `MicLevel`.
- **Long device names** truncate with "…" at the end; hovering the dropdown then shows the full name
  as a tooltip (only when truncated).
- **Show mouse cursor / Cursor = Hidden** records without the pointer.

### Settings window — Recording card (same choices, same stored values)

Rows in order: Format · Frame rate · divider · **Microphone** (dropdown: Off + mics) · **System audio**
(dropdown: the three modes; when Format = GIF both audio dropdowns are dimmed/disabled and a sub-label
reads "GIFs have no sound. Switch Format to MP4 to record audio.") · **Camera** (dropdown: Off +
cameras) · Camera size [Small | Medium] (disabled while Camera = Off) · **Show mouse cursor** (switch,
new) · Highlight mouse clicks · Show keystrokes · Countdown before recording · Show stop button in
recording. The three old switches ("Record system audio", "Record microphone", "Show camera bubble")
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
- **Show mouse cursor** — "Draws the mouse pointer into the recording. Turn off for a clean video
  without the pointer." — "Turn off when recording a slideshow or video you won't be clicking through."

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
| `showsCursor` | `true`/`false` | `true` | **New** ("Show mouse cursor"). |

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
  `SysAudioCheck` / mic / camera switches with ComboBoxes + the "Show mouse cursor" switch.

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
desktops, shadow on, draggable by its background, **tooltips shown even though the app is inactive**.
Height **40**, corner radius **20** (capsule). Background: the app's dark HUD material (the dark
translucent panel look used across the app; macOS vibrant dark `.hudWindow`) + a **black 25 %** wash over it (keeps white text readable on bright backdrops) + a **1 px
border, white 10 %**. The panel is sized to its content (width changes with state, see below).

**Expanded — order, left → right (all sizes in pt):**

| # | Item | Size | Spacing after |
|---|---|---|---|
| — | left inset | 14 | — |
| 1 | status dot (circle) | 10 × 10 | 8 |
| 2 | timer label, monospaced digits 14 pt semibold, left-aligned, fixed width 46 | 46 | 10 |
| 3 | separator (vertical line, white 16 %) | 1 × 18 | 10 |
| 4 | **Mic** toggle (icon + label) | 58 × 28 | 2 |
| 5 | **Sound** toggle (icon + label) | 79 × 28 | 2 |
| 6 | **Camera** toggle (icon + label) | 87 × 28 | 10 |
| 7 | separator | 1 × 18 | 10 |
| 8 | **Switch window…** / **Switch area…** (icon + label) | 137 × 28 | 10 |
| 9 | separator | 1 × 18 | 10 |
| 10 | Restart (icon) | 28 × 28 | 2 |
| 11 | Discard (icon) | 28 × 28 | 2 |
| 12 | Pause / Resume (icon) | 28 × 28 | 2 |
| 13 | Stop (icon, red) | 28 × 28 | 6 |
| 14 | chevron (icon, white 55 %) | 20 × 28 | — |
| — | right inset | 6 | — |

Total **656** wide on macOS. Items 8 + its separator (7) are **hidden for full-screen recordings** (498
wide). All vertically centred.

**Buttons.** Borderless, height **28**, corner radius **7**. Icon buttons: SF Symbol 14 pt semibold,
centred (chevron: 11 pt). Labelled toggles (items 4–6, 8): SF Symbol 13 pt semibold, then the label in
system font **12 pt medium**, icon leading and hugging the text, **8 pt padding each side**; each
labelled button's width is **locked to its widest state** (widest icon × widest label + 16) so toggling
never shifts the pill (macOS widths: 58 / 79 / 87 / 137 — recompute with Segoe UI). Glyph + text colour
white; **disabled → white 30 %**. **Hover** (tracked even while the app is inactive): fill white 12 %;
on a button that already has a fill, the fill blended 15 % toward white.

**Collapsed** (chevron clicked): only dot · timer · Pause · Stop · chevron remain, same metrics and
spacings (timer → Pause 10, Pause → Stop 2, Stop → chevron 6) = **178** wide.

**ASCII mockups (as built).** `[ ]` = a 28 pt control, `▓…▓` = red chip, `░…░` = greyed/disabled.
```
Recording a window (expanded, default):
╭──────────────────────────────────────────────────────────────────────────────────────────────╮
│ ●  1:23   │ [🎙 Mic] [🔊 Sound] [📷̸ Camera] │ [▭ Switch window…] │ [↺] [🗑] [⏸] [■]  › │
╰──────────────────────────────────────────────────────────────────────────────────────────────╯
Mic + Sound muted, camera bubble showing:
│ ●  1:23   │ ▓🎙̸ Mic▓ ▓🔊̸ Sound▓ [📷 Camera] │ [▭ Switch window…] │ [↺] [🗑] [⏸] [■]  › │
Area recording, no mic track, paused (grey dot + grey timer, ▶ instead of ⏸):
│ ○  1:24   │ ░🎙̸ Mic░ [🔊 Sound] [📷̸ Camera] │ [⬚ Switch area…]   │ [↺] [🗑] [▶] [■]  › │
Countdown (engine not started yet): grey dot, "0:00", Switch/Restart/Discard/Pause greyed, Stop live:
│ ○  0:00   │ [🎙 Mic] [🔊 Sound] [📷̸ Camera] │ ░▭ Switch window…░ │ ░↺░ ░🗑░ ░⏸░ [■]  › │
First click on Restart (Discard is the same with "Discard?"):
│ ●  12:07  │ … │ [▭ Switch window…] │ ▓ Restart? ▓ [🗑] [⏸] [■]  › │
Full screen (no Switch group):
│ ●  12:07  │ [🎙 Mic] [🔊 Sound] [📷̸ Camera] │ [↺] [🗑] [⏸] [■]  › │
Collapsed:
╭──────────────────────────╮
│ ●  12:07   [⏸] [■]  ‹ │
╰──────────────────────────╯
```
Snapshots: `part5-pill-expanded.png`, `-muted.png`, `-area-no-mic.png`, `-countdown.png`,
`-confirm-restart.png`, `-collapsed.png`, `-hover.png` (Sound and Discard hovered).

**States of each item (icons are SF Symbol names → port icon keys below):**

| Item | State | Icon | Look | Tooltip (verbatim) |
|---|---|---|---|---|
| Dot | recording | — | systemRed | — |
| Dot | paused / countdown | — | systemGray | — |
| Timer | recording | — | white, "m:ss" (minutes unbounded, e.g. "12:07") | — |
| Timer | paused / countdown | — | secondary grey; countdown shows "0:00" | — |
| Mic | on | `mic.fill` | white | "Mute microphone — the video keeps a silent gap, stays in sync" |
| Mic | muted | `mic.slash.fill` | **red chip**: fill systemRed 85 %, white icon + text | "Unmute microphone" |
| Mic | not recorded | `mic.slash.fill` | disabled (30 %) | "Mic wasn't on when this recording started — there's no mic track to mute" |
| Sound | on | `speaker.wave.2.fill` | white | "Mute system audio — the video keeps a silent gap, stays in sync" |
| Sound | muted | `speaker.slash.fill` | red chip | "Unmute system audio" |
| Sound | not recorded | `speaker.slash.fill` | disabled | "System audio wasn't on when this recording started — there's no sound track to mute" |
| Camera | bubble showing | `video.fill` | white | "Hide camera bubble" |
| Camera | bubble hidden / never shown | `video.slash.fill` | white, **no chip** (camera-off is the normal state, not a warning) | "Show camera bubble" |
| Camera | no camera | `video.slash.fill` | disabled | "No camera found" |
| Camera | permission denied | `video.slash.fill` | disabled | "Camera access is off — allow BetterScreenshot in System Settings › Privacy & Security › Camera" (Windows: "…in Settings › Privacy & security › Camera") |
| Switch | window recording | `macwindow`, "Switch window…" | white | "Record a different window — it's scaled to fit this video's frame" |
| Switch | area recording | `rectangle.dashed`, "Switch area…" | white | "Record a different area — it's scaled to fit this video's frame" |
| Switch | countdown | as above | disabled | "Available once recording starts" |
| Restart | normal | `arrow.counterclockwise` | white | "Restart — delete what's recorded so far and start over" |
| Restart | confirming | no icon, text "Restart?" | **red capsule**: fill systemRed, white 12 pt semibold text, width = text + 16 (≈ 70) | "Click again to restart — what's recorded so far is deleted" |
| Discard | normal | `trash` | white | "Discard — stop and delete this recording" |
| Discard | confirming | text "Discard?" | red capsule (≈ 72 wide) | "Click again to delete this recording" |
| Restart/Discard | countdown | icon | disabled | "Available once recording starts" |
| Pause | recording / paused | `pause.fill` / `play.fill` | white; disabled during countdown | "Pause recording" / "Resume recording" |
| Stop | recording / countdown | `stop.fill` | systemRed glyph | "Stop recording" / "Cancel recording" |
| Chevron | expanded / collapsed | `chevron.right` / `chevron.left` | white 55 % | "Collapse to timer, Pause and Stop" / "Show all controls" |

**Resizing & position.** Whenever the width changes (expand/collapse, confirm chip, Switch shown/hidden)
the pill keeps its **bottom-right corner fixed** (the chevron stays under the pointer), then is clamped
8 pt inside the screen's work area. First show with no saved position: bottom-centre of the recording's
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
  Switch, Pause, Stop or the chevron is used or the recording stops (the Mic/Sound/Camera toggles don't
  cancel it; clicking the other of Restart/Discard moves the confirm to that one). Deliberately
  **not a dialog** — a modal would steal focus from the app being recorded.
- **Pause / Stop** as before (Stop during the countdown cancels the recording).
- **Chevron** toggles expanded/collapsed; the state persists.
- Tooltips: every control has one (table above).

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
- Pure logic: `windows/src/BetterScreenshot.Recording/LetterboxFit.cs` (+ `SilenceFill.cs` only if audio
  is captured in-process, option C below); tests in `windows/tests/BetterScreenshot.Tests/RecordingTests.cs`
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
  `SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)` (Windows 10 2004+) unless "Show stop button in
  recording" is on — verify with a probe recording that it hides the window from `gdigrab`; if not, fall
  back to `ddagrab` (Desktop Duplication honours it). It's per-window, so it survives a switch.
- **Focus.** The pill must never activate (`WS_EX_NOACTIVATE`, `ShowActivated=false`, handle
  `WM_MOUSEACTIVATE` → `MA_NOACTIVATE`). Test that its tooltips and hover highlights still appear while
  another app is focused (macOS needed an explicit opt-in, `allowsToolTipsWhenApplicationIsInactive`,
  and hover tracking that is active even when the app isn't).
- **Camera bubble show/hide:** keep the `CameraBubbleWindow` instance and `Hide()`/`Show()` it so a
  dragged position survives; stop the camera while hidden.

---

## Part 6 — Video editor v2 (cut, per-segment speed/mute, GIF export)

**What it is.** The recording trim window (opened by a recording's Quick Access card ✂ **Trim** button,
or History's **Trim…**; MP4 only) is now a small video editor. It replaces AVKit's single-range "yellow
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
window size, one segment).

```
┌─ Edit Video — Recording 2026-09-24 at 12.00.00.mp4 ──────────────────────────────────────────┐
│                                                                                              │
│                 video preview — black letterbox, aspect-fit; click = play / pause            │
│                                                                                              │
│ ╭──────────────────────────────────────────────────────────────────────────────────────────╮ │
│ │ ▶  0:05.0 / 0:10.5   [✂ Split] [🗑 Delete] │ [↶] [↷]                  🔍−  ──●──────  🔍+ │ │
│ │                                          ●  (playhead knob)                              │ │
│ │ ╭────────────────────────╮░░░░░░░✂░░░░░░░▐▌[2×][🔇] filmstrip — selected (yellow)   ▐▌ │ │
│ │ │ filmstrip (segment 1)  │░ cut, dimmed ░│▐▌                                        ▐▌ │ │
│ │ ╰────────────────────────╯░░░░░░░░░░░░░░░▐▌━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━▐▌ │ │
│ │ Segment 2 of 2  0:09.0 – 0:20.0    Speed [ 1× | 1.5× | 2× | 4× ]   ☑ Mute segment       │ │
│ │ ⓘ Sped-up segments are muted so the audio doesn't sound rushed — untick Mute segment …   │ │
│ ╰──────────────────────────────────────────────────────────────────────────────────────────╯ │
├──────────────────────────────────────────────────────────────────────────────────────────────┤
│ 0:10.5 kept of 0:20.0   ☐ Mute audio                 [Cancel] [Save as Copy │▾] [Replace Original] │
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
   | Play / Pause | borderless icon, `play.fill` ↔ `pause.fill`, 15 pt semibold, white 85%, 29 pt wide | `Play (Space)` / `Pause (Space)` | Space | loaded, not exporting |
   | Time | `0:05.0 / 0:10.5` = playhead / edit length (output time), 12 pt monospaced-digit medium, white 85%, min width 116 | `Playhead / length of the edit` | — | — |
   | (10 pt gap) | | | | |
   | **Split** | rounded push button, `scissors` 12 pt + "Split" | `Split the segment at the playhead (S or ⌘B)` | S, ⌘B | the playhead is ≥ 0.1 s inside a segment |
   | **Delete** | rounded push button, `trash` + "Delete" | `Delete the selected (yellow) segment (⌫)` | ⌫ / Delete | more than one segment |
   | divider | 1 × 18 pt, white 15% | | | |
   | Undo | rounded push button, icon only `arrow.uturn.backward` | `Undo (⌘Z)` | ⌘Z | something to undo |
   | Redo | rounded push button, icon only `arrow.uturn.forward` | `Redo (⇧⌘Z)` | ⇧⌘Z | something to redo |
   | (flexible space) | | | | |
   | Zoom out | borderless `minus.magnifyingglass` 12 pt, 26 pt wide | `Zoom out the timeline` | — | zoom > 1 (÷ 1.5 per click) |
   | Zoom slider | small slider, 110 pt wide, 1…12 (1 = fit to width), continuous | `Timeline zoom` | — | loaded |
   | Zoom in | borderless `plus.magnifyingglass` 12 pt | `Zoom in the timeline` | — | zoom < 12 (× 1.5 per click) |
2. **Timeline** — 66 pt tall, full card width, scrolls horizontally when zoomed (overlay scroller, no
   bounce). Tooltip: `Click to move the playhead and pick a segment · drag a yellow edge to trim · right-click for speed and mute`.
   Drawing spec below.
3. **Selected-segment row** (items 8 pt apart): `Segment 2 of 3` (11 pt semibold, white 90%) ·
   `0:09.0 – 0:20.0` (the segment's **source** range; 11 pt monospaced-digit, white 50%; tooltip
   `Where this segment comes from in the original recording`) · 14 pt gap · `Speed` (11 pt, white 60%) ·
   small segmented control `1×` `1.5×` `2×` `4×` (each 40 pt wide; tooltip
   `Play this segment faster (sped-up segments start muted)`) · 10 pt gap · small checkbox
   `Mute segment` (11 pt; tooltip `Silence this segment's audio (the rest keeps its sound)`; shown ticked
   and disabled while whole-file **Mute audio** is on).
4. **Hint line**: `info.circle` 11 pt (white 45%) + one sentence, 11 pt white 55%, truncated at the end if
   too long. Text (first match wins, verbatim):
   1. exporting → `Exporting — the original stays untouched until it's done.`
   2. Mute audio ticked → `Mute audio is on: the saved video will have no sound at all.`
   3. selected segment sped up and muted → `Sped-up segments are muted so the audio doesn't sound rushed — untick Mute segment to keep it.`
   4. selected segment sped up, not muted → `Sped-up audio keeps its pitch but plays faster.`
   5. only one segment → `Move the playhead, then press S (or ⌘B) to split · drag the yellow edges to trim · I / O set in / out`
   6. otherwise → `Click a segment to select it · ⌫ deletes it · right-click for speed and mute · Space plays the edit`

**Action bar** (bottom, 52 pt tall, standard header material, 1 px separator on top; row inset 16 pt,
items 10 pt apart): kept label (12 pt monospaced-digit, secondary colour; tooltip
`Length of the saved video / length of the recording`) · 4 pt gap · checkbox `Mute audio` (tooltip
`Save without any sound`) · 8 pt gap · progress bar (140 pt, hidden except while exporting; the kept
label hides while it shows) + progress text · flexible space · **Cancel** (tooltip `Close without saving`;
reads **Done** with tooltip `Close the editor` after Replace Original) · **Save as Copy ▾** — a split
button: the main part saves a copy, the ▾ opens a menu with one item `Export as GIF` (tooltip on the
button `Save the edit as a new file next to the original — the ▾ menu exports a GIF`; on the item
`Save the edit as an animated GIF next to the original (10 fps, up to 960 px wide)`) · **Replace
Original** (accent-tinted, deliberately **no** Return shortcut; tooltip
`Overwrite the original recording with the edit`).

Kept label texts (verbatim; times are `m:ss.t`, rounded to tenths — `TrimRange.timestamp`):
`Loading…` · `This recording can't be opened for editing.` · `Whole recording · 0:45.0` (nothing edited)
· `0:31.2 kept of 0:45.0` · and one-off notes that stay until the next edit: `Edited ✓ original replaced · 0:31.2`,
`GIF saved ✓ <gif file name>`, `Couldn't export the edit — original untouched`,
`Couldn't export the GIF — nothing was changed`. Progress text: `Exporting… 42%` (re-encode or GIF,
determinate bar) or `Saving…` (passthrough, indeterminate bar).

**Icons** (SF Symbol → port icon key in `windows/src/BetterScreenshot.App/Resources/Icons.xaml`):
`play.fill` → `icon-play`; `trash` → `icon-trash`; `arrow.uturn.backward` / `.forward` → `icon-undo` /
`icon-redo`. **New glyphs to author:** `pause.fill` → `icon-pause`, `scissors` → `icon-scissors`,
`minus.magnifyingglass` / `plus.magnifyingglass` → `icon-zoom-out` / `icon-zoom-in`, `info.circle` →
`icon-info`, `speaker.slash.fill` → `icon-speaker-off`.

### Timeline — drawing spec

- 12 pt inset at both ends. Scale (pt per timeline second) = (view width − 24) ÷ timeline length; view
  width = visible width × zoom. Track: y 10 … height − 6 (50 pt of a 66 pt view); behind it a rounded
  rect (radius 8, black 35%) 2 pt in from the sides and 3 pt beyond the track top/bottom.
- **Kept segment**: its rect inset 1 pt left/right (so adjacent segments show a 2 pt gap), radius 6,
  filled with the filmstrip, 1 px border white 22%.
- **Filmstrip**: tiles `track height × video aspect` wide (clamped 24…160 pt), starting at each block's
  left edge; each tile aspect-fills the thumbnail nearest to the **source** time at the tile's centre
  (so a 2× segment shows twice the footage per tile). Thumbnails: `clamp(2 × duration, 12, 240)` frames at
  `(k + 0.5) × duration / count`, max 320 × 200 px, loaded in the background; until then tiles are grey 22%.
- **Cut** (removed range): its rect inset 1 pt left/right and 4 pt top/bottom, radius 4; filmstrip, then
  black 66%, then 45° hatch lines (white 9%, 1.5 pt, every 7 pt), and a centred `scissors` glyph (11 pt,
  white 45%) if the block is ≥ 22 pt wide. Cuts before the first and after the last segment are drawn too.
- **Badges** (top-left of a kept segment, 5 pt from its left, 4 pt from the top): 16 pt-tall fully rounded
  pills, black 70%, 5 pt side padding, 4 pt apart: the speed (`1.5×`, `2×`, `4×`; 10 pt bold white) when
  not 1×, then `speaker.slash.fill` (9 pt bold white) when muted. A badge that doesn't fit is skipped.
- **Selection** (exactly one segment is always selected): system-yellow 2.5 pt border (radius 6) plus two
  solid yellow handles, 10 pt wide (or a third of the segment if narrower), radius 4, each with a centred
  2 × 14 pt grip (black 55%).
- **Playhead**: 2 pt white line from y 3 to the bottom with a 10 pt white circle knob at the top, soft
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
  one checked) · `Mute Segment` (checked when muted; disabled while Mute audio is on) · separator ·
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
**Mute audio** box mutes the preview immediately and makes the export drop all audio.

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
  open and reloads the new file: a fresh single-segment cut list (undo history cleared), Mute audio
  unticked, Cancel reads **Done**, note `Edited ✓ original replaced · <new length>`; a HUD says
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

### Where it goes in the port

- Pure: `windows/src/BetterScreenshot.Recording/CutList.cs` (+ `CutHistory`), `TrimRange.cs`,
  `TrimmedFileName.cs`, and `FfmpegArgs.BuildCutExport(...)` / `BuildPassthroughTrim(...)` next to
  `BuildGifConversion` in `windows/src/BetterScreenshot.Recording/FfmpegArgs.cs` (unit-test the strings).
- UI: new `windows/src/BetterScreenshot.App/Recording/VideoEditorWindow.xaml(.cs)` + a custom-drawn
  `CutTimeline` `FrameworkElement` (OnRender) in the same folder; dark theme from `Resources/Theme.xaml`,
  the card from `Controls/DarkSection.cs`-style chrome.
- Entry points: `QuickAccessActions.OnTrim` (`Overlays/QuickAccessTypes.cs`) + a Trim button on MP4
  recording cards (`Overlays/QuickAccessWindow.xaml`), wired in `Capture/CaptureCoordinator.ShowRecordingCard`
  with the Part 0 `restoreCard`; a `Trim…` command in `History/HistoryWindow.xaml(.cs)`. Copy / GIF
  results go through `CaptureCoordinator.OnRecordingFinished(path, thumbnail)`.
- Running ffmpeg: `windows/src/BetterScreenshot.Platform/FfmpegRunner.RunAsync` (add a progress callback
  that parses `-progress pipe:1` output); GIF via `Recording/GifExporter.ConvertAsync` (it deletes its
  source MP4 on success — fine for the temp render).

### Platform notes (ffmpeg instead of AVFoundation)

- **Passthrough trim** (plain start/end, 1×): `ffmpeg -y -ss <start> -to <end> -i in.mp4 -c copy
  -avoid_negative_ts make_zero -movflags +faststart out.mp4` (add `-an` for Mute audio). `-ss` before `-i`
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
  -crf 18`. Whole-file Mute audio: no `atrim` chains, `concat=n=N:v=1:a=0`, `-an`. Two audio tracks
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
