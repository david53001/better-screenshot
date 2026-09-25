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

## Guided tours (v3 Part 7) — strip, pill, and tags kept out of recordings
Steps are data in `Packages/TourKit/Sources/TourKit/Catalog/RecordingTours.swift`; every step, anchor, event
and the exclusion mechanism are written up in `docs/MAC-TO-WINDOWS-PARITY-v3.md` §7.6. A **tour** is a
sequence of **steps**, each outlining one control (its **anchor**, `view.tourAnchor = "…"`) with a red tag;
an Explain step advances on Next, a **Try** step when the app posts the matching `TourEvents` event.
- **Strip** (`First recording` tour): anchors `strip.targets` (the three target buttons, grouped in their own
  stack just for this), `strip.format`, `strip.fps`, `strip.output` (Format + FPS, grouped in their own stack
  just for the tour's merged step — frames unchanged), `strip.microphone`, `strip.microphoneColumn`,
  `strip.systemAudio`, `strip.camera`, `strip.cursor`, `strip.hint`. The mic/system-audio anchors are removed
  in GIF mode (their menus are disabled), so those steps skip. Events: `menuOpened` from each dropdown menu's
  `menuWillOpen` (the strip is the menus' delegate), `choiceMade` from every choice, `choiceMade("strip.targets")`
  from Full Screen / Area… / Window… (before `on…` hides the strip — it hands over to the pill tour).
  `show()` ends with `TourEvents.surfaceShown(.recordStrip)`. The ⓘ (`InfoButton`) sits between FPS and ✕.
- **Pill** (`Recording pill` tour): anchors `pill.timer/mic/systemAudio/camera/switch/restart/discard/pause/
  collapse/stop`; `pill.mic` only while there's a mic track (set in `render`). `micTapped` posts
  `action("pill.micMuted")` when muting; `show()` ends with `surfaceShown(.recordingPill)`. No ⓘ. The pill's
  window is a `PillPanel` adopting TourKit's `TourHostShaping`: it reports the capsule (`pillFrame`, radius
  20) plus the hover-hint band above and below it, so a tour tag dims only the capsule and doesn't jump
  30 pt when a hovered control grows the window for its hint.
- **Coordinator:** `stop()` posts `action("recording.stopped")` first (every stop path); `begin` posts
  `action("recording.started")` once the engine runs.
- **Since the tours review (`docs/reviews/2026-09-26-tours-review.md`):** First recording is 6 steps and the pill tour 5 (4 without a mic
  track); the pill tour runs over a live recording, so its only Try step is Stop — "Mute the mic" is an
  Explain step and nothing waits for `pill.micMuted` any more. `pill.camera`, like `pill.mic`, is set in
  `render` only while the control can be used (no camera or no camera access → no anchor).
- **Tags are never recorded** (owner: not even one frame) — `TourTagRecordingGate.swift`: every display filter
  is built by `tagGate.displayFilter(…)`, which leaves out every tag window that exists (content fetched with
  `onScreenWindowsOnly: false`, so hidden ones are listed too); a tag window first shown after the filter was
  built stays alpha 0 until `refreshTagExclusion()` has updated the running stream's filter
  (`ScreenRecorder.updateFilter`, bracketed by `willUse`/`didUse`); `tearDownPanels()` ends the gate after the
  stream stops. `RecordingSafeTagPresenter` (same file) is the app's tag presenter (`AppDelegate`'s
  `makePresenter:`) — it registers the overlay's windows with the gate the moment they're created. **Any new
  display filter must go through `tagGate.displayFilter` and `willUse`/`didUse`**, or tags can leak into videos.
  Window recordings (single-window filter) never capture our windows.
- Verified by a headless probe compiled from the App sources (parity doc §7.6 "How it was verified"): a control
  clip shows a tag that isn't left out; a real recording with the pill tour running, a tag re-shown and a brand-new
  tag shown mid-recording has 0 % tour red in every tag region of every frame. Probe tips: park windows just above
  the desktop; add the other apps' windows to the probe's filter so the capture can see its low windows; **don't
  open real pop-up menus** (macOS 26 draws them on screen before a probe can hide them) — call the menu
  delegate's `menuWillOpen` instead.

Recording model + capture engine live in `Packages/RecordingKit`; this section is the app-side
orchestration and on-screen controls. Verify by recording in the built app.
