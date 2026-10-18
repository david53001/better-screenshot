# App/Lifecycle — app entry & wiring

Bootstrap and lifecycle for the menu-bar agent.

- `Main.swift` — process entry; creates the `NSApplication` and installs `AppDelegate`.
- `AppDelegate.swift` — owns and wires the app's coordinators (capture, recording, history, tours),
  registers global hotkeys, and runs terminate/cleanup hooks (e.g. restoring native screenshot
  shortcuts on quit). **Its very first line classifies the tour audience**
  (`TourCoordinator.classifyAudienceIfNeeded`, spec §14.9) — keep it above anything that writes a
  preference (status item, Sparkle's `SU*` keys, window frames…), or every new user would look like
  an existing one. (`didRegisterLaunchAtLogin` is no longer written: ≤ 3.1.0's silent launch-at-login enable
  was replaced by `App/MenuBar/LaunchAtLoginPromptController.swift`; the flag is only read.) Built with
  `-DSPARKLE_E2E_TEST` (only by `scripts/sparkle-e2e-test.sh`) it starts nothing but the updater and never
  restores the native shortcuts on quit. The `TourCoordinator`'s `makePresenter:` is `RecordingSafeTagPresenter`
  (`App/Recording/TourTagRecordingGate.swift`): TourKit's `TagOverlayController` with its windows registered
  so a tour tag never shows up in a screen recording — keep it that way. `tours.extraAnchorWindows` returns
  the menu-bar status item's window (`MenuBarController.iconWindow`) so the Welcome tour's first step can
  point at the icon.
- `Updates.swift` — Sparkle 2 (`SPUStandardUpdaterController`, started in `applicationDidFinishLaunching`):
  gentle reminders (a background find opens Sparkle's window behind other apps), `pendingVersion` drives the
  menu's "Update Available (X)…" and Settings → Updates. Feed/key in `App/Info.plist`;
  `docs/sparkle-updates/README.md`.
- `WindowPlacer.swift` — every app window goes through `WindowPlacer.place(window, rememberAs:)` right
  before it's shown: exactly centred on the screen under the pointer; resizable windows (keys
  `annotate`, `editVideo`, `history` → UserDefaults `windowPlacement.<key>`) reopen at the last closed
  size, covering the screen, or in full screen. Pure maths + tests: CaptureKit `WindowPlacement`. Don't
  call `NSWindow.center()` for app windows (it sits a third of the way down) — use this.

These files are the glue layer: they instantiate the controllers defined in the sibling `App/*`
sections and connect them to the `Packages/*` modules. Behavior change here affects startup and
shutdown ordering — verify by launching `dist/BetterScreenshot.app` after `scripts/build-app.sh`.
