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

_(pending — filled when Part 4 lands)_

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

_(pending — filled when Part 6 lands)_
