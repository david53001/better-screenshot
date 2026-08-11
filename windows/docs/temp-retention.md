# Keep temp copies for — implementation note

Copying a capture, or dragging one out of the Quick Access card, writes a throwaway PNG into
`%TEMP%\BetterScreenshot-{guid}\` so other apps can take the capture *as a file* (clipboard file-drop /
drag-and-drop). That file was deleted on a hardcoded 5-minute timer (`TempFiles.PayloadLifetime`), which is too
short if you copy a screenshot and only paste it into an email, an upload box or a chat some minutes later — by
then the file-drop points at nothing. This change makes the lifetime a user setting: a slider in
**Settings → Temporary Files → "Keep temp copies for"**, **5 to 30 minutes**, default **5** (exactly the old
behavior, so nothing changes until the slider is moved).

- **`Capture/TempRetentionScale.cs`** (pure) owns the range: `MinMinutes = 5`, `MaxMinutes = 30`,
  `DefaultMinutes = 5`, plus `Clamp`, `PositionToMinutes` (rounds a slider double, then clamps) and `Label`
  ("5 min" … "30 min"). One tested place for the mapping, mirroring `OverlayDismissScale`, so the slider and the
  persisted int cannot drift apart.
- **`CaptureSettings.TempRetentionMinutes`** persists as `tempRetentionMinutes` and is **clamped on read**: a
  missing/zero legacy value or a hand-edited `settings.json` can never shorten the lifetime below the 5 minutes an
  in-flight drop needs, nor leave temp files lying around past the 30-minute end.
- **`Platform/TempFiles`** turns `PayloadLifetime` from a `static readonly TimeSpan` into a property over
  `RetentionMinutes`, set by `TempFiles.Configure(minutes)`. Both consumers — `ClipboardService.SetImage` and
  `CaptureCoordinator.ShowOverlayCard`'s drag file — keep reading `PayloadLifetime` unchanged, so one setting
  governs every temp payload. `Configure` is called from `App.OnStartup` (right after `SettingsStore.Load`, before
  any capture can run) and from `SettingsWindow.Apply` (instant-apply), the same wiring shape as
  `StartupRegistration.Reconcile`.
- **Settings UI**: a new `Temporary Files` `DarkSection` in column B under Save Location — a `Theme.Slider`
  (5..30, snap-to-integer, `IsMoveToPointEnabled`) with a live "5 min" readout and an InfoTip, matching the
  auto-dismiss bar's pattern.

A retention change takes effect from the next capture onward; deletions already scheduled keep the delay they were
scheduled with (they are in-flight `Task.Delay` continuations — re-arming them would mean tracking every pending
payload for no real benefit). Note the drag file's timer starts when the Quick Access **card is dismissed**, not
when the capture is taken, so a card left open (or set to "Never" auto-dismiss) keeps its temp file the whole time
and then the chosen number of minutes.

**Nothing here can lose a capture.** These are disposable copies; the screenshot itself lives in History under
`%APPDATA%\BetterScreenshot\History\`, a separate location that this cleanup never touches — which is why the
slider has no "forever" stop.

## Verification

Build clean (0 warnings / 0 errors), **336 tests green** (301 → 336, 35 new): `TempRetentionScaleTests` (range, clamping,
rounding, labels, lossless slider round-trip), `TempFilesTests` (default is still exactly 5 minutes; `Configure`
sets the clamped lifetime) and `CaptureSettingsTests` (the new field round-trips; out-of-range persisted values are
clamped on read). The settings window was rendered from the freshly built binary via `--ui-preview settings` and
PrintWindow: the **TEMPORARY FILES** card shows in column B with the slider at its 5-minute minimum and the
"5 min" readout. Then `dist/` was republished and the tray agent relaunched.
