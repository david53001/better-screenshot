# App/SystemIntegration — ⚠️ OS-integration & permission surface (SECURITY-SENSITIVE)

This section concentrates the code that touches macOS privacy/permission controls, global input, the
user's system preferences, and login-item registration. Treat changes here with extra care: review
against the diff-level security checklist, and never weaken or bypass a permission gate.

## Files
- `PermissionManager.swift` — Screen Recording (**TCC**, Transparency/Consent/Control) permission.
  Preflight (`CGPreflightScreenCaptureAccess`), prompt (`CGRequestScreenCaptureAccess`), deep-link to
  System Settings, and a relaunch helper (grants only take effect at process start). The relaunch
  passes the bundle path as `$0` (never interpolated into the shell string) — keep it that way.
- `HotKeyManager.swift` — global hotkeys via Carbon `RegisterEventHotKey` (deliberately avoids the
  Accessibility/event-tap prompt). Registers/unregisters bound combos; reports combos macOS refused.
- `ShortcutRecorderField.swift` — custom keybind-capture UI (records a new combo; suspends global
  hotkeys while recording so currently-bound combos can be re-typed).
- `SystemScreenshotShortcuts.swift` — disables/restores the **user's** native macOS screenshot
  shortcuts (⌘⇧3 / ⌘⇧4 / ⌘⇧5) by editing the `com.apple.symbolichotkeys` preferences domain and reloading
  via a private `activateSettings` helper. Restore is crash-safe (removes our entries to revert to
  defaults).
- `LaunchAtLogin.swift` — login-item (launch-at-login) registration via `SMAppService.mainApp` (`isEnabled`,
  `needsApproval` = `.requiresApproval`, `setEnabled` → returns the resulting status, marks the one-time
  question answered and posts `didChangeNotification`; `openSystemSettings()` → Login Items). Never enabled
  without the user: the Settings switch or the one-time card (`App/MenuBar/LaunchAtLoginPromptController.swift`).

## Invariants / guardrails
- **No cloud, non-sandboxed, local-only.** Nothing here uploads or phones home. (The one network call in the
  app is Sparkle's update check + download from GitHub, `App/Lifecycle/Updates.swift`; nothing is sent.)
- The paired declarations live at `App/` root and must stay there: `App/Info.plist` (TCC usage
  strings) and `App/BetterScreenshot.entitlements` (signed in by `scripts/build-app.sh`). They are
  part of this surface even though they sit one level up.
- `SystemScreenshotShortcuts` mutates the *user's* OS settings. A regression can silently disable the
  user's native screenshot keys — always pair a `disable…` with a matching `restore…` (AppDelegate
  restores on quit).
- Don't replace the Carbon hotkey path with an event tap without owner sign-off: the Carbon route is
  an intentional choice to avoid the Accessibility permission prompt.
