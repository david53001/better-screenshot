# App/Lifecycle — app entry & wiring

Bootstrap and lifecycle for the Dock app (a regular app since 3.3.0; no `LSUIElement`).

- `Main.swift` — process entry; creates the `NSApplication` and installs `AppDelegate`.
- `AppDelegate.swift` — owns and wires the app's coordinators (capture, recording, history, tours),
  registers global hotkeys, and runs terminate/cleanup hooks (e.g. restoring native screenshot
  shortcuts on quit). **Its very first line classifies the tour audience**
  (`TourCoordinator.classifyAudienceIfNeeded`, spec §14.9) — keep it above anything that writes a
  preference (Sparkle's `SU*` keys, window frames…), or every new user would look like an existing
  one. (The only line above it reads the launch's Apple Event, `LaunchAtLogin.launchedAsLoginItem`, which must
  be read while this method runs; it writes nothing.) (`didRegisterLaunchAtLogin` is no longer written: ≤ 3.1.0's silent launch-at-login enable
  was replaced by `App/MenuBar/LaunchAtLoginPromptController.swift`; the flag is only read.) Built with
  `-DSPARKLE_E2E_TEST` (only by `scripts/sparkle-e2e-test.sh`) it starts nothing but the updater and never
  restores the native shortcuts on quit. The `TourCoordinator`'s `makePresenter:` is `RecordingSafeTagPresenter`
  (`App/Recording/TourTagRecordingGate.swift`): TourKit's `TagOverlayController` with its windows registered
  so a tour tag never shows up in a screen recording — keep it that way.
  **Dock app (3.3.0):** the launch window is CaptureKit `LaunchWindowPolicy` (setup without Screen Recording ·
  Welcome after the permission relaunch / for an unasked new user · Settings · nothing at login);
  `applicationShouldHandleReopen` (Dock click, or opening the app again) shows Settings when none of our titled,
  non-panel windows is up; `applicationDockMenu` → `MenuBarController.dockMenu()`;
  `applicationShouldTerminateAfterLastWindowClosed` → false (⌘Q quits). The e2e build stays `.accessory` and
  its test copies get `LSUIElement` from `scripts/sparkle-e2e-test.sh`.
- `Updates.swift` — Sparkle 2 (`SPUStandardUpdaterController`, started in `applicationDidFinishLaunching`):
  gentle reminders (as a Dock app Sparkle shows a scheduled find at an opportune moment, e.g. when the app is
  brought forward), `pendingVersion` drives the menus' and Settings' one label `actionTitle` ("Update Available (X)…" / "Check for Updates…"). Feed/key
  in `App/Info.plist`; `docs/sparkle-updates/README.md`.
- `SparkleE2EUI.swift` — compiled only with `-DSPARKLE_E2E_TEST`, active only with `SPARKLE_E2E_UI=1`
  (`E2E_UI=1 scripts/sparkle-e2e-test.sh`): clicks through Sparkle's real update windows (transparent, so
  nothing shows on screen) and logs focus / menu title / user-attention, to test the production UI path.
- `WindowPlacer.swift` — every app window goes through `WindowPlacer.place(window, rememberAs:)` right
  before it's shown: exactly centred on the screen under the pointer; resizable windows (keys
  `annotate`, `editVideo`, `history` → UserDefaults `windowPlacement.<key>`) reopen at the last closed
  size, covering the screen, or in full screen. Pure maths + tests: CaptureKit `WindowPlacement`. Don't
  call `NSWindow.center()` for app windows (it sits a third of the way down) — use this.

These files are the glue layer: they instantiate the controllers defined in the sibling `App/*`
sections and connect them to the `Packages/*` modules. Behavior change here affects startup and
shutdown ordering — verify by launching `dist/BetterScreenshot.app` after `scripts/build-app.sh`.
