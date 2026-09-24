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

_(pending — filled when Part 1 lands)_

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

_(pending — filled when Part 5 lands)_

---

## Part 6 — Video editor v2 (cut, per-segment speed/mute, GIF export)

_(pending — filled when Part 6 lands)_
