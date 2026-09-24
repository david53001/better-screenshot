# RecordingKit — screen recording engine + overlays

Screen recording (ScreenCaptureKit), GIF export, and the on-screen recording overlays. Imported by the
`App/` target (`App/Recording`).

## Key files (`Sources/RecordingKit/`)
- `ScreenRecorder.swift` — the recording engine. Live controls: `setMicMuted`/`setSystemAudioMuted`
  (muted tracks keep appending `SilenceFill` copies — continuous, in sync), `retarget(filter:sourceRect:)`
  (`SCStream.updateContentFilter` + `updateConfiguration`; new content letterboxed via `LetterboxFit`
  as `destinationRect`). Pause/resume: the resume gap is anchored on the last audio end (or the pause
  moment), not the last video frame (that put video ~0.9 s ahead of audio after pausing over static
  content), and the newest frame seen while paused opens the resumed span (static content sends no
  new frames).
- `SilenceFill.swift`, `LetterboxFit.swift` — pure helpers for the above (tested).
- `RecorderState.swift`, `RecordingConfig.swift` — recording state machine + config (pure, tested).
- `GIFExporter.swift`, `GIFTiming.swift` — GIF output + frame timing.
- `MicCapturer.swift` — microphone audio.
- `CameraBubbleController.swift`, `KeystrokeOverlayController.swift`, `ClickHighlighter.swift` —
  camera bubble + keystroke/click visualizers shown during recording. The bubble's `setHidden(_:)`
  hides/re-shows it in place (live pill's Camera toggle).
- Trim: `TrimRange.swift`, `TrimmedFileName.swift` (pure, tested), `TrimExporter.swift` (passthrough
  trim/mute export, copy + atomic replace; tested on a generated MP4), `TrimWindowController.swift`
  (AVKit `AVPlayerView` trim-mode window; verified manually).

`RecorderState`, `RecordingConfig`, `SilenceFill`, `LetterboxFit`, and the trim pieces (except the window) are unit-tested; the AV/overlay pieces are verified manually or with headless probes (retarget, mute, pause sync — see `docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 5).

## Verify
`swift run --package-path Packages/RecordingKit RecordingKitTests`.
