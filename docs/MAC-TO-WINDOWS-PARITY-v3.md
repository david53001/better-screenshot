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

_(pending — written by the coordinating session)_

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
