# BetterScreenshot v2.5 — Recording Trim Editor

Date: 2026-06-05 · Status: **implemented 2026-09-24** (on `main`, untagged — see
`docs/PROGRESS-2026-09-24-text-controls-trim.md`). Owner change from this spec: after **Replace
Original** the window stays open on plain playback of the trimmed file (Adjust Trim trims again)
instead of closing; Save as Copy still closes and presents a new Quick Access card.
Builds on: v2.2 (`main`, commit 28403d2+; v2.3/v2.4 recommended first but not required)
Ends at tag: `v2.5-trim`

> **For a fresh session:** read `CLAUDE.md` first. Then turn this spec into a plan with the
> `superpowers:writing-plans` skill and execute it with `superpowers:subagent-driven-development`.
> Verify integration-point symbols against the live code before writing the plan. **Run the
> AVPlayerView trim probe (Risks section) as the plan's first task** — the UI approach hinges
> on it.

## Goal

The largest remaining recording gap vs CleanShot (spec §2 "built-in video editor"): nearly
every screen recording has dead air at the ends, and today users need another app to cut it.

1. **Trim** — cut the start/end of a finished MP4 recording, losslessly (no re-encode).
2. **Mute** — optionally strip the audio tracks on export.
3. Save as a copy or replace the original, with the standard Quick Access feedback.

## Out of scope

