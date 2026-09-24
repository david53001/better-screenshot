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

_(pending — filled when Part 0 lands)_

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
Colour · Stroke · **Stroke (highlighter)** · Font · Background · Redaction · **Strength** · **Shape** ·
**Dim outside** · Opacity · Arrange.

```
 Blur / Pixelate               Black-out                     Highlighter                   Spotlight
┌──────────────────────────┐  ┌──────────────────────────┐  ┌──────────────────────────┐  ┌──────────────────────────┐
│ Blur                     │  │ Black-out                │  │ Highlighter              │  │ Spotlight                │
│ REDACTION                │  │ REDACTION                │  │ COLOUR                   │  │ SHAPE                    │
│ [Blur|Pixelate|Black-out]│  │ [Blur|Pixelate|Black-out]│  │ ● ● (●) ● ● ● ● ●        │  │ [▭ Rectangle|◯ Ellipse]  │
│ Softens what's under-    │  │ Covers it with solid     │  │ [▬] [⌖ Pick from Screen] │  │ ──────────────────────── │
│ neath. Raise the strength│  │ black — the safest       │  │ ──────────────────────── │  │ DIM OUTSIDE              │
│ until it can't be read.  │  │ choice, nothing can be   │  │ STROKE                   │  │ ──────●────────── 60%    │
│ ──────────────────────── │  │ recovered.               │  │ Width ────●──── 20 px    │  └──────────────────────────┘
│ STRENGTH                 │  └──────────────────────────┘  │ [Thin|Medium|Thick]      │
│ ───●──────────── 12 px   │                                │ ──────────────────────── │
└──────────────────────────┘                                │ OPACITY                  │
                                                            │ ────●──────────── 40%    │
                                                            └──────────────────────────┘
```
Under Select, a selected object shows the same sections plus **Arrange** (e.g. one blur → Redaction · Strength ·
Arrange; one spotlight → Shape · Dim outside · Arrange).

| Section (caption) | Rows (exact) |
|---|---|
| **Redaction** (Blur, Pixelate, Black-out) | ① Segmented **Blur / Pixelate / Black-out**, small, full width, equal segments; tooltips "Blur (B)", "Pixelate (P)", "Black-out (X)". Selected segment = the active redaction tool, or (under Select) the selected redaction's mode. ② A note (12pt, white 62%, wraps at 232pt) that follows the mode — Blur: "Softens what's underneath. Raise the strength until it can't be read." · Pixelate: "Turns what's underneath into blocks. Bigger blocks hide more." · Black-out: "Covers it with solid black — the safest choice, nothing can be recovered." |
| **Strength** (Blur, Pixelate — not Black-out) | Slider with **no label** (like Opacity) · value "12 px" (11.5pt monospaced digits, white 55%, 40pt, right-aligned). Blur: 2…40, tooltip "Blur radius, in image pixels". Pixelate: 4…48, tooltip "Size of each block, in image pixels". Whole pixels. Blur and Pixelate share this section, so switching between them only changes the range, value and tooltip. |
| **Stroke** (Highlighter — its own section, same look as Part 1's Stroke) | ① "Width" label (44pt) · slider **4…48** · value "20 px". ② Segmented **Thin / Medium / Thick** = **12 / 20 / 32 px** (tooltips "12 px", "20 px", "32 px"); no segment highlighted for other widths. |
| **Colour**, **Opacity** (Highlighter) | Exactly Part 1's sections; they show and edit the highlighter's own pen (default Yellow ring, 40%). |
| **Shape** (Spotlight) | Segmented **Rectangle / Ellipse**, small, full width, equal segments, each with an icon before the label (SF `rectangle`, `circle`; port: rectangle / circle outline icons); tooltips "Rectangle", "Ellipse — or hold ⌥ while dragging". |
| **Dim outside** (Spotlight) | Slider with no label, **10…90 %**, value "60%", tooltip "How dark everything outside the spotlights gets". |

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

_(pending — filled when Part 4 lands)_

---

## Part 5 — Live recording pill v2 (mute, switch window, restart, discard)

_(pending — filled when Part 5 lands)_

---

## Part 6 — Video editor v2 (cut, per-segment speed/mute, GIF export)

_(pending — filled when Part 6 lands)_
