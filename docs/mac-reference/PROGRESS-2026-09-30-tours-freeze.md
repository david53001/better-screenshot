# Tour outline, Opacity tour, current-desktop windows, freeze screen — progress (2026-09-30)

All on `main` (commits `5764cc9`, `c3af088`, `70a1cf9`), pushed to GitHub, **not tagged, no version bump,
no CHANGELOG entry** (the CHANGELOG is written per release). Installed locally: `scripts/build-app.sh release`,
then `dist/BetterScreenshot.app` copied over `/Applications/BetterScreenshot.app` and relaunched (same
signing identity, so the Screen Recording permission is kept).

**Terms.** *Tour*: the guided walkthrough (red outline + red tag bubble) that points at real controls one
*step* at a time; each step points at an *anchor* (a view carrying an id like `editor.toolbar`, set with
`view.tourAnchor`). Background: `App/Tours/CLAUDE.md`. *Space*: a macOS desktop (Mission Control); an app in full
screen gets its own Space. *Freeze screen*: while choosing the area to capture, the user sees a still image of
the screen, and the screenshot is taken from that image.

## Owner requests (2026-09-30, dictated)
1. "The tour doesn't perfectly outline that pill or that box."
2. "There's no tour for the opacity — show the bar slowly going down and up so the user sees what it does."
3. "When you open the UI, open it in your current page" — read as: on the current desktop (Space).
4. "Freeze the screen when you take a screenshot, so you capture the exact moment."

## What was built
1. **Outline follows the control's shape** (`Packages/TourKit`): `NSView.tourOutline` (`TourAnchor.swift`)
   gives the rect + corner radius to outline — the view's layer radius or a same-size rounded background inside
   it (the editor tool pill's `HUDSurfaceView`, 15 pt); a padded `NSStackView` with no background (the editor
   side panel's sections) is outlined around its content, not its padding (it used to run along and past the
   panel edge). `TagStyle.boxRadius(anchorRadius:box:)` = radius + 4 (concentric), 6 for square controls, capped
   at a capsule. SwiftUI anchors pass it: `.tourAnchor(id, cornerRadius:)` — Settings' Keyboard Shortcuts card
   (10) and the History cell (12).
2. **Opacity tour step**: Settings tour step 3, anchor `settings.opacity` (the Appearance card's content). While
   it shows, `App/Settings/OpacityDemo.swift` sweeps the slider (hold → down to 0 → hold → up to 1 → hold →
   back → rest, loop; `OpacityDemoPath` in `Packages/DesignKit/Sources/DesignKit/OpacityDemo.swift`) through
   `SettingsStore.opacityPreview`, which the AppDelegate pushes into `UIOpacity.shared` — **never saved**. The
   step leaving puts the saved value back; dragging the slider or Default ends it and keeps the user's value.
   Driven by the new `TourCoordinator.onStepShown(anchor?)`. Settings tour version unchanged (1): existing
   first-use-tour users aren't re-shown the tour; replay it from the menu bar → Help & Tours → Settings, or
   Settings' ⓘ.
3. **Windows open on the current desktop** (`App/Lifecycle/WindowPlacer.swift`): every window gets
   `.moveToActiveSpace`; fixed-size ones (Settings, Welcome) also `.fullScreenAuxiliary` (they can show over a
   full-screen app). The remembered windows (editor, History, video editor) keep `.fullScreenPrimary` instead,
   so they can't open *on top of* a full-screen app's Space. A window still open on another desktop is moved here
   and re-centred under the pointer.
4. **Freeze screen** (area screenshot and Capture Text): `CaptureCoordinator.presentFrozenSelection` grabs every
   display first (`CaptureService.freezeDisplays`, ~210 ms cold on the 14″ MacBook), the selection overlay shows
   the still (`SelectionOverlayController.present(frozen:)`) and the shot is cut from it (`FrozenScreen.crop`,
   the same maths as the live area capture). If the freeze fails, it falls back to the live screen. Recording's
   area selection is unchanged.

## Verified
- `scripts/test.sh`: DesignKit 9, CaptureKit 122, OverlayKit 50, EditorKit 155, RecordingKit 92, HistoryKit 41,
  TourKit 119 — all pass. Release build signed with the stable identity.
- Outline: a throwaway probe (scratchpad, not in the repo) rendered the editor + tag overlay at desktop level
  behind all windows: the tool pill's outline is now concentric, side-panel sections are outlined inside the
  panel.
- Freeze: a headless probe froze the display and its crop matched the live area capture's size (600 × 400 px
  for 300 × 200 pt).

## Not verified (needs the owner's hands)
- The Opacity demo in the real Settings window (SwiftUI, App target — not probed).
- Freeze screen end to end (the overlay covers the whole screen, so it wasn't driven headlessly).
- Opening on the current desktop with several Spaces / a full-screen app.
- Windows port (`windows-port` branch): the outline + Opacity step are in `docs/MAC-TO-WINDOWS-PARITY-v3.md`
  (§ outline box, Settings tour table); window Spaces and freeze screen are not in the parity doc yet.
