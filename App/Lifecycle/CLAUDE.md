# App/Lifecycle — app entry & wiring

Bootstrap and lifecycle for the menu-bar agent.

- `Main.swift` — process entry; creates the `NSApplication` and installs `AppDelegate`.
- `AppDelegate.swift` — owns and wires the app's coordinators (capture, recording, history, tours),
  registers global hotkeys, and runs terminate/cleanup hooks (e.g. restoring native screenshot
  shortcuts on quit). **Its very first line classifies the tour audience**
  (`TourCoordinator.classifyAudienceIfNeeded`, spec §14.9) — keep it above anything that writes a
  preference (status item, `didRegisterLaunchAtLogin`, window frames…), or every new user would look like
  an existing one. The `TourCoordinator`'s `makePresenter:` is `NoOpTourTagPresenter` until lane 7B's
  `TagOverlayController` is merged.
- `WindowPlacer.swift` — every app window goes through `WindowPlacer.place(window, rememberAs:)` right
  before it's shown: exactly centred on the screen under the pointer; resizable windows (keys
  `annotate`, `editVideo`, `history` → UserDefaults `windowPlacement.<key>`) reopen at the last closed
  size, covering the screen, or in full screen. Pure maths + tests: CaptureKit `WindowPlacement`. Don't
  call `NSWindow.center()` for app windows (it sits a third of the way down) — use this.

These files are the glue layer: they instantiate the controllers defined in the sibling `App/*`
sections and connect them to the `Packages/*` modules. Behavior change here affects startup and
shutdown ordering — verify by launching `dist/BetterScreenshot.app` after `scripts/build-app.sh`.
