# App/Recording — screen-recording orchestration

- `RecordingCoordinator.swift` — orchestrates a screen recording: start/stop/state, driving
  `Packages/RecordingKit` (`ScreenRecorder`, GIF export, mic/camera/keystroke/click overlays) and
  routing the finished file into History.
- `RecordStripController.swift` — the floating pre-record "record strip" `NSPanel` (target buttons +
  per-recording toggles, shown before recording starts).
- `RecordingControlsController.swift` — the floating timer · Pause · Stop pill shown for the whole
  session. `RecordingConfig.controlsInRecording` (off by default) decides whether
  `RecordingCoordinator` excludes its `SCWindow` from the capture filter.
- `RecordingCoordinator.presentTrim(url:)` opens RecordingKit's `TrimWindowController` (from the
  Quick Access card's ✂ button or History's Trim…).

Recording model + capture engine live in `Packages/RecordingKit`; this section is the app-side
orchestration and on-screen controls. Verify by recording in the built app.
