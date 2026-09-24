# App/Recording — screen-recording orchestration

- `RecordingCoordinator.swift` — orchestrates a screen recording: start/stop/state, driving
  `Packages/RecordingKit` (`ScreenRecorder`, GIF export, mic/camera/keystroke/click overlays) and
  routing the finished file into History.
- `RecordStripController.swift` — the floating pre-record "record strip" `NSPanel` (v3 Part 4): Full
  Screen / Area… / Window… · Format · FPS · ✕, then one labelled column per source (Microphone ·
  System audio · Camera · Cursor) with a popup menu each, a live mic level meter (runs only when mic
  access is already granted — otherwise an "Allow microphone access…" link, so opening the strip never
  prompts), and a hint line explaining whatever is hovered/focused. Menus come from RecordingKit's
  `AudioInputCatalog` / `CameraCatalog` (injectable `DeviceCatalog`s) and write straight into
  `SettingsStore.recording`. Verified by a headless probe that copies this file + a stub SettingsStore
  (synthetic `mouseEntered` events via `NSEvent.enterExitEvent(trackingNumber:)`, snapshots via
  `CGWindowListCreateImage`).
- `RecordingCoordinator.begin(target:screen:)` plumbs the choices: camera `deviceID`, GIF → no mic /
  system audio, and for **window** targets a display-wide `systemAudioFilter` — a
  `desktopIndependentWindow` filter only hears that window's own process (a browser tab records
  silence), so window recordings take system audio from a separate audio-only stream.
- `RecordingControlsController.swift` — the floating timer · Pause · Stop pill shown for the whole
  session. `RecordingConfig.controlsInRecording` (off by default) decides whether
  `RecordingCoordinator` excludes its `SCWindow` from the capture filter.
- `RecordingCoordinator.presentTrim(url:)` opens RecordingKit's `TrimWindowController` (from the
  Quick Access card's ✂ button or History's Trim…).

Recording model + capture engine live in `Packages/RecordingKit`; this section is the app-side
orchestration and on-screen controls. Verify by recording in the built app.
