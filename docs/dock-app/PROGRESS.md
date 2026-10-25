# Dock app conversion — progress (v3.3.0, build 13)

Written for a fresh session with no context. BetterScreenshot (a local CleanShot X clone, SwiftPM, CLT only)
stops being a **menu-bar agent** (`LSUIElement` in `App/Info.plist` + an `NSStatusItem`) and becomes a normal
**Dock app**: Dock icon, its own main menu at the top of the screen while it's in front, a Dock right-click
menu. Owner-approved brief, 2026-10-25; built overnight by an agent.

- Worktree: `~/Desktop/Home/Projects/Code/BetterScreenshot/.claude/worktrees/dock-app`, branch
  `feat/dock-app`, off `main` 4009a6b (= released v3.2.0 + an install.sh tweak). Not merged, not pushed,
  not installed, not released.
- Build rules on this Mac (fanless 16 GB Air, another agent builds in parallel): wrap every build/test in
  `lockf -k /private/tmp/claude-501/-Users-davidghermansteinberg/d86e55d5-4394-4ba0-83b9-8af7adc4ab0e/scratchpad/build.lock <cmd>`
  (that scratch path only exists for that session; any shared lock file works). `scripts/sdk-env.sh` pins the
  26.5 SDK (the 27.0 SDK breaks SwiftUI macros).
- Never touched: bundle id `com.betterscreenshot.mac`, signing (designated requirement still
  `certificate leaf = H"08faa1f9…"`), Sparkle feed/keys, settings keys, `windows/`.

