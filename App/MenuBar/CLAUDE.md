# App/MenuBar — the app's menus, onboarding, the launch-at-login card

- `MenuBarController.swift` — since 3.3.0 (a Dock app, no status item) it builds the **main menu**
  (`NSApp.mainMenu`, at the top while the app is in front): BetterScreenshot (About · Open at Login… ·
  Check for Updates… · Settings… ⌘, · Hide ⌘H / Hide Others ⌥⌘H / Show All · Quit ⌘Q) · **Capture** (Capture
  Area / Window / Full Screen / Text · Record Screen… ↔ Stop Recording · Pause ↔ Resume Recording, shown only
  while recording · Pin from Clipboard · History… · Restore Recently Closed) · Edit (standard Undo/Redo/Cut/
  Copy/Paste/Delete/Select All, through the responder chain) · Window (`NSApp.windowsMenu`) · Help (the Help &
  Tours items, `NSApp.helpMenu`); and the **Dock menu** (`dockMenu()`, made fresh each time for
  `AppDelegate.applicationDockMenu`: the Capture items · Help & Tours ▸ · Open at Login… · Check for Updates… ·
  Settings…; the Dock adds Options/Show All Windows/Hide/Quit itself; state set explicitly, hidden items
  removed). Same targets for both. State that changes (Record/Stop, Pause/Resume, Open at Login…, the
  Updates title) is applied in `refresh` (`menuNeedsUpdate` and `dockMenu`), enabling in `isEnabled`
  (validation): Pin needs an image on the clipboard, Restore needs something closed, Updates
  `canCheckOrShow`. **Key equivalents:** the Capture items show the live bindings (`refreshKeyEquivalents`,
  from `AppDelegate.applyBindings`), but firing stays Carbon (`HotKeyManager`), which takes the keystroke even
  while we're in front; `fromCarbonHotkey` makes an item ignore a keyDown that is its own registered combo,
  so nothing can fire twice, while a combo macOS refused (`unregistered`) still works from the menu. Capture
  Window from a menu passes `skippingOwnWindows: true` (the user's window, not our Settings in front of it).
  `setRecording` puts the elapsed time on the Dock icon (`NSApp.dockTile.badgeLabel`; RecordingKit
  `RecorderState.badgeString`, "⏸ 1:23" while paused), cleared on stop.
  `isMenuOpen` follows `NSMenu.didBegin/EndTrackingNotification` for any of our menus (the Dock menu is the
  Dock's and can't be seen). Every capture/app item has an SF Symbol (macOS 26 adds a gear to "Settings…" by
  itself; icons on all items keep the titles aligned) — give any new item one too. **Help & Tours ▸**
  (`helpToursItem`, static so probes can build it): Take the Welcome Tour · one "<Name> Tour" per other
  `TourID` (`TourID.menuTitle`/`menuSymbol` in TourKit) · Reset All Tours → `onReplayTour` / `onResetTours`.
- `OnboardingController.swift` — first-run onboarding flow, including prompting for the Screen Recording
  permission (works with `App/SystemIntegration/PermissionManager`). Fixed 440×380pt content for every
  state; the "You're all set!" shortcut grid comes from the live bindings via
  `CaptureKit/HotkeyCheatSheet` (injected as `bindings:` by `AppDelegate`), never hard-coded.
  **Tour question (spec §14.9):** for a *new* user who hasn't answered (`shouldAskTourQuestion`), that page
  replaces "Start Capturing" with "Want a quick tour?" · **No Thanks** (Esc) · **Show Me Around** (Return).
  Show Me Around re-renders the page without the question, then `onTourAnswer(true, window)` starts the
  Welcome tour over it; No Thanks or closing the window on the question → `onTourAnswer(false, …)`.
  Everyone else sees the page exactly as before. `show(_:)` posts `TourEvents.surfaceShown(.welcome)`.
  Welcome tour anchors: the "lives in your Dock" line (`welcome.dock`, step 1 — the Dock itself is another
  process's window), an empty view over just the grid's area / window / full-screen rows — the ones
  the tour's body names (`welcome.shortcuts`, added in `shortcutGrid`) — and Capture Area's keys label
  (`welcome.captureArea`); steps in `docs/MAC-TO-WINDOWS-PARITY-v3.md` §7.4.
  `render(_:askTourQuestion:)` is internal so probes can draw a page without showing the window.
- **Check for Updates…** (above Settings…) → `Updates.shared.checkForUpdates()`; `refresh` renames it
  `Updates.actionTitle` ("Update Available (X)…" while a background find waits to be seen — the same label as
  the Settings button). `isMenuOpen` (the launch-at-login card waits while one of our menus is open);
  **Open at Login…** (above Check for Updates…, App menu and Dock menu) shows only while the launch-at-login
  question is due (`offersLoginQuestion` → `LaunchAtLoginPromptController.offersMenuItem`; action
  `askFromMenu`: the question as a standard `NSAlert`, the card's keyboard path).
- `LaunchAtLoginPromptController.swift` — "Open BetterScreenshot at login?", answered once, after the 5th
  completed screenshot (`CaptureCoordinator.onCaptureCompleted`), at a calm moment, on OverlayKit's
  `PromptCardController` card (top-right; bottom-right when Quick Access uses top-right; the window is made on
  the first showing). Every decision is a pure, tested step in CaptureKit `LaunchAtLoginPrompt`
  (`afterCapture`, `waitStep`, `Showing`, `cardHidUnanswered`, `fullScreenInFront`; each step applies its own
  side effects); this class only reads system state (occlusion, active Space, input idle time, the window list)
  and carries them out. Unanswered, the card hides after 25 s (not under the pointer); only a showing the user
  could have seen counts (visible on the active Space + input since it appeared, ≥ 5 s); a counted one returns
  after a capture ≥ 24 h later (a relaunch, e.g. by an automatic update, doesn't shorten that), ≤ 3, then counts
  as "no"; an unseen one after ≥ 10 min. The "One more step" / error cards hide after 25 s too. Never while
  something full-screen is in front (`fullScreenInFront` with each screen's notch inset,
  `NSScreen.safeAreaInsets.top`): AppKit **does** show the card on another app's full-screen Space (checked
  2026-10-18, macOS 26.7.1), so this wait is what keeps it off. While the question is due the menus have
  **Open at Login…** (`askFromMenu`, an `NSAlert`: Return = Open at Login, Escape = No Thanks), the keyboard path.
  Launch at login found already on → marked asked (no status call on later captures). Left out of screenshots (`windowIDs` in `CaptureCoordinator.tourTagWindowIDs`)
  and recordings (registered with `TourTagRecordingGate`). Rules and keys: `docs/sparkle-updates/README.md`.

These menus and the Dock icon are the app's always-on UI entry points. Verify by launching the built app
and exercising the main menu and the Dock menu (a headless probe can dump both: build the App sources
without `Main.swift` in a scratch copy, `NSApp.setActivationPolicy(.prohibited)`, construct
`MenuBarController`, print `NSApp.mainMenu` / `dockMenu()` — `docs/dock-app/PROGRESS.md`).
