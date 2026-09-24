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
│ [System                 ⌃⌄]  │
│ [24 pt ⌃⌄]  [ B | I | U | S ] │ ← size 84 pt + four 30 pt toggles
│ [  ≡  |  ≡  |  ≡  ]          │
│ ──────────────────────────── │
│ BACKGROUND                   │
│ [  None  | Solid |  Auto  ]  │ ← full width, equal segments
│ ● ● ● ● ● ● ● ●              │ ← Solid only: box palette (Black = 80 %)
│ RECENT ● ● ●                 │ ← Solid only, hidden when empty
│ [▬▬] [⌖ Pick from Screen]    │ ← Solid only: box colour well + eyedropper
│ Dark or light — whichever …  │ ← Auto only (note)
│ Padding  ────●────── 6 px    │ ← Solid and Auto
│ Corners  ──●──────── 4 px    │ ← Solid and Auto
│ ──────────────────────────── │
│ EFFECTS                      │
│ ☑ Outline              [▬▬]  │ ← checkbox left, outline colour well right
│     Width ──●─────── 3 px    │ ← only while Outline is on; indented 20 pt
│ ☐ Shadow                     │
│ ──────────────────────────── │
│ OPACITY  (unchanged)         │
└──────────────────────────────┘
```

| Section (caption) | Rows (exact) |
|---|---|
| **Styles** | Two rows of three `TextPresetChip`s, `fillEqually`, 8 pt apart; each 28 pt tall. Chip drawing: rounded rect (radius 6) inset 1.5 pt; fill = the preset's box colour, or white 6 % for presets without a box (Title, Subtle); border 1 px white 16 %; **active** (the current style already has that look, `TextStylePreset.isApplied`) = 2 px accent-colour border; hover = white 10 % overlay. Label = the preset's name, centred, in the preset's font family and weight at 12 pt (Title: 15 pt), in the preset's text colour (Title keeps the user's colour, so its chip label is white 92 %). Tooltips: "Label — bold white text on a black box", "Callout — bold white text on a red box", "Note — black text on a yellow box", "Code — light monospaced text on a dark box", "Title — 48 pt bold, no box (keeps the colour)", "Subtle — 18 pt regular grey, no box". |
| **Font** | As §1.1, except row ② is now size pop-up (84 pt) · a **four**-segment toggle group (select-any, 30 pt per segment): SF `bold`, `italic`, `underline`, `strikethrough`; tooltips "Bold", "Italic", "Underline", "Strikethrough". |
| **Background** | ① Segmented **None / Solid / Auto**, full width, equal segments; tooltips "No box behind the text", "A box in the colour you pick below", "A dark or light box, whichever stands out against the text colour". ② *(Solid only)* the Colour section's three rows, but editing the **box** colour: 8 swatches with the same colours and names except the last is **black at 80 % alpha**, tooltip "Black (80%)"; the shared RECENT row; a second colour well 44×24 (tooltip "Custom box colour — opens the colour picker") + "Pick from Screen" (same tooltip as §1.1; the picked colour becomes the box colour — handy for covering old text with the page's own colour). ③ *(Auto only)* note, 12 pt white 62 %: "Dark or light — whichever stands out against the text colour." ④ *(Solid and Auto)* slider row "Padding" (label 56 pt wide), 0…40 whole px, value "6 px", tooltip "Space between the text and the edge of the box". ⑤ *(Solid and Auto)* slider row "Corners" (label 56 pt), 0…40 whole px, value "4 px", tooltip "How rounded the box's corners are". Hidden rows take no space. |
| **Effects** | ① Checkbox **"Outline"** (12 pt, white 88 %; tooltip "An edge around every letter — keeps text readable on busy screenshots") · flexible space · outline colour well 44×24 (tooltip "Outline colour — picking one turns the outline on"). ② *(only while Outline is on)* slider row indented 20 pt: "Width" (44 pt label), 1…20 whole px, value "3 px", tooltip "Outline thickness in image pixels". ③ Checkbox **"Shadow"** (tooltip "A soft drop shadow under the text (and its box)"). |

**Canvas handles.** A single selected text shows **six** handles: the four corners (**scale**) and middle-left /
middle-right (**box width**) — top-/bottom-middle are not shown. Handles are the usual 8×8 view-pt white squares with
a 1 px blue border (screen-sized at any zoom), hit area +2 pt; where handles overlap on a tiny text, corners win.
All handles and the dashed selection outline sit on the **box** (text + padding) when the text has a background.

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

_(pending — filled when Part 3 lands)_

---

## Part 4 — Recording setup strip v2 (device menus, level meter, hint line)

_(pending — filled when Part 4 lands)_

---

## Part 5 — Live recording pill v2 (mute, switch window, restart, discard)

_(pending — filled when Part 5 lands)_

---

## Part 6 — Video editor v2 (cut, per-segment speed/mute, GIF export)

_(pending — filled when Part 6 lands)_
