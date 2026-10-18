# App/MenuBar — status-item menu & onboarding

- `MenuBarController.swift` — the `NSStatusItem` menu bar item: builds the menu (capture/record/history
  items), reflects recording state + elapsed-time in the icon, and adopts `NSMenuItemValidation`.
  Every item has an SF Symbol (macOS 26 adds a gear to "Settings…" by itself; icons on all items keep
  the titles aligned) — give any new item one too. **Help & Tours ▸** (`helpToursItem`, static so probes
  can build it without a status item): Take the Welcome Tour · one "<Name> Tour" per other `TourID`
  (`TourID.menuTitle`/`menuSymbol` in TourKit) · Reset All Tours → `onReplayTour` / `onResetTours`.
  The status item's button carries the tour anchor `menuBar.icon` (Welcome tour step 1); `iconWindow`
  (the button's window) is handed to `TourCoordinator.extraAnchorWindows` by `AppDelegate`.
- `OnboardingController.swift` — first-run onboarding flow, including prompting for the Screen Recording
  permission (works with `App/SystemIntegration/PermissionManager`). Fixed 440×380pt content for every
  state; the "You're all set!" shortcut grid comes from the live bindings via
  `CaptureKit/HotkeyCheatSheet` (injected as `bindings:` by `AppDelegate`), never hard-coded.
  **Tour question (spec §14.9):** for a *new* user who hasn't answered (`shouldAskTourQuestion`), that page
  replaces "Start Capturing" with "Want a quick tour?" · **No Thanks** (Esc) · **Show Me Around** (Return).
  Show Me Around re-renders the page without the question, then `onTourAnswer(true, window)` starts the
  Welcome tour over it; No Thanks or closing the window on the question → `onTourAnswer(false, …)`.
  Everyone else sees the page exactly as before. `show(_:)` posts `TourEvents.surfaceShown(.welcome)`.
  Welcome tour anchors: an empty view over just the grid's area / window / full-screen rows — the ones
  the tour's body names (`welcome.shortcuts`, added in `shortcutGrid`) — and Capture Area's keys label
  (`welcome.captureArea`); steps in `docs/MAC-TO-WINDOWS-PARITY-v3.md` §7.4.
  `render(_:askTourQuestion:)` is internal so probes can draw a page without showing the window.
- **Check for Updates…** (above Settings…) → `Updates.shared.checkForUpdates()`; menu validation renames it
  `Updates.actionTitle` ("Update Available (X)…" while a background find waits to be seen — the same label as
  the Settings button). The menu's delegate tracks `isMenuOpen` (the launch-at-login card waits while it's open).
- `LaunchAtLoginPromptController.swift` — "Open BetterScreenshot at login?", answered once, after the 5th
  completed screenshot (`CaptureCoordinator.onCaptureCompleted`), at a calm moment, on OverlayKit's
  `PromptCardController` card (top-right; bottom-right when Quick Access uses top-right; the window is made on
  the first showing). Every decision is a pure, tested step in CaptureKit `LaunchAtLoginPrompt`
  (`afterCapture`, `waitStep`, `shouldHideUnanswered`); this class only carries them out. Unanswered, the card
  hides after 25 s (not under the pointer) and returns after a later capture, ≤ 3 showings, then counts as "no".
  Launch at login found already on → marked asked (no status call on later captures). Left out of screenshots (`windowIDs` in `CaptureCoordinator.tourTagWindowIDs`)
  and recordings (registered with `TourTagRecordingGate`). Rules and keys: `docs/sparkle-updates/README.md`.

This is the app's primary always-on UI entry point. Verify by launching the built app and exercising
the menu.
