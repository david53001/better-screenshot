# App/Recording — screen-recording orchestration

- `RecordingCoordinator.swift` — orchestrates a screen recording: start/stop/state, driving
  `Packages/RecordingKit` (`ScreenRecorder`, GIF export, mic/camera/keystroke/click overlays) and
  routing the finished file into History.
- `RecordStripController.swift` — the floating pre-record "record strip" `NSPanel` (target buttons +
  per-recording toggles, shown before recording starts).
- `RecordingControlsController.swift` — the floating recording pill shown for the whole session
  (countdown included). Expanded by default: ● timer │ Mic · Sound · Camera │ Switch window…/area… │
  Restart · Discard · Pause · Stop │ chevron (collapses to timer · Pause · Stop). Persists
  `recordingPillCollapsed` + `recordingPillAnchor` (bottom-right corner) in UserDefaults; Restart/Discard
  confirm inline (never a dialog — the panel must not steal focus). Pure view: `update(Status)` is fed by
  `RecordingCoordinator.pillStatus()`. `RecordingConfig.controlsInRecording` (off by default) decides
  whether `RecordingCoordinator` excludes its `SCWindow` from the capture filter (re-applied on an area
  switch). Verified with a headless snapshot probe (layout in `docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 5).
- Live pill actions live in `RecordingCoordinator` (`// MARK: - Live pill`): mute →
  `ScreenRecorder.setMicMuted`/`setSystemAudioMuted` (reset in `arm()`, kept by Restart); camera →
  `CameraBubbleController.setHidden`/`show`; Switch → pause, `presentWindowPicker` / area
  `selection`, `ScreenRecorder.retarget`, resume, refocus (`activeTarget` tracks the current target);
  Restart → stop + delete + `begin()` again on `activeTarget`; Discard → stop + delete, no card/history.
- `RecordingCoordinator.presentTrim(url:)` opens RecordingKit's `TrimWindowController` (from the
  Quick Access card's ✂ button or History's Trim…).

Recording model + capture engine live in `Packages/RecordingKit`; this section is the app-side
orchestration and on-screen controls. Verify by recording in the built app.
