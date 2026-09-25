# BetterScreenshot v3 — Editor & Recording Overhaul (design)

Date: 2026-09-24 · Status: **approved by the owner 2026-09-24** — build straight from this spec (owner: no separate
implementation plans); progress in `docs/PROGRESS-v3.md`. Owner decisions (2026-09-24): inspector = **right-side panel**; cuts = **frame-accurate**;
order = **editor first**; extras added = **Highlighter + Spotlight, canvas zoom (pinch / ⌘-scroll) +
tool shortcuts, per-segment speed/mute, export edit as GIF**; plus a **Windows-port handoff document**
(§12) is a required deliverable of every part.
**Part 7 (interactive guided tours + ⓘ help — §14) was added and approved 2026-09-25, deferred to later;
Parts 0–6 are built.**
Builds on: `main` at `1c3d4fd` (text fonts/boxes, recording pill, trim window — see
`docs/PROGRESS-2026-09-24-text-controls-trim.md`)

> **For a fresh session:** read `CLAUDE.md` first, then this file. This is an umbrella design split
> into **Parts 0–6** (§3–§9); each part is built, tested and committed on its own, directly from
> this spec (the owner decided against separate plan documents). Build in the
> order in §11. Where this doc says **probe**,
> run that experiment as the plan's first task — the design of that piece depends on the answer.
> Items marked **Decision** are the owner's call; the recommended default is stated so work can
> proceed if the owner agrees.

## 1. Why — what the owner asked for (2026-09-24, verbatim intent)

After using the build from `1c3d4fd`, the owner asked for:

1. **Text:** drag a text object's *corners* to make the whole text bigger (scale the font); a real
   **background behind text** (e.g. black box behind white text) with a **choosable colour**; more
   text options overall.
2. **Editor UI:** it has too few options and **looks cramped** (screenshot: the arrow inspector pill
   — label, 8 swatches, a colour well and S/M/L squeezed into one 44pt row). It must be
   **intuitive and nicely formatted** — the owner called this an important feature.
3. **Blur / pixelate:** choose **how strong** it is (blur radius / pixel size), in the screenshot
   editor.
4. **Recording setup strip:** the mic / speaker / camera buttons are **unlabelled icons** and
   confusing. Wants **dropdowns** (e.g. pick which microphone) and a **line of explanatory text**
   under the controls, nicely formatted.
5. **Recording pill (while recording):** must be **expanded** with live controls — **mute system
   audio, mute microphone, change the recorded window**, etc.
6. **Trim window bug:** pressing **Cancel** loses the recording's Quick Access card ("it just deletes
   it") — cancelling should **put the card back in the corner**.
7. **Cut:** a real **cut** feature — split the clip in the middle and remove parts, "a bit more like
   editing software".
8. **Brainstorm extra features** in the same spirit.
9. **Document everything for the Windows port** — the C#/WPF port on the `windows-port` branch will
   get these changes "identical", and it has none of them (nor the 2026-09-24 text/pill/trim work),
   so a document must describe exactly the layout, items and behaviour (§12).

**Terms used below.** *Quick Access card* = the thumbnail card that appears in a screen corner after
a capture/recording (OverlayKit). *Inspector* = the editor panel holding the active tool's options.
*HUD style* = the dark translucent panel look used across the app. *SCK* = ScreenCaptureKit, macOS's
screen/audio capture API (`SCStream`, `SCContentFilter`). *Passthrough export* = copying the
compressed video as-is (fast, lossless) instead of re-encoding it; it can only cut cleanly at
*keyframes* (full frames the encoder stores every ~1 s; frames in between depend on them).
*PCM* = raw uncompressed audio samples.

