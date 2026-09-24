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

_(pending — filled when Part 5 lands)_

---

## Part 6 — Video editor v2 (cut, per-segment speed/mute, GIF export)

_(pending — filled when Part 6 lands)_