CleanShot's quality/resolution/stereo→mono conversions · GIF trimming (future: decode frames,
drop range, re-export via the existing `GIFExporter`/`GIFTiming` pieces — noted, not built) ·
multi-segment cuts (single in/out range only) · annotation overlays on video · opening
arbitrary files (entry points are BetterScreenshot's own recordings only).

## UX flows

### Entry points
- **Quick Access recording card** gains a "Trim" button (`scissors` SF symbol) for MP4
  recordings — the card grows to 5 buttons, matching the screenshot card. GIF cards do not get
  the button (`QuickAccessActions.onTrim` stays nil → button omitted).
- **History window** (if v2.3 shipped): "Trim" action on MP4 recording entries. Optional —
  one-line wiring, skip silently if history isn't present.

### Trim window
- Titled, resizable window (~900×600 min 640×480), like the annotation editor a standalone
  window the coordinator retains.
- `AVPlayerView` (AVKit) fills the window above a bottom action bar. On open the window
  immediately enters AVKit's native trim mode (`beginTrimming`) — QuickTime-style yellow
  in/out handles, scrubbing, and AVKit's own Trim/Cancel chrome.
- Confirming AVKit's trim chrome does **not** touch the file — it just records the selected
  range (read from `currentItem.reversePlaybackEndTime` / `forwardPlaybackEndTime`); the user
  can re-enter trim mode via a "Adjust Trim" button in the action bar.
- Bottom action bar: range label ("0:02.1 – 0:41.8 of 0:45.0") · **Mute audio** checkbox ·
  spacer · **Cancel** · **Save as Copy** · **Replace Original** (accent, default).
- Export runs async with the buttons disabled and a small spinner; the window closes on
  success and the result is presented as a fresh Quick Access recording card (same
  `presentQuickAccess` path recordings already use). HUD on failure ("Couldn't export
  trimmed recording — original untouched").

### Export semantics
- **Lossless**: `AVAssetExportSession` with `AVAssetExportPresetPassthrough` + `timeRange`
  (no re-encode; export of a multi-minute file completes in seconds).
- **Mute**: build an `AVMutableComposition` containing only the video track for the selected
  range, export that with passthrough. (Mute + trim compose naturally this way.)
- **Save as Copy**: writes alongside the original as `<original-stem> (trimmed).mp4`,
  uniquified with ` 2`, ` 3`… on collision.
- **Replace Original**: export to a temp URL, then atomic `FileManager.replaceItemAt` — the
  original is never destroyed before the new file is complete. Note: a Quick Access card or
  history entry pointing at the original path remains valid (same path, new content).

## Architecture

### RecordingKit (the kit already owns recording post-processing — GIFExporter precedent)
- `TrimRange.swift` — **pure, TDD**: value type over `CMTime` —
  `clamped(start:end:duration:minimum: 0.5s)` (ordering, bounds, minimum length),
  `isNoOp(duration:tolerance:)` (full-range selection → Save buttons still work but skip
  export-with-timeRange), and the range-label formatting ("m:ss.t").
- `TrimmedFileName.swift` — **pure, TDD**: `name(forOriginal: "Recording X.mp4") →
  "Recording X (trimmed).mp4"` + collision uniquifier given an `exists` closure.
- `TrimExporter.swift` — async wrapper: `export(source: URL, range: CMTimeRange?, muted: Bool,
  to destination: URL) throws` — passthrough session, optional video-only composition,
  progress optional (v1: indeterminate spinner). Probe-style TestKit test: generate a tiny
  MP4 headlessly (AVAssetWriter writing a few solid-color frames — the same technique
  `ScreenRecorder` uses, minus SCK), trim it, assert output duration ≈ range and audio track
  absent when muted.
- `TrimWindowController.swift` — the window described above (AVKit `AVPlayerView`,
  `beginTrimming`, action bar). Callback seams: `onExported: (URL) -> Void`,
  `onCancelled: () -> Void`. Manual GUI verification per project norm.

### OverlayKit
- `QuickAccessActions` gains `onTrim: (() -> Void)? = nil`; `QuickAccessOverlayController`
  adds the scissors button to the recording row only when `onTrim != nil` (pattern matches the
  existing optional-action handling).

### App
- `RecordingCoordinator.presentQuickAccess(for:)` — pass `onTrim` for `.mp4` URLs → presents
  `TrimWindowController`; wire `onExported` → `presentQuickAccess(for: newURL)` (+ history add
  if v2.3 shipped). Retain the controller like `CaptureCoordinator.editorController`.
- No settings additions. No new hotkeys.

## Error handling

- `canBeginTrimming == false` (corrupt/unsupported file) → alert "This recording can't be
  trimmed", window stays open for playback only, Save buttons disabled.
- Export failure → HUD, original untouched (Replace uses the temp + atomic swap), window stays
  open so the user can retry.
- Source file deleted while the window is open → export fails with the same path; alert and
  close.
- Replace Original while the file is open in another app: `replaceItemAt` succeeds (POSIX
  semantics); note in checklist to verify QuickTime Player behavior.

## Testing

- **TestKit (automated)**: `TrimRange` clamp/minimum/ordering/no-op/label cases;
  `TrimmedFileName` naming + collisions; `TrimExporter` end-to-end on a generated MP4
  (duration ≈ trimmed range; muted export has zero audio tracks; passthrough export of a
  no-op range equals source duration).
- **Manual checklist (GUI)**: trim a real 30 s recording to 5 s and verify instant export +
  playable result; mute leaves video intact; Save as Copy naming + collision; Replace Original
  keeps the path valid for an open Quick Access card; cancel leaves no temp files; GIF card has
  no trim button; trim entry from a fresh recording's card; window resize; dark mode; export
  failure path (make the folder read-only).

## Build order (one plan)

1. **AVKit trim probe** (see Risks — go/no-go for the UI approach) → 2. `TrimRange` +
`TrimmedFileName` (TDD, pure) → 3. headless tiny-MP4 generator test fixture + `TrimExporter`
(TDD) → 4. `TrimWindowController` UI → 5. OverlayKit `onTrim` button + coordinator wiring →
6. Manual checklist, CHANGELOG, README, bump 2.5.0, tag `v2.5-trim`.

## Risks / probes for the implementing session

- **Probe first (plan Task 1):** AVKit's `AVPlayerView.beginTrimming` in a CLT-only SwiftPM
  app — verify `canBeginTrimming == true` for a `ScreenRecorder`-produced MP4 and that the
  selected range is readable from `reversePlaybackEndTime`/`forwardPlaybackEndTime`. P3 set the
  precedent: probe the OS capability before committing the design. **Fallback if the probe
  fails**: a custom two-handle range slider over an `AVPlayerView` without trim mode (a thin
  custom NSView — more work, same export pipeline; the spec's export/naming/pure-logic layers
  are unchanged either way).
- Passthrough exports cut on keyframes — the actual cut can land up to a GOP (~1-2 s at our
  encoder settings) from the requested point. Acceptable for v1 (CleanShot-grade precision
  would need re-encode); note it in the README line for the feature.
- `AVAssetExportSession` passthrough + composition (mute path) must be verified together in the
  `TrimExporter` test — if passthrough rejects compositions on some OS version, fall back to
  `AVAssetExportPresetHighestQuality` for the mute path only (re-encode acceptable for mute).