**Hard constraints that still apply** (from `CLAUDE.md`): no cloud / network, macOS 14+ target,
menu-bar agent, updates must never cost permissions/settings/data (new settings need defaults that
keep today's behaviour; persisted `AnnotationStyle` / `RecordingConfig` must keep decoding),
background/wallpaper styling stays dropped, bundle id stays `com.betterscreenshot.mac`.

**Success looks like:** every control is labelled or explained on hover; the editor inspector never
truncates or squeezes at the minimum window size; all new options persist like colour does; each
recording/cut path is covered by an automated test on a generated MP4 (the `TrimExporterTests`
fixture pattern) or a headless probe (the pattern used on 2026-09-24).

## 2. Design principles for all new UI

- **No unexplained icons.** Every icon button gets a visible caption *or* a tooltip plus the shared
  hint line (§4.3). Where there's room, use icon + short label.
- **Group, then label.** Controls sit in titled groups ("Colour", "Font", "Background"); a group
  that would overflow moves into a popover rather than shrinking.
- **One visual language.** Reuse the existing dark HUD look (`NSVisualEffectView` `.hudWindow`,
  vibrant dark, 1px 10% white border, 12pt radius) and an 8pt spacing grid; controls 24–28pt tall.
- **Live preview.** Every style control updates the canvas / video immediately; nothing needs an
  "Apply" button. Every change is one undo step.
- **Sticky defaults.** Anything the user sets becomes the default for next time (existing
  `SettingsStore.editorStyle` / `RecordingConfig` pattern).

## 3. Part 0 — Trim window: Cancel restores the card (bug fix)

**Cause (verified in code):** `QuickAccessOverlayController.trimAction()` dismisses the card with
`.actionTaken` before opening the trim window; closing the trim window never re-presents it.

**Design:** `RecordingCoordinator.presentTrim(url:restoreCard:)` gains an optional `restoreCard`
closure (the card path passes one that calls `presentCard(for:image:historyID:)` with a **fresh
thumbnail** from `thumbnail(for:)`; the History path passes nil). When the trim window closes:
- **Cancel / close box, nothing saved** → the original's card comes back in its corner.
- **Replace Original, then close** → the card comes back showing the *trimmed* file's first frame.
- **Save as Copy** → the copy's card appears (as today) **and** the original's card comes back, so
  nothing the user had disappears.

Test: extend the trim probe — cancel → `restoreCard` called once; save-as-copy → both callbacks.
Tiny; build first.

## 4. Part 1 — Editor inspector redesign (foundation for Parts 2–3)

### 4.1 Problem
One 44pt pill holds everything; Part 2/3 options can't fit. `EditorWindowController.swift` is
already ~650 lines mixing window layout, toolbar and inspector.

### 4.2 Approaches
- **A. Right-side inspector panel (recommended).** A 264pt-wide dark panel on the right of the
  canvas with titled, stacked sections that change with the tool/selection (like Keynote / Figma).
  Room for labels and every Part 2/3 option; scales as features grow. Collapsible (⌥⌘I or a toolbar
  button) for small screenshots; the canvas re-fits. Cost: less canvas width (the window's minimum
  width grows from 600 to ~864pt — 600 canvas + 264 panel — while the panel is shown).
- **B. Roomier top bar + popovers.** Keep the horizontal pill, add spacing and captions, and move
  groups (font, background, effects) into popover buttons. Keeps canvas width, but options hide
  behind clicks and the bar still crowds at 600pt.
- **C. Floating mini-toolbar beside the selected object.** Very direct, but covers the image,
  jumps around, and has no room for many options.

**Decided (owner, 2026-09-24): A — right-side panel.**

### 4.3 Layout (approach A)
```
┌──────────────────────────────────────────────────────────────┬──────────────────────┐
│   [↖] │ [↗][／][▭][■][◯] │ [Aa][①] │ [💧][▦] │ [⌗]   ⟲ ⟳     │ TEXT                 │
│                                                              │ ─ Colour ──────────  │
│                                                              │ ● ● ● ● ● ● ● ●  [▣] │
│                                                              │ Recent: ● ● ● ●      │
│                  (canvas, centred, fit to width)             │ ─ Font ────────────  │
│                                                              │ [System        ▾]    │
│                                                              │ [24 pt ▾]  [B][I][U] │
│                                                              │ [⇤][≡][⇥]  Opacity ▬ │
│                                                              │ ─ Background ──────  │
│                                                              │ [None|Solid|Auto]    │
│                                                              │ [▣ colour] Pad ▬ R ▬ │
│                                                              │ ─ Effects ─────────  │
│                                                              │ ☐ Outline [▣] ▬      │
│                                                              │ ☐ Shadow             │
├──────────────────────────────────────────────────────────────┴──────────────────────┤
│ Drag to draw a text box · double-click text to edit · ⇧↩ new line          ← hint line │
│ 1200 × 700 px                                   Done   Stack   Save   [Copy]         │
└─────────────────────────────────────────────────────────────────────────────────────┘
```
- Toolbar stays on top (icons; tooltips name the tool + shortcut, e.g. "Arrow (A)"). Part 3 adds
  Highlighter and Spotlight to it (next to Text/Counter and Blur/Pixelate respectively).
- **Hint line** above the action bar: one sentence for the active tool / selection (the "text at
  the bottom that explains things" the owner asked for, applied to the editor too).
- Section content per tool: Arrow/Line/Shapes → Colour, Stroke (width slider + S/M/L presets),
  Opacity. Text → Colour, Font, Background, Effects (§5). Blur/Pixelate → Strength (§6).
  Select with one object → that object's sections; multiple → shared sections + Arrange.

### 4.4 Canvas zoom + tool shortcuts (owner-chosen extras)
- **Zoom:** trackpad **pinch** (`NSView.magnify(with:)`), **⌘ + scroll wheel** (mouse), **⌘+ / ⌘−**,
  **⌘0 = fit to window** (today's only mode), **⌘1 = 100%** (1 image px per screen pixel). Zoom
  anchors on the pointer (pinch/scroll) or the view centre (keys). Range: fit … 800%. A small
  "Fit · 150% ▾" control sits at the right end of the action bar. Plain scrolling pans when zoomed.
  Implementation: the canvas frame grows inside the existing `NSScrollView` (the canvas's
  `scale` = image px per view pt already drives all coordinate mapping, so drawing/hit-testing keep
  working); `fitCanvas()` only runs in "Fit" mode.
- **Tool shortcuts** (single keys, active only when no text is being edited; shown in tooltips as
  "Arrow (A)"): V select · A arrow · L line · R rectangle · F filled rectangle · O ellipse · T text ·
  N counter · H highlighter · S spotlight · B blur · P pixelate · C crop. Esc = back to Select.

### 4.5 Components
- New `EditorInspectorView` (EditorKit): builds sections from a small `InspectorModel` (pure: which
  sections/controls show for tool + selection → unit-testable), emits `AnnotationStyle` changes.
- New `InspectorSection` / small control wrappers in `EditorChrome.swift` (labelled slider row,
  swatch row + recent colours, segmented row).
- `EditorWindowController` keeps window/toolbar/action bar and wires the inspector — shrinks, not
  grows.

## 5. Part 2 — Text v2

### 5.1 Corner handles scale the text
- A selected text shows **4 corner handles** (scale) plus the existing **2 side handles** (box
  width). Dragging a corner scales `fontSize` proportionally to the diagonal change (and the box
  `wrapWidth` by the same factor, so line breaks stay put). Clamped to 8…400 pt. ⇧ not needed
  (always proportional). The size menu in the inspector updates live.
- Pure helper `TextScale.scaled(fontSize:wrapWidth:original:proposed:handle:)` → unit-tested.

### 5.2 Background behind text
`AnnotationStyle` gains (all optional-decoded, defaults = today's look):
- `textBackgroundMode`: `none | solid | auto` (replaces the Bool `textBackground`; legacy
  `true` decodes to `auto`, `false` to `none`).
- `textBackgroundColor: RGBAColor` (default black 80%), `textBackgroundPadding` (default 6),
  `textBackgroundCornerRadius` (default 4).
Inspector: segmented None/Solid/Auto + colour well + Padding/Radius sliders. "Auto" = today's
auto-contrast chip (`TextChip`).

### 5.3 More text options (recommended set — owner can trim)
- **Underline**, **strikethrough** (B / I / U / S row).
- **Outline** (stroke colour + width) — legible on busy screenshots.
- **Shadow** (on/off; fixed soft shadow).
- **Opacity** slider.
- **Style presets** (CleanShot has 7): one-click chips — *Label* (bold on solid black), *Callout*
  (white on red), *Note* (black on yellow), *Code* (Mono on dark), *Title* (48pt bold),
  *Subtle* (regular 18pt grey). Presets set style fields only.
- **Recent colours** row (last 6) shared by all tools.

Rendering: all in `TextAnnotation.attributes(for:)` + `draw()`; the inline editor already uses the
same attributes, so it matches automatically. Tests: legacy decode, preset round-trip, scale helper,
render test (background box pixels are the chosen colour; outline widens ink bounds).

## 6. Part 3 — Redaction v2 (blur / pixelate strength) + Highlighter & Spotlight

- `BlurAnnotation` / `PixelateAnnotation` store a **strength** (blur radius 2…40 px, default 12;
  pixel size 4…48 px, default 12) and **re-render their patch from the base image for their current
  frame** whenever frame or strength changes. **Fixes a latent bug:** today the patch is baked at
  creation, so moving a blur box shows the old area's blur over the new area, and resizing stretches
  it.
- Inspector "Strength" slider with live preview; applies to the selected redaction(s) and becomes
  the default. Blur/Pixelate stays a segmented switch; **Blur ↔ Pixelate converts a selected
  redaction** in place.
- Extra (recommended): **Black-out** mode (solid box, strongest redaction) as a third segment —
  pixelate/blur can sometimes be partially reversed on text; a solid box can't.
- Tests: `Redactor` strength monotonic (higher strength → lower local variance); moved patch equals
  a fresh render of the new region.

**Highlighter tool (owner-chosen extra).** A freehand translucent marker, like a real highlighter
pen: drag draws a path (⇧ = straight line); colour from the palette (default yellow), width
S/M/L (12/20/32 px), opacity slider (default 40%), drawn with multiply blending so text underneath
stays readable. New `HighlighterAnnotation` (points + style), movable, deletable; bounding box =
path bounds + half width.

**Spotlight tool (owner-chosen extra).** Drag a rectangle (⌥ = ellipse); everything *outside* all
spotlight shapes is dimmed. Inspector: Shape (Rectangle/Ellipse), Dim amount slider (default 60%
black). Several spotlights combine into one dim layer with several holes. New `SpotlightAnnotation`;
the renderer draws one dim layer (even-odd fill: full image minus all spotlight shapes) directly
above the base image, below every other annotation, so arrows/text stay bright.
Tests: render test — pixels inside a spotlight unchanged, outside darkened by the chosen amount;
highlighter pixels blend (not replace) the base.

## 7. Part 4 — Recording setup strip v2

### 7.1 Layout
```
┌────────────────────────────────────────────────────────────────────────────────────┐
│  [▭ Full Screen]  [⬚ Area…]  [🗔 Window…]     Format [MP4|GIF]   FPS [30|60]    ✕  │
│  ────────────────────────────────────────────────────────────────────────────────  │
│  🎙 Microphone            🔊 System audio          📷 Camera                         │
│  [MacBook Pro Mic   ▾]    [All apps        ▾]      [Off              ▾]              │
│  ▮▮▮▮▯▯▯ level                                                                      │
│  ────────────────────────────────────────────────────────────────────────────────  │
│  ⓘ Microphone: records your voice from the selected input. Choose "Off" to skip it.  │
└────────────────────────────────────────────────────────────────────────────────────┘
```
- Each source is **icon + caption + popup menu**, replacing the bare toggles:
  - **Microphone:** `Off` · each input device (built-in, AirPods, USB, Continuity mics) — listed
    via `AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio,
    position: .unspecified)`; persisted by `uniqueID` (`RecordingConfig.microphoneDeviceID`, falls
    back to the default device if missing). A small **live level meter** proves the mic works
    before recording.
  - **System audio:** `Off` · `All apps` · `All apps except BetterScreenshot`
    (`SCStreamConfiguration.excludesCurrentProcessAudio`) · for window recordings, `Only this app`
    (**probe**: SCK audio with a single-app filter).
  - **Camera:** `Off` · each camera (built-in, Continuity Camera) + a Small/Medium size sub-menu.
- **Hint line** at the bottom: hovering or focusing any control shows one plain sentence about it
  (the explanatory text the owner asked for). Default text when nothing is hovered: "Pick what to
  record, then choose Full Screen, Area or Window."
- Existing toggles map onto the new menus (mic Bool → `Off`/default device), so settings survive.
- `RecordStripController` is rebuilt; the device lists come from a small `AudioInputCatalog` /
  `CameraCatalog` (thin wrappers so the strip is testable with fake device lists).

## 8. Part 5 — Live recording controls v2 (expanded pill)

### 8.1 Layout (expanded by default; chevron collapses to today's compact pill)
```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ● 1:23  │ [🎙 Mic ✓] [🔊 Sound ✓] [📷 Cam] │ [🗔 Switch window…] │ [↺] [🗑] [⏸] [■] │ ‹ │
└──────────────────────────────────────────────────────────────────────────────┘
      hover hint (tooltip): "Mute microphone — the video keeps a silent gap, stays in sync"
```
- **Mute mic / mute system audio** (toggle, icon crosses out when muted). Implementation: keep
  appending buffers but **zero their PCM samples** while muted, so the audio track stays continuous
  and in sync (dropping buffers would leave gaps that some players mishandle). The track must exist
  from the start, so muting only works for sources enabled when recording began; a disabled source's
  button is greyed with a tooltip saying why.
- **Camera bubble** show/hide.
- **Switch window…** (window recordings) / **Switch area…** (area recordings): reuses the existing
  window picker, then `SCStream.updateContentFilter(_:)` retargets the live stream without stopping.
  The output size is fixed at start, so a differently-sized window is **letterboxed** to fit
  (`SCStreamConfiguration.preservesAspectRatio`). **Probe first:** retarget a running stream
  between two windows of different sizes and check the MP4.
- **Restart** (discard what's recorded so far and start again with the same settings, after a
  confirm) and **Discard** (stop and delete, confirm) — CleanShot has restart.
- **Pause / Stop** as today. The pill remembers where it was dragged. Still excluded from the video
  unless "Show stop button in recording" is on.
- Mid-recording **mic device switch** (from the mic button's menu) — **probe**: swapping the
  `AVCaptureSession` input while the writer runs.

`ScreenRecorder` gains `setMicMuted(_:)`, `setSystemAudioMuted(_:)`, `retarget(filter:)`; the
silence logic is a pure `SilenceFill` helper over `AudioBufferList` → unit-tested.

## 9. Part 6 — Video editor v2 (cut)

### 9.1 What changes
The trim window grows into a small editor. AVKit's built-in trim mode only supports **one** range,
so cutting needs our own timeline.
```
┌───────────────────────────────────────────────────────────────────────────────┐
│                          (video preview — AVPlayerView, no AVKit trim UI)       │
├───────────────────────────────────────────────────────────────────────────────┤
│  ▶ 0:12.4 / 0:45.0     [✂ Split ⌘B]  [🗑 Delete ⌫]  [⟲][⟳]     Zoom ▬          │
│  ┌──────────┬───────────────┬─────────────────────────┬──────────────────┐     │
│  │▓▓ seg 1 ▓│░░ deleted ░░░░│▓▓▓▓▓▓ seg 2 ▓▓▓▓▓▓▓▓▓▓▓▓│▓▓▓ seg 3 ▓▓▓▓▓▓▓▓│     │
│  └──────────┴───────────────┴───────────▲─────────────┴──────────────────┘     │
│   filmstrip thumbnails; yellow edges drag to fine-trim; ▲ = playhead           │
├───────────────────────────────────────────────────────────────────────────────┤
│  0:31.2 kept of 0:45.0 · ☐ Mute audio            Cancel  Save as Copy  [Replace] │
└───────────────────────────────────────────────────────────────────────────────┘
```
- **Split** at the playhead (⌘B or S), **Delete** the selected segment (⌫), drag segment edges to
  trim, **undo/redo** (⌘Z/⇧⌘Z), **Space** play/pause, ←/→ step one frame, **I / O** set in/out.
- Preview plays only the kept segments (an `AVMutableComposition` rebuilt on each edit).
- Model: pure `CutList` (ordered kept ranges over the source duration; split / delete / trim /
  undo stack) → unit-tested; `TrimRange` becomes the single-segment case.
- Export: composition of kept segments (+ mute) through the existing `TrimExporter` paths
  (copy / atomic replace).

### 9.2 Cut precision — **decided (owner, 2026-09-24): frame-accurate**
Any export with a middle cut, a speed change, or a per-segment mute is **re-encoded**
(`AVAssetExportSession` with `AVAssetExportPresetHighestQuality`, hardware H.264) so every cut lands
exactly on the chosen frame; a progress bar shows while it runs (a 1-minute clip takes seconds).
A plain start/end trim with no other edits stays lossless passthrough, as today. Also record with a
keyframe every 0.5 s (`AVVideoMaxKeyFrameIntervalDurationKey`) so passthrough trims land closer.
**Probe:** re-encode speed + quality of a 60 s, 3-segment 1080p60 composition on the owner's Mac.

### 9.3 Per-segment speed / mute + GIF export (owner-chosen extras)
- Right-click (or the segment's inspector row) → **Speed 1× / 1.5× / 2× / 4×** and **Mute segment**.
  Speed uses `AVMutableCompositionTrack.scaleTimeRange`; a sped-up segment's audio is **muted** by
  default (avoids chipmunk audio; a note in the UI says so). The timeline draws sped segments
  narrower with a "2×" badge; the kept-duration label accounts for speed.
- **Export as GIF…** in the save menu: render the edit to a temp MP4, then the existing
  `GIFExporter` (10 fps, ≤ 960 px wide), saved next to the original as `<name> (edited).gif`.
- `CutList` segments gain `speed: Double` and `muted: Bool` (pure, unit-tested: kept duration with
  speeds, split preserves a segment's speed/mute).

## 10. Brainstormed extras (owner picks; ✅ = recommended to include in the part named)

**Editor**
- ✅ Recent colours + eyedropper (pick a colour from the screenshot) — Part 1.
- ✅ Opacity for every object — Part 1.
- ✅ Text style presets, outline, shadow, underline/strike — Part 2.
- ✅ Black-out redaction; strength sliders; Blur↔Pixelate convert — Part 3.
- ✅ Highlighter tool (translucent marker) and Spotlight tool — **owner-chosen**, Part 3.
- Pencil / freehand tool.
- Arrow styles: curved, double-headed, thickness taper.
- Duplicate (⌘D), copy/paste style (⌥⌘C / ⌥⌘V), nudge with arrow keys.
- ✅ Canvas zoom (pinch, ⌘-scroll, ⌘+/⌘−) and single-letter tool shortcuts — **owner-chosen**, Part 1.

**Recording**
- ✅ Mic level meter; device menus; hint line — Part 4.
- ✅ Mute mic/system audio, switch window, restart, discard — Part 5.
- ✅ "Hide cursor" option (`showsCursor` is currently always on).
- Resolution preset (Native / 1080p / 720p) for smaller files.
- "Open the video editor after recording" setting.
- Remember the last target (Full Screen / Area / Window) and last area.

**Video editor**
- ✅ Split / delete / undo / keyboard shortcuts / filmstrip — Part 6.
- ✅ Per-segment speed and mute; export the edit as GIF — **owner-chosen**, Part 6.
- Crop the video frame.

**Out of scope** (constraints): uploading/sharing, background/wallpaper styling (dropped by owner),
Do Not Disturb toggling (no public API), the Windows port (none of v2/v3 is ported yet).

## 11. Build order, testing, risks

**Order:** Part 0 (bug, tiny) → Part 1 (inspector; Parts 2–3 need it) → Part 2 (text) → Part 3
(redaction) → Part 4 (setup strip) → Part 5 (live pill; needs two probes) → Part 6 (cut editor;
biggest). Parts 4–6 don't depend on 1–3 and could go first if the owner prefers recording work.

**Testing per part:** pure models (`InspectorModel`, `TextScale`, `CutList`, `SilenceFill`,
catalog mapping) get TestKit unit tests; AV paths get generated-MP4 tests like
`TrimExporterTests`; UI gets headless probes (synthetic events + snapshots) plus a short manual
checklist for the owner. `scripts/test.sh` must stay green after every part.

**Risks / probes:**
1. `SCStream.updateContentFilter` between different-size windows (Part 5) — if letterboxing
   doesn't work, "Switch window" only offers windows of the same size, or is dropped.
2. Swapping the mic device mid-recording (Part 5) — fallback: device choice only before recording.
3. Single-app system audio for window recordings (Part 4) — fallback: offer only All / All-except-us.
4. Passthrough multi-segment joins (Part 6) — decides whether re-encoding is needed at all.
5. Window width with the inspector (Part 1) — the canvas must still fit at the ~864pt minimum;
   collapsing the inspector returns to the current layout.

## 12. Windows-port handoff document (required deliverable of every part)

The Windows port (C#/.NET 9 + WPF, on the `windows-port` branch under `windows/`; its engine records
with **ffmpeg** — `ddagrab`/`gdigrab` video, WASAPI loopback system audio, `dshow` mic; see
`windows/README-win.md`, `windows/docs/PROGRESS.md`, and the per-module "ground truth" files
`windows/docs/port-reference/0N-*.md`) will receive all of this, and today has **none** of it —
nor the 2026-09-24 text-font/text-box, recording-pill and trim work (commits `d845ad1`, `4a4316c`,
`88f3a8f`).

**Deliverable:** `docs/MAC-TO-WINDOWS-PARITY-v3.md` on `main` (the reverse of
`docs/WINDOWS-TO-MAC-PARITY.md`). Part 0's plan creates it with a section for the already-built
2026-09-24 features; **every later part adds its section before its final commit**. Each section
must let someone port it without reading Swift:
- **Layout, exactly:** every panel/window with sizes, paddings, order of items, grouping, section
  titles, control types, labels, tooltips and hint-line texts (verbatim), icon names (SF Symbol →
  the port's icon set in `windows/src/BetterScreenshot.App/Resources/Icons.xaml`), colours, and an
  ASCII mockup matching the shipped UI (plus a PNG snapshot from the headless probe when possible).
- **Items & behaviour:** what each control does, keyboard shortcuts, defaults, clamps/ranges,
  undo behaviour, edge cases, and error messages (verbatim).
- **Data:** new/changed persisted keys and their defaults + legacy decoding rules (the port stores
  settings in `SettingsStore.cs` / `EditorStyle.cs` / `RecordingConfig.cs`).
- **Pure logic to port 1:1** (with the Swift test cases listed so they can be re-created in the
  port's tests), e.g. `TextScale`, `CutList`, `TrimRange`, `TrimmedFileName`, `InspectorModel`.
- **Where it goes in the port:** the matching Windows files (e.g. editor →
  `windows/src/BetterScreenshot.App/Editor/EditorWindow.xaml(.cs)` + `windows/src/BetterScreenshot.Editor/`;
  record strip → `Recording/RecordStripWindow.xaml`; engine → `Recording/RecordingEngine.cs`,
  `windows/src/BetterScreenshot.Recording/FfmpegArgs.cs`).
- **Platform notes:** where the Windows mechanism must differ. Known now: live mute / switch window
  can't be changed inside a running ffmpeg process — the port's segment-per-span design (already
  used for pause) suggests starting a new segment with the new inputs/region and concatenating
  (segments must share resolution → scale/pad); mic device lists come from
  `DshowAudioDevices.cs`; trimming/cutting/GIF needs ffmpeg commands instead of AVFoundation.

## 13. Remaining open items
Part 7 (§14) is approved and deferred (build later). For Parts 0–6: none blocking — the owner's decisions are recorded at the top and the spec is approved. The owner
chose to skip per-part implementation plans; parts are built directly from this spec by sub-agents
in git worktrees (see `docs/PROGRESS-v3.md`).

## 14. Part 7 — Interactive guided tours and ⓘ help on every window

Added 2026-09-25 · Status: **approved by the owner 2026-09-25 — deferred: "we will build later"**. Build it
after the UI-review fixes (lane "UI fixes" in `docs/PROGRESS-v3.md`); Parts 0–6 are built.

### 14.1 What the owner asked for
First message (2026-09-25): "When you open the app for the first time you have a tour — taking photos
with keybinds, then editing photos — where buttons are highlighted with a tag explaining each thing. The
person can skip the whole thing, or read and go through. There's always an info icon at the top of all
windows to replay the tutorial. Since the UI will get more complicated, explanations must be short and
concise. It must work with the current UI, and cover every part: first time you edit an image, open
Settings, take your first screenshot, edit a video… With actual examples — using Remotion or HyperFrames
to make a digital twin of the UI, like a video of someone editing a screenshot."

Follow-up (same day), with a mock — `assets/2026-09-25-tour-tag-mock.png` (next to this spec): the
editor's Colour row outlined in a red box with a red tag "these are the colors" joined to it by a line.
"The demo should be **interactive**, based on the actual UI explanations, that you can press skip on,
**based on what you do**. If you open the editor the first time there's an intro to that; video editing,
same thing; trying to take a video the first time walks you through **all the choices you can make**."

**Owner decisions (2026-09-25):**
- Tours are **interactive and action-driven** on the real UI (this replaces the earlier "read-only"
  choice): steps can wait for the user to *do* the thing (pick a colour, draw an arrow, open the mic
  menu) and advance on their own; every step can be skipped, and so can the whole tour.
- Tags look like the owner's mock: an outline box around the real control + a tag with a leader line.
- **No demo videos** (owner, 2026-09-25): the interactive tour on the real UI *is* the demo. (The
  earlier idea — HyperFrames-rendered clips built from real UI captures — is dropped; see 14.5.)

### 14.2 Terms
- **Tour** — an ordered list of **steps** for one surface or feature (e.g. "Editor", "First recording").
- **Step** — one highlighted control + one short tag. Two kinds:
  - **Explain** — "this is X"; advances on **Next**.
  - **Try** — "do X"; advances **by itself when the user does it** (the app reports the action); a
    **Skip step** link is always there. If the user has already done it, the step is skipped silently.
- **Anchor** — a stable string id on a real control (e.g. `editor.inspector.colour`), so tours don't
  depend on coordinates and survive layout changes.
- **Tour event** — a tiny message the app posts when the user does something tours care about
  (`toolSelected(.arrow)`, `annotationAdded(.arrow)`, `styleChanged(.strokeColor)`, `menuOpened(anchor)`,
  `choiceMade(anchor)`, `recordingStarted`, `segmentSplit`, …).

### 14.3 UX
**The tag (from the owner's mock).** A 2 pt rounded outline box drawn around the anchor (4 pt padding,
6 pt radius) in the tour colour (**accent red `#FF453A`**, matching the mock), and a tag bubble in the
same colour — white text, 12 pt corner radius, max 260 pt wide — joined to the box by a 2 pt leader line.
Inside the tag: **title** (13 pt semibold) · **body** (12 pt, ≤ 2 lines) · footer "2 of 7 ·
**Next** (Explain) *or* Skip step (Try) · Skip tour". The rest of the window gets only a light 20% dim
so the highlighted control stands out, and the overlay is **click-through** — the user clicks the real
control underneath (that's what makes Try steps work); only the tag itself takes clicks. Placement:
beside the anchor on the side with room (the mock puts it to the left), never off-screen; the box and
tag follow the window when it moves or resizes. Keys: Return = Next, Esc = Skip tour. The overlay
never takes keyboard focus from the user's work.

**Copy rules (enforced by a unit test):** title ≤ 4 words; body ≤ 20 words, 1–2 short sentences, verb
first for Try steps ("Pick a colour"), plain words, shortcuts shown as keycaps built from the user's
**current** bindings (`HotkeyBindings`); one idea per step. All strings live in one catalog file.

**When tours run (based on what you do).** Each tour starts the first time the user reaches its
surface or feature, runs once, and can be replayed from the ⓘ. Opening a different surface mid-tour
pauses the current tour (resumes when they come back) rather than stacking tags.

| Tour | Starts when | Steps — **E** = Explain, **T** = Try (advances when done) |
|---|---|---|
| Welcome | first launch, after permission ("Take the tour" / "Skip for now") | E menu-bar icon · E capture shortcuts (keycaps) · T "Take a screenshot now — press ⌘⇧4 and drag" (advances on the first capture; Skip step leaves it for later) → hands over to the Quick Access tour |
| Quick Access card | first capture | E the card · T "Drag it into any app" (or Skip) · E Copy / Edit / Save · T "Click Edit to annotate" → hands over to the Editor tour |
| Editor intro | first editor window | E toolbar · T "Choose the Arrow" · T "Drag on the image" · E the side panel · T "Pick a colour" (the mock) · E Stroke & Opacity · E hint line · E zoom · E Copy / Save / Stack |
| Text tool | first time Text is chosen | T "Click to type" · E "Drag instead for a box" · T "Drag a corner to resize it" · E Styles / Background / Effects |
| Redaction | first Blur or Pixelate | T "Drag over something private" · T "Change the strength" · E Blur / Pixelate / Black-out |
| Highlighter · Spotlight | first use of each | 1–2 steps each |
| First recording | first time the record strip opens | walks through **every choice**: E Full Screen / Area / Window · E MP4 / GIF · E FPS · T "Open the Microphone menu" → E its choices (Off, each mic) + the level meter · T System audio menu → E All apps / All except BetterScreenshot · E Camera + bubble size · E Cursor · E hint line · T "Start recording" → hands over to the pill tour |
| Recording pill | first recording starts | E timer · T "Mute the mic" · E Sound · E Camera · E Switch window/area · E Restart / Discard · E Pause · T "Press Stop when done" |
| Video editor | first Edit Video window | E preview · E timeline · T "Press S to split here" · T "Select a part, press ⌫" · E Speed / Mute segment · E Save as Copy / Replace / GIF |
| Settings | first Settings window | E the cards · E ⓘ tips · E shortcuts |
| History | first History window | E grid · E multi-select + drag · E actions |

Menus: when a Try step opens a pop-up menu (Microphone, System audio…), the tag stays put while the menu
is open and the following Explain step describes the choices once the menu closes (a menu can't be
drawn over).

**If the user wanders off.** A Try step that isn't done is fine — they can use the app normally; the tag
stays until they do it, press Skip step, or leave the window. If an anchor disappears (panel hidden,
feature off), that step is skipped. Closing the window pauses the tour; it resumes next time unless the
user pressed Skip tour.

**First launch.** The Welcome window (`App/MenuBar/OnboardingController.swift`) ends on "You're all set!"
with **Take the tour** (primary) and **Skip for now**, plus a checkbox **"Show me around the first time I
use each part"** (on by default; off = no automatic tours, all still replayable).

**ⓘ on every window.** A small ⓘ at the top-right of every window, opening a menu: **Replay tour** ·
**Keyboard shortcuts** (for that window). Placement:
title-bar accessory on the Editor, Video editor, Settings and History windows (needs the UI review's
title-bar fix first — `docs/reviews/2026-09-25-ui-review.md` found the editor's title-bar accessory has
zero width); next to ✕ on the Record setup strip; the pill and the Quick Access card are too small, so
their tours replay from the menu bar. **Menu bar:** a **Help & Tours** submenu — Take the welcome tour ·
one item per tour · Reset all tours. **Settings:** a "Tours & tips" row with the checkbox above and
**Reset all tours**.

**Accessibility.** VoiceOver reads each tag when it appears and announces when a Try step completes.

### 14.4 Architecture
- **New local package `Packages/TourKit`** (AppKit + pure logic, TestKit tests):
  - `TourCatalog` — every tour, step (anchor, kind, advance-on event, strings) as data.
  - `TourEngine` — pure state machine: start / next / skip step / skip tour / pause / resume; matches
    incoming **tour events** against the current Try step; skips steps whose anchor is missing or whose
    action was already done; unit-tested.
  - `TourEvents` — a tiny event bus (`TourEvents.post(.toolSelected(.arrow))`); surfaces post events and
    never import tour logic beyond this and anchors.
  - `TourAnchors` — `NSView.tourAnchor = "…"` (backed by the accessibility identifier) for AppKit views,
    and a SwiftUI `.tourAnchor("…")` modifier that reports the view's frame (anchor preferences) for
    Settings/History.
  - `TagOverlayController` — a borderless, click-through child window over the host window: light dim,
    outline box, tag + leader line; only the tag takes clicks.
  - `InfoButton` — the ⓘ control + its menu.
- **App side:** `TourCoordinator` (in `App/`) owns triggers (first launch, first capture, first editor,
  first strip, …), hand-overs between tours, persistence, the menu-bar submenu and the Settings row.
  Persisted in UserDefaults: `toursSeen` (tour id → catalog version seen), `toursPaused` (tour id → step
  index), `firstUseToursEnabled` (Bool, default true). Bumping a tour's version re-offers it once after a
  big UI change.
- **Surfaces** add anchors, post tour events at the points listed in 14.3, and add an ⓘ — no layout
  changes (works with the current UI).

### 14.5 Demo videos — dropped
Considered and **dropped by the owner (2026-09-25)**: short clips rendered with HyperFrames (HeyGen's
open-source HTML-to-MP4 tool) from real UI captures. The interactive tour on the real UI replaces them —
no video pipeline, no bundle growth, nothing extra to keep in sync. Don't re-propose unless the owner
asks (e.g. for README/marketing clips).

### 14.6 Testing
`TourEngine` unit tests (order, Next, Try steps advancing on the right event and ignoring others,
skip step / skip tour, already-done steps skipped, missing anchors, pause/resume, hand-overs, versions);
catalog lint tests (word limits, every step's anchor exists in a known-anchor list, every Try step names
an event); headless probes that open each surface, post the real actions (the probe technique from the
UI review — synthetic clicks), and snapshot the tag on every step in light and dark; then a manual pass by
the owner.

### 14.7 Risks / probes (run first)
1. **Click-through overlay** — the overlay window must pass clicks to the real control under the box while
   the tag stays clickable, and never take focus (also over the non-activating record strip and pill).
2. **Anchors in SwiftUI windows** (Settings, History) — fallback: highlight the whole card/section.
3. **Pop-up menus** — confirm the tag survives a menu opening/closing and that `choiceMade` can be posted
   from the menu's action.
4. **Event coverage** — every Try step needs a real event hook; add each hook where the action already
   happens (tool change, annotation added, style edit, split, recording start…).

### 14.8 Build order and Windows handoff
Before Part 7: fix the top UI-review issues (`docs/reviews/2026-09-25-ui-review.md` — at minimum the
editor title-bar accessory, which the ⓘ depends on). Then: TourKit engine + events + catalog + anchors →
tag overlay → Welcome + Quick Access + Editor tours → Recording strip + pill → Video editor → Text /
Redaction / Highlighter / Spotlight micro-tours → Settings + History → ⓘ + menu bar + Settings row. Part 7 adds its section to `docs/MAC-TO-WINDOWS-PARITY-v3.md` like every other
part: exact tag layout and colours, every tour's steps and strings verbatim, triggers, events, and
persistence keys.
