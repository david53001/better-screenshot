# RecordingKit — screen recording engine + overlays

Screen recording (ScreenCaptureKit), GIF export, and the on-screen recording overlays. Imported by the
`App/` target (`App/Recording`).

## Key files (`Sources/RecordingKit/`)
- `ScreenRecorder.swift` — the recording engine. `start(…systemAudioFilter:)`: when set, system audio
  comes from a separate audio-only `SCStream` on that (display) filter instead of the video filter —
  window filters only hear the window's own process. Honours `showsCursor` and
  `systemAudioMode.excludesOwnAudio` (`excludesCurrentProcessAudio`).
- `RecorderState.swift`, `RecordingConfig.swift` — recording state machine + config (pure, tested).
  Config v3 keys: `systemAudioMode` (off/all/excludeSelf; legacy `systemAudio` Bool still read and
  written, and kept as a get/set view), `microphoneDeviceID` / `cameraDeviceID` (`uniqueID`, nil =
  default), `showsCursor`.
- `DeviceChoice.swift` (pure, tested) — `DeviceList` (saved → default → first resolution, menu choice,
  Off + de-duplicated device rows) behind the `DeviceCatalog` protocol; `DeviceCatalog.swift` —
  `AudioInputCatalog` / `CameraCatalog` (AVFoundation discovery; listing never prompts for access).
  Reuse these for any later device menu (e.g. the mid-recording mic switch).
- `MicLevel.swift` (pure, tested) — dBFS → meter fraction (−60 dB floor), smoothing, lit segments.
- `GIFExporter.swift`, `GIFTiming.swift` — GIF output + frame timing.
- `MicCapturer.swift` — microphone audio from a chosen device (`start(deviceID:)`, falls back to the
  default), per-buffer power via `onLevel`; start/stop serialized on one queue so a quick start→stop
  can't orphan a running session.
- `CameraBubbleController.swift`, `KeystrokeOverlayController.swift`, `ClickHighlighter.swift` —
  camera bubble (`show(…deviceID:)`) + keystroke/click visualizers shown during recording.
- Trim: `TrimRange.swift`, `TrimmedFileName.swift` (pure, tested), `TrimExporter.swift` (passthrough
  trim/mute export, copy + atomic replace; tested on a generated MP4), `TrimWindowController.swift`
  (AVKit `AVPlayerView` trim-mode window; verified manually).

`RecorderState`, `RecordingConfig`, `DeviceList`, `MicLevel`, and the trim pieces (except the window) are unit-tested; the AV/overlay pieces are verified manually.

## Verify
`swift run --package-path Packages/RecordingKit RecordingKitTests`.
