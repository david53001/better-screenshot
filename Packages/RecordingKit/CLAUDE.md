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
- Video editor (trim / cut; opened from a recording's Quick Access ✂ or History's Trim…):
  - `CutList.swift` (pure, tested) — the edit: ordered kept segments of the source, each with speed
    (1× / 1.5× / 2× / 4×) and mute; split / remove / edge trims / in-out points, output↔source↔timeline
    time mapping, `passthrough` (a plain start/end trim), and `CutHistory` (undo / redo of whole
    values). `TrimRange` (pure) is the single-segment case; `TrimmedFileName` (pure) names exports
    "<name> (trimmed).mp4" / "<name> (edited).gif".
  - `CutComposition.swift` — `CutList` → `AVMutableComposition` (segments back to back, per-track
    `scaleTimeRange` for speed, empty audio where muted) for both the preview and the export, plus
    `videoComposition(for:source:)`. **Exports always render through that video composition**: without
    one, `AVAssetExportPresetHighestQuality` silently copies the samples behind an MP4 edit list
    instead of re-encoding (only edit-list-aware players honour it), and a sped-up segment followed by
    the next stretch of the same source fails with -16364 (both probed 2026-09-24).
  - `TrimExporter.swift` — passthrough for a plain trim, re-encode otherwise (with progress);
    `exportCopy`, atomic `replaceOriginal` (temp in an item-replacement dir + `replaceItemAt`),
    `exportGIF` (temp MP4 → `GIFExporter`). Tested on generated MP4s (frame-exact cuts, 2× length,
    silent muted segment, GIF frame count).
  - `TrimWindowController.swift` (window, keyboard, export flow) + `CutTimelineView.swift` (filmstrip
    timeline, edge drags, context menu). Verified with a headless probe (synthetic clicks/keys +
    snapshots); layout and strings in `docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 6.
- Recordings are written with a keyframe at least every 0.5 s (`RecordingConfig.keyFrameInterval`) so
  passthrough trims land close to the chosen frame.

`RecorderState`, `RecordingConfig`, `SilenceFill`, `LetterboxFit`, `CutList`, and the trim/export pieces (except the window) are unit-tested; the AV/overlay pieces are verified manually or with headless probes (retarget, mute, pause sync — see `docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 5; the video editor — Part 6).

## Verify
`swift run --package-path Packages/RecordingKit RecordingKitTests`.
