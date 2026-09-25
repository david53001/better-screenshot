# App/MenuBar — status-item menu & onboarding

- `MenuBarController.swift` — the `NSStatusItem` menu bar item: builds the menu (capture/record/history
  items), reflects recording state + elapsed-time in the icon, and adopts `NSMenuItemValidation`.
  Every item has an SF Symbol (macOS 26 adds a gear to "Settings…" by itself; icons on all items keep
  the titles aligned) — give any new item one too.
- `OnboardingController.swift` — first-run onboarding flow, including prompting for the Screen Recording
  permission (works with `App/SystemIntegration/PermissionManager`). Fixed 440×380pt content for every
  state; the "You're all set!" shortcut grid comes from the live bindings via
  `CaptureKit/HotkeyCheatSheet` (injected as `bindings:` by `AppDelegate`), never hard-coded.

This is the app's primary always-on UI entry point. Verify by launching the built app and exercising
the menu.
