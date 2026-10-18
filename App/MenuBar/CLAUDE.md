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
  the Settings button). The menu's delegate tracks `isMenuOpen` (the launch-at-login card waits while it's open)
  and, in `menuNeedsUpdate`, shows **Open at Login…** (above Check for Updates…) only while the launch-at-login
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
  2026-10-18, macOS 26.7.1), so this wait is what keeps it off. While the question is due the menu has
  **Open at Login…** (`askFromMenu`, an `NSAlert`: Return = Open at Login, Escape = No Thanks), the keyboard path.
  Launch at login found already on → marked asked (no status call on later captures). Left out of screenshots (`windowIDs` in `CaptureCoordinator.tourTagWindowIDs`)
  and recordings (registered with `TourTagRecordingGate`). Rules and keys: `docs/sparkle-updates/README.md`.

This is the app's primary always-on UI entry point. Verify by launching the built app and exercising
the menu.