## STATUS
**Done, verified headless; needs the live checks below on the real installed app before release.**
`scripts/build-app.sh release` assembles + signs `dist/BetterScreenshot.app` (exit 0; no `LSUIElement` in the
bundle's Info.plist; 3.3.0 / 13; `codesign --verify --deep --strict` OK). `scripts/test.sh`: all suites pass —
DesignKit 10/10, CaptureKit 164/164 (13 new), OverlayKit 50/50, EditorKit 155/155, RecordingKit 93/93 (1 new),
HistoryKit 41/41, TourKit 119/119 (632 total). Re-run 2026-10-26 after the review fixes (section below).

## Review fixes (2026-10-26, after an independent review found no serious defects)
1. Dock click: `LaunchWindowPolicy.reopen` (pure, tested) — app hidden → `NSApp.unhide` (while hidden every
   window reports not visible); a titled non-panel window visible → AppKit brings the app forward; only a
   minimized one (e.g. ⌘M) → `deminiaturize` it; nothing → Settings.
2. Dock badge while paused: `RecorderState.badgeString` → "⏸ 1:23" (the menu/pill text "Paused · 1:23" was
   too wide for the badge); `onStateChange` now carries the badge text.
3. After the Settings shortcut recorder ends, `applyBindings()` re-registers (was `hotKeys.resume()`), so
   the menu's shortcuts and its refused-combo list (`unregistered`) are refreshed too.
4. Capture Window from a menu also needs `windowLayer == 0`; no window found (any path) → HUD "No window to
   capture" instead of nothing.
5. Session restore: `notification.userInfo[NSApplication.launchIsDefaultUserInfoKey] == false` (macOS
   relaunching the app for "Reopen windows when logging back in", maybe without the login-item flag) opens no
   window, like a login launch; setup and Welcome-after-the-grant still show. Logged at launch:
   `BetterScreenshot launch: login item N, default launch N` (`log show --predicate 'process ==
   "BetterScreenshot"' --last 5m | grep "launch:"`).
6. Opened as a login item while our `SMAppService` login item is off (the Dock's Options ▸ Open at Login, or a
   Login Items entry added by hand) → the one-time launch-at-login question is marked answered.

## What changed (file map)
- `App/Info.plist` — no `LSUIElement`; 3.3.0, build 13.
- `App/MenuBar/MenuBarController.swift` — no status item. Builds the **main menu** (BetterScreenshot: About ·
  Open at Login… (only while due) · Check for Updates… · Settings… ⌘, · Hide ⌘H · Hide Others ⌥⌘H · Show All ·
  Quit ⌘Q — **Capture**: Capture Area/Window/Full Screen/Text · Record Screen… ↔ Stop Recording · Pause ↔
  Resume (only while recording) · Pin from Clipboard · History… · Restore Recently Closed — **Edit**: Undo,
  Redo, Cut, Copy, Paste, Delete, Select All — **Window**: Minimize ⌘M, Zoom, Close ⌘W, Bring All to Front —
  **Help**: the Help & Tours items) and the **Dock menu** (`dockMenu()`: the Capture items · Help & Tours ▸ ·
  Open at Login… · Check for Updates… · Settings…; the Dock adds Options/Show All Windows/Hide/Quit itself).
  Same targets, same validation (Pin needs a clipboard image, Restore needs something closed, Updates title
  and enabling from `Updates.shared`). The Dock menu is built fresh each time with explicit state.
- **Key equivalents / double fire:** the Capture items show the live bindings. Carbon `RegisterEventHotKey`
  still fires them (it takes the keystroke at the window server, also while we're in front). As a guard,
  `fromCarbonHotkey(action)` makes an item ignore a keyDown that equals its own *registered* combo, so even if
  AppKit ever saw that keystroke too nothing runs twice; a combo macOS refused (`settings.failedActions`,
  passed as `unregistered`) still works from the menu. The Settings shortcut recorder's local key monitor
  swallows keystrokes before menus see them, so rebinding still works. Proven in the probe (below):
  registered → 0 runs from the menu, refused → 1.
- `App/Lifecycle/AppDelegate.swift` — no `.accessory` policy; `applicationShouldHandleReopen` (Dock click or
  opening the app again): Settings when none of our titled, non-panel windows is visible, else default;
  `applicationDockMenu`; `applicationShouldTerminateAfterLastWindowClosed` → false. Launch window via
  CaptureKit `LaunchWindowPolicy` (pure, tested): no Screen Recording → setup; relaunch after the grant or a new
  unasked user → Welcome; else Settings — **unless macOS opened the app at login: no window**.
- `App/SystemIntegration/LaunchAtLogin.swift` — `launchedAsLoginItem`: the open-application Apple Event's
  `keyAEPropData == keyAELaunchedAsLogInItem` (the exact check sindresorhus/LaunchAtLogin-Modern ships for
  `SMAppService.mainApp`); read first thing in `applicationDidFinishLaunching`.
- Recording: `MenuBarController.setRecording` puts the elapsed time on the Dock icon
  (`NSApp.dockTile.badgeLabel`), nil when stopped. Stop paths: Dock menu, Capture menu, the hotkey, the
  floating pill.
- `CaptureCoordinator.captureFrontWindow(skippingOwnWindows:)` — from a menu (Dock or main) it skips windows
  owned by our PID, so it captures the user's window instead of our Settings/History/editor window that is in
  front while our main menu is used. The hotkey path is unchanged (captures whatever window is in front, ours
  included, as before).
- `Packages/OverlayKit/…/SelectionOverlayController.swift` — `KeyableOverlayWindow` (selection overlay +
  window picker) is now a **non-activating `NSPanel`** with `[.canJoinAllSpaces, .fullScreenAuxiliary]` and
  `hidesOnDeactivate = false` (see RISKS 1). It still calls `NSApp.activate` (crosshair cursor rects need an
  active app; Escape would work without).
- Floating panels (Quick Access, pins, HUD, record strip, recording pill, countdown, camera bubble, click and
  keystroke overlays): `canHide = false` (a Dock app can be hidden with ⌘H or another app's Hide Others — the
  camera bubble/click highlights would vanish from a recording), and `hidesOnDeactivate = false` where it was
  still `NSPanel`'s default `true` (strip, camera, keystrokes, clicks — a Dock app deactivates far more often).
- Tours: Welcome step 1 is now `welcome.dock` → the "BetterScreenshot lives in your Dock. Capture any time
  with:" line on the Welcome page — "Your Dock icon" / "Click it for Settings. Right-click it for captures,
  recordings, History and more." (TagFit + lint tests pass). `TourCoordinator.extraAnchorWindows` is no longer
  set.
- Launch-at-login card: `MenuBarController.isMenuOpen` now follows `NSMenu.didBegin/EndTrackingNotification`
  (any of our menus). The Dock menu is drawn by the Dock process and can't be observed (it's at the bottom; the
  card is top-right).
- `scripts/sparkle-e2e-test.sh` — its test copies get `LSUIElement` so they never appear in the Dock.
- Copy: onboarding, Settings ⓘ texts (Launch at login, Tours & tips), History empty state no longer say "menu
  bar". CHANGELOG v3.3.0 (unreleased). Briefs (`CLAUDE.md`s), parity doc §7.4 (Windows keeps the tray step),
  Sparkle README note.

## How it was verified headless (repeatable)
Menu probe (not in the repo): rsync the worktree (minus `.build`, `dist`, `windows`, `.git`, `docs`) to a
scratch folder, delete `App/Lifecycle/Main.swift`, add an `@main` that calls
`NSApp.setActivationPolicy(.prohibited)` (no Dock icon, nothing on screen), builds `SettingsStore`,
`CaptureCoordinator`, `SettingsWindowController`, `MenuBarController`, prints `NSApp.mainMenu` and `dockMenu()`
recursively (title, key equivalent, hidden, enabled), flips recording/paused/login-due, posts + dispatches a
synthetic ⇧⌘5 keyDown to test the double-fire guard, and prints `LaunchAtLogin.launchedAsLoginItem`. Run the
binary under a **different name** (e.g. copy to `DockProbe`) so its `UserDefaults` domain isn't the
pre-existing `~/Library/Preferences/BetterScreenshot.plist`. Result 2026-10-25: every old status-menu item
present in both menus, Pause/Open at Login… hidden/shown correctly, Record ↔ Stop, Pause ↔ Resume, badge
"0:05" then nil, guard 0 / 1, `launchedAsLoginItem` false for a shell launch.

## NEXT STEPS (for the main session / owner)
1. Install the build (`scripts/install.sh` path or the usual) and do the **LIVE CHECKS** below.
2. If all good: merge `feat/dock-app` → `main`, release 3.3.0 per `docs/sparkle-updates/README.md`.

## LIVE CHECKS (could not be done without showing UI)
1. **Full-screen apps (most important):** with Safari/Keynote in full screen, ⌘⇧4 (Capture Area) and Capture
   Text: the overlay shows on that Space, crosshair cursor, Esc cancels, no jump to a desktop; also with our
   Settings window open on another desktop. Capture Window / Full Screen there. Record (strip, countdown, pill,
   camera bubble, click highlights) over a full-screen app. Quick Access card + pin over a full-screen app.
2. Dock icon present; **click** → Settings; click again with Settings closed → Settings; with the editor open →
   just comes forward. Launch from Finder/Spotlight → Settings. First run without permission → onboarding.
3. **Right-click Dock icon**: all items, state (Pin greyed without a clipboard image, Restore greyed with
   nothing closed, Pause only while recording, Stop Recording title, Update Available title), each one works.
   Confirm the Dock re-asks for the menu each time (state is fresh) and shows the submenu.
4. **Main menu** while in front: same; capture shortcuts shown (also after rebinding one in Settings; cleared
   binding shows none); pressing a capture shortcut while BetterScreenshot is in front fires **once** (Record:
   strip opens and stays). ⌘, ⌘W ⌘M ⌘H ⌘Q; ⌘C/⌘V/⌘A/⌘Z in a Settings text field and in the editor's text box;
   editor ⌘Z/⌘⇧Z/⌘+/⌘0 still the editor's.
5. **Capture Window from the Capture menu** (Settings in front, Safari behind) → Safari's window. From the
   Dock menu while Safari is in front → Safari's window.
6. **Login:** turn on Launch at login, log out/in → Dock icon, **no window**. (If a window appears, the Apple
   Event check doesn't fire for `SMAppService.mainApp` on this macOS — see RISKS 3; the launch log line says
   which flag was seen.) Also **restart with "Reopen windows when logging back in" ticked** while the app is
   running (launch at login off) → it comes back with no window.
   **Dock's Options ▸ Open at Login** (with our Settings switch off): log out/in → no window, and the
   one-time "Open at login?" card never appears afterwards.
7. Closing Settings/History/editor never quits; hotkeys keep working with no windows. Dock click with only a
   minimized window (⌘M the editor) → it comes back, Settings doesn't open; with the app hidden (⌘H) → it
   unhides, Settings doesn't open.
8. **Recording badge**: elapsed time on the Dock icon, ticking; "⏸ 0:17" while paused, fully visible; gone
   after stop.
9. ⌘H (and Hide Others from another app) leaves Quick Access cards, pins, the recording pill and camera bubble
   on screen; Settings/editor hide.
10. Welcome tour (Help → Take the Welcome Tour): step 1 outlines the "lives in your Dock" line.
11. Launch-at-login card still appears after the 5th screenshot (calm moment) and not while our main menu is
    open.
12. Sparkle: Check for Updates… from both menus brings the window forward; a scheduled find shows when the app
    is brought forward and the menu reads "Update Available (X)…" meanwhile.
13. Cmd-Tab lists BetterScreenshot (expected).

## RISKS / DECISIONS
1. **Full screen.** Researched, not tested live: Apple DTS (Developer Technical Support; developer.apple.com/forums/thread/826308) says macOS doesn't layer a
   *regular* app's windows above other apps' full-screen Spaces; Electron hides the Dock icon for
   `visibleOnFullScreen` ("Apple changed … starting with 10.14 to disallow NSWindows from floating on top of
   fullscreen apps"); FunWithPanels shows a real non-activating `NSPanel` is the exception (it swizzles
   `NSWindow` into one to get there). All our floating surfaces already were such panels; the selection overlay
   and window picker were plain `NSWindow`s and are now panels. Still unknown: whether `NSApp.activate` of a
   regular app while its key panel sits on another app's full-screen Space keeps the user there (expected: yes,
   the app has a window on that Space). If live check 1 fails, the fallback is to not activate when a full-screen
   app is in front (Esc works on a key non-activating panel; the crosshair would need `NSCursor.set` instead of
   cursor rects).
