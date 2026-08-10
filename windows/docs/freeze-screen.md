# Freeze the screen while selecting — implementation note

Taking a screenshot of a full-screen game captured the wrong thing: pressing the shortcut showed the selection
overlay, the overlay stole focus, the game reacted by pausing to its menu, and the capture — taken *after* the
drag, from the live screen — got the menu instead of the frame the user was looking at. The fix is to stop
capturing late. `Overlays/FrozenScreen.cs` BitBlts every monitor the instant the shortcut fires, *before* any
overlay window exists and so before anything has lost focus; the selection and window-picker overlays paint their
monitor's still as their backdrop, and the capture is cropped out of that still rather than re-grabbed. New
setting `CaptureSettings.FreezeScreen` (persisted key `freezeScreen`, **default on**), toggled in
**Settings → Capture**.

It applies to **Capture Area**, **Capture Text** and **Capture Window**. `CaptureFullscreen` needs nothing — it
shows no overlay, so nothing changes between the keypress and the grab. Recording target-picking passes
`freeze: false` deliberately: only the *rectangle* matters there and the recording itself is live, so selecting
against a stale still would misrepresent what is about to be recorded.

Three details are load-bearing:

- **Frozen overlays go opaque** (`OverlayHelpers.MakeOpaque`, flipping `AllowsTransparency` off in the
  constructor — WPF rejects that change once the HWND exists). Not cosmetic: a layered/transparent window gets no
  hardware acceleration, so repainting a 4K still on every mouse-move while dragging a selection would crawl.
  Windows 11 also rounds top-level window corners, which on a screen-filling overlay leaks four notches of the
  *live* desktop through the still — suppressed with `DWMWA_WINDOW_CORNER_PREFERENCE`
  (`OverlayHelpers.SquareOffCorners`).
- **The still is laid out at its own pixel size ÷ DPI scale**, anchored top-left, not stretched to the window. On
  a rig whose real framebuffer is smaller than the monitor's reported bounds (a stretched resolution — see
  `Screens.RealFramebufferSize`) stretching would visibly skew the frozen picture. Cropping goes through the pure,
  unit-tested `SelectionMath.ToSnapshotRect`, which subtracts the monitor origin, rounds exactly the way the live
  `ScreenCapture.CaptureRegion` does (so both paths agree on the output size) and clamps to the still.
- **Every crop is a fallback, never a failure.** A null crop — no still for that monitor, the rect outside it, a
  window spanning two screens — falls straight through to the previous live capture. With the setting off the
  behaviour is byte-for-byte what it was before.

`WindowPickerWindow` also now enumerates windows in its **constructor** instead of in `SourceInitialized`, i.e.
before the overlay is shown. A game that minimises itself on deactivation used to drop out of the list
(`IsIconic`) and become unpickable, and in freeze mode the list has to describe the same desktop the still froze.
The picked window's pixels come from the frame that was enumerated at that moment, so a window that has since
moved or closed still yields what the user saw.

`FrozenScreen.Crop` copies the cropped pixels into a frozen `WriteableBitmap` rather than returning the
`CroppedBitmap` itself — a `CroppedBitmap` is only a window onto its source, so returning it would pin the whole
full-screen still (up to ~33 MB on 4K) in memory for as long as the capture lives on in the Quick Access card,
history, a pin or the editor.

**Known trade-off:** with freeze on, Capture Window crops what was *visibly* on screen instead of `PrintWindow`-ing
the window's own content, so picking a window that is buried behind another captures the one on top. That is the
honest reading of "freeze"; turning the setting off restores the `PrintWindow` behaviour, which can still capture
occluded windows.

## Verification

Build clean (0 warnings / 0 errors), 301 tests green — 6 new covering `SelectionMath.ToSnapshotRect` (origin
subtraction, rounding, clamping to a short framebuffer, miss → null) and the `FreezeScreen` settings round-trip.
Because the real failure modes are all runtime, a scratch harness drove the actual overlay windows with
synthesized `SendInput`:

1. **Area** — painted the screen red, froze, painted it blue, then dragged a selection. The capture came back
   **red** while a live capture of the same rect was blue; the region was exact (375×270 at the requested point).
2. **Picker** — showed the picker over a green window running in a *separate process*, **killed that process**,
   then clicked where it had been. The pick returned its green pixels at the exact frame size — something a live
   `PrintWindow` of a dead HWND could never do.
3. **Freeze off** — the overlay stayed `AllowsTransparency=True`, carried no crop, and the live capture returned
   the current (blue) screen: the old path, unchanged.

Then `dist/` was republished and the tray agent relaunched.
