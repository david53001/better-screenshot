# App/MenuBar — status-item menu & onboarding

- `MenuBarController.swift` — the `NSStatusItem` menu bar item: builds the menu (capture/record/history
  items), reflects recording state + elapsed-time in the icon, and adopts `NSMenuItemValidation`.
  Every item has an SF Symbol (macOS 26 adds a gear to "Settings…" by itself; icons on all items keep
  the titles aligned) — give any new item one too. **Help & Tours ▸** (`helpToursItem`, static so probes
  can build it without a status item): Take the Welcome Tour · one "<Name> Tour" per other `TourID`
  (`TourID.menuTitle`/`menuSymbol` in TourKit) · Reset All Tours → `onReplayTour` / `onResetTours`.
- `OnboardingController.swift` — first-run onboarding flow, including prompting for the Screen Recording
  permission (works with `App/SystemIntegration/PermissionManager`). Fixed 440×380pt content for every
  state; the "You're all set!" shortcut grid comes from the live bindings via
  `CaptureKit/HotkeyCheatSheet` (injected as `bindings:` by `AppDelegate`), never hard-coded.
  **Tour question (spec §14.9):** for a *new* user who hasn't answered (`shouldAskTourQuestion`), that page
  replaces "Start Capturing" with "Want a quick tour?" · **No Thanks** (Esc) · **Show Me Around** (Return).
  Show Me Around re-renders the page without the question, then `onTourAnswer(true, window)` starts the
  Welcome tour over it; No Thanks or closing the window on the question → `onTourAnswer(false, …)`.
  Everyone else sees the page exactly as before. `show(_:)` posts `TourEvents.surfaceShown(.welcome)`.
  `render(_:askTourQuestion:)` is internal so probes can draw a page without showing the window.

This is the app's primary always-on UI entry point. Verify by launching the built app and exercising
the menu.
