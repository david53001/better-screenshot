# RecordingKit — screen recording engine + overlays

Screen recording (ScreenCaptureKit), GIF export, and the on-screen recording overlays. Imported by the
`App/` target (`App/Recording`).

## Key files (`Sources/RecordingKit/`)
- `ScreenRecorder.swift` — the recording engine. `start(…systemAudioFilter:)`: when set, system audio
  comes from a separate audio-only `SCStream` on that (display) filter instead of the video filter —
  window filters only hear the window's own process — so a window `retarget` leaves the audio stream
  running. Honours `showsCursor` and `systemAudioMode.excludesOwnAudio` (`excludesCurrentProcessAudio`).
  Live controls: `setMicMuted`/`setSystemAudioMuted`
  (muted tracks keep appending `SilenceFill` copies — continuous, in sync), `retarget(filter:sourceRect:)`
  (`SCStream.updateContentFilter` + `updateConfiguration`; new content letterboxed via `LetterboxFit`
  as `destinationRect`). Pause/resume: the resume gap is anchored on the last audio end (or the pause
  moment), not the last video frame (that put video ~0.9 s ahead of audio after pausing over static
  content), and the newest frame seen while paused opens the resumed span (static content sends no
  new frames).
- `SilenceFill.swift`, `LetterboxFit.swift` — pure helpers for the above (tested).
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
- `RecordingHUDStyle.swift` — the shared dark HUD look (`.hudWindow`, vibrant dark, 40% black tint,
  1px 10% white border; text white / white 60%) used by the countdown, the record strip and the live
  pill. `RecordingPillLayout.swift` (pure, tested) — the pill's confirm-slot widths and hover-hint
  bubble placement. `CountdownOverlayController.swift` — the pre-record countdown (digit centred by
  its baseline, "Click to start now").
- `CameraBubbleController.swift`, `KeystrokeOverlayController.swift`, `ClickHighlighter.swift` —
  camera bubble (`show(…deviceID:)`) + keystroke/click visualizers shown during recording. The
  bubble's `setHidden(_:)` hides/re-shows it in place (live pill's Camera toggle).
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
  - `TrimWindowController.swift` (window, keyboard, export flow, error state for a missing/unreadable
    file, Replace Original enabled only when the video differs from the file) + `CutTimelineView.swift`
    (time ruler, filmstrip timeline, edge drags, context menu). Verified with a headless probe (synthetic
    clicks/keys + snapshots); layout and strings in `docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 6.
  - `TimeRuler.swift` (pure, tested) — the timeline's ruler: round **output** times over kept segments
    only, label step picked to fit, labels that would touch or clip dropped. `FilmstripFrames.swift`
    (pure, tested) — how many thumbnails to load (enough for full zoom, 12…400, ≤ 30/s) and in what
    order (coarse to fine). Probe clips often burn a timestamp into every frame; in snapshots that text
    shows *inside* the thumbnails and is not an app label (the 2026-09-25 UI review mistook it for one).
- Recordings are written with a keyframe at least every 0.5 s (`RecordingConfig.keyFrameInterval`) so
  passthrough trims land close to the chosen frame.
- Guided tours (v3 Part 7): the **video editor tour** (steps in TourKit `Catalog/VideoEditorTours.swift`, all
  details in `docs/MAC-TO-WINDOWS-PARITY-v3.md` §7.7). `TrimWindowController` sets the anchors
  (`view.tourAnchor`): `video.preview`, `video.timeline` (the timeline's **scroll view** — the content view is
  wider when zoomed), `video.segment` (the selected-part row), `video.saveCopy`, `video.replace`; posts
  `action("video.split")` / `action("video.segmentDeleted")` from `splitAtPlayhead` / `deleteSelected` only when
  the edit applied (`perform` returns Bool); posts `surfaceShown(.videoEditor)` once per window when the
  recording has loaded *and* the window is visible (`announceToTours`); installs the ⓘ with `shortcuts` (update
  that list when a key is added). `NSComboButton` ignores `setAccessibilityIdentifier`, so Save as Copy is an
  `AnchoredComboButton` that keeps it. `ScreenRecorder.updateFilter(_:)` swaps only the running stream's filter —
  the app uses it to leave out a tour tag that appeared mid-recording (App/Recording `TourTagRecordingGate`).
  Tests: `Tests/RecordingKitTests/RecordingTourTests.swift` (every recording/video tour body fits the tag's two
  lines at its max width — the 20-word lint doesn't guarantee that; video-editor anchors; the ⓘ; Try events).

`RecorderState`, `RecordingConfig`, `DeviceList`, `MicLevel`, `SilenceFill`, `LetterboxFit`, `RecordingPillLayout`, `RecordingHUDStyle`, `CutList`, `TimeRuler`, `FilmstripFrames`, and the trim/export pieces (except the window) are unit-tested; the AV/overlay pieces are verified manually or with headless probes (retarget, mute, pause sync — see `docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 5; record strip, device menus, window-recording audio — Part 4; the video editor — Part 6).

## Verify
`swift run --package-path Packages/RecordingKit RecordingKitTests`.
