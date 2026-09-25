# App/Recording — screen-recording orchestration

- `RecordingCoordinator.swift` — orchestrates a screen recording: start/stop/state, driving
  `Packages/RecordingKit` (`ScreenRecorder`, GIF export, mic/camera/keystroke/click overlays) and
  routing the finished file into History.
- `RecordStripController.swift` — the floating pre-record "record strip" (v3 Part 4): a borderless
  `NSPanel` that can still become key (Tab focus), in the shared dark HUD (`RecordingHUDStyle`). Full
  Screen / Area… / Window… · Format · FPS (a small accent-filled `ChoiceControl` — `NSSegmentedControl`
  barely marks the choice while the panel isn't key) · ✕, then one labelled column per source
  (Microphone · System audio · Camera 252pt each, Mouse cursor 128pt) with a popup menu each, a live mic
  level meter beside the Microphone caption (runs only when mic access is already granted — otherwise
  an "Allow microphone access…" link, so opening the strip never prompts), and a hint line explaining
  whatever is hovered/focused (that group's caption brightens; idle in GIF mode it says why audio is
  off). Popups use `EvenInsetPopUpCell` so truncated device names keep the normal title inset. Menus
  come from RecordingKit's `AudioInputCatalog` / `CameraCatalog` (injectable `DeviceCatalog`s) and write
  straight into `SettingsStore.recording`. Verified by a headless probe that copies this file + a stub
  SettingsStore (synthetic `mouseEntered` events via `NSEvent.enterExitEvent(trackingNumber:)`,
  snapshots via `CGWindowListCreateImage`; probe windows must stay behind the owner's — sink them to
  just above the desktop level and `orderBack`; window-list snapshots show the HUD's flat fallback
  grey, not the live blur).
- `RecordingCoordinator.begin(target:screen:)` plumbs the choices: camera `deviceID`, GIF → no mic /
  system audio, and for **window** targets a display-wide `systemAudioFilter` — a
  `desktopIndependentWindow` filter only hears that window's own process (a browser tab records
  silence), so window recordings take system audio from a separate audio-only stream.
- `RecordingControlsController.swift` — the floating recording pill shown for the whole session
  (countdown included), in the shared dark HUD. Expanded by default: ● timer │ Mic · System audio ·
  Camera │ Switch Window…/Area… │ Restart · Discard · Pause · Stop │ chevron (collapses to timer · Pause ·
  Stop). Paused shows "Paused" over the time. Hovering any control shows its hint in a bubble drawn in
  the pill's own window (so it's excluded from the recording with it) — no tooltips; the window is the
  capsule (`pillFrame`) plus the bubble, laid out by hand in `layoutWindow()`. Persists
  `recordingPillCollapsed` + `recordingPillAnchor` (the capsule's bottom-right corner) in UserDefaults;
  Restart/Discard confirm inline (never a dialog — the panel must not steal focus), the confirming
  button filling both buttons' slot so the width never changes (`RecordingPillLayout`). Pure view:
  `update(Status)` is fed by `RecordingCoordinator.pillStatus()`. `RecordingConfig.controlsInRecording` (off by default) decides
  whether `RecordingCoordinator` excludes its `SCWindow` from the capture filter (re-applied on an area
  switch). Verified with a headless snapshot probe (layout in `docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 5).
- Live pill actions live in `RecordingCoordinator` (`// MARK: - Live pill`): mute →
  `ScreenRecorder.setMicMuted`/`setSystemAudioMuted` (reset in `arm()`, kept by Restart); camera →
  `CameraBubbleController.setHidden`/`show`; Switch → pause, `presentWindowPicker` / area
  `selection`, `ScreenRecorder.retarget`, resume, refocus (`activeTarget` tracks the current target);
  Restart → stop + delete + `begin()` again on `activeTarget`; Discard → stop + delete, no card/history.
- `RecordingCoordinator.presentTrim(url:restoreCard:)` opens RecordingKit's `TrimWindowController`
  (the video editor — from the Quick Access card's ✂ button or History's Trim…). The card path passes
  `restoreCard`, which runs once when the window closes (any way) and re-presents the card with a fresh
  thumbnail (`bringBackCard`) — the ✂ button dismissed it; History passes nil. The editor's Save as
  Copy and Export as GIF results go through `finishRecording(at:)` (new card + History entry).

Recording model + capture engine live in `Packages/RecordingKit`; this section is the app-side
orchestration and on-screen controls. Verify by recording in the built app.