2. **Windows over full-screen apps:** Settings/Welcome/editor/History are plain windows; up to 3.2.0 they could
   open on top of a full-screen app (`.fullScreenAuxiliary` in `WindowPlacer`). As a regular app macOS will
   most likely put them on a desktop (switching Spaces). Standard Dock-app behaviour; not changed.
3. **Login detection** relies on `keyAELaunchedAsLogInItem` in the launch Apple Event — what LaunchAtLogin-Modern
   uses with `SMAppService.mainApp`; not documented by Apple. A Sparkle "Install and Relaunch" relaunch shows
   Settings (it's not a login launch) — judged fine.
4. **Double fire** reasoned + probed (see Key equivalents). The live check 4 confirms Carbon wins while in front.
5. Floating panels don't count as "a window up" for a Dock click. `launchIsDefault == false` also covers other
   non-default launches (e.g. macOS opening the app to restore it): no window then either. If session restore
   also sets the login-item flag, a user restored at login with our login item off is marked as having answered
   the launch-at-login question (they already get relaunched at login).
6. The Settings tour (if Tours & tips is on and it's unseen) can now start when Settings opens at launch.
7. The hotkey Capture Window path still captures our own window if it's in front (unchanged); it now shows
   "No window to capture" when nothing qualifies.
8. Sparkle's scheduled-update timing changes for a regular app (Sparkle waits for an opportune moment). The
   e2e UI test (`E2E_UI=1 scripts/sparkle-e2e-test.sh`) still runs dockless copies, so it no longer tests the
   exact production activation policy. Not run tonight (it opens transparent windows and takes minutes).

## Dead code (mentioned, not deleted)
- `TourCoordinator.extraAnchorWindows` — no longer set by the app.
- TourKit `TagOverlayController` / `TagLayout` menu-bar-host branches (status-bar window, tag below a menu-bar
  icon) and their `TagLayoutTests` — only the old `menuBar.icon` step used them; the Windows port's tray step
  mirrors them.
- `App/Tours/NoOpTourTagPresenter.swift` was already unused.
