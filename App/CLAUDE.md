# App/ — menu-bar app target (orientation)

The BetterScreenshot menu-bar agent (`LSUIElement`, non-sandboxed, local-only). This is the single
SwiftPM **executable target** `BetterScreenshot` (see root `Package.swift`, `path: "App"`). It
orchestrates the capture → overlay → editor → output flow across the `Packages/*` library modules.

## How this folder is built (read before moving anything)
- **One module.** Every `.swift` under `App/` (recursively, including the subfolders below) compiles
  into the same target. SwiftPM selects sources by directory glob, so the subfolders are *organization
  only* — they are NOT separate modules and need no `import`s between them.
- **`Info.plist` and `BetterScreenshot.entitlements` must stay at `App/` root.** They are referenced
  by path in `scripts/build-app.sh` (bundle assembly + `codesign --entitlements`) and excluded by
  `Package.swift` (`exclude: ["Info.plist", "BetterScreenshot.entitlements"]`). Moving them breaks the
  build/signing.

## Sections (each has its own brief)
- `Lifecycle/` — app entry + wiring.
- `Capture/` — screenshot capture orchestration.
- `Recording/` — screen-recording orchestration + record strip.
- `History/` — capture-history glue + browser window.
- `Settings/` — settings store + UI.
- `MenuBar/` — status-item menu + onboarding.
- `Tours/` — guided-tour coordinator (who gets tours, triggers, persistence; logic in `Packages/TourKit`).
- `SystemIntegration/` — ⚠️ OS-integration & permission surface (hotkeys, TCC, login item, native-shortcut suppression).

## Verify changes to this target
- Build: `scripts/build-app.sh` (assembles + signs `dist/BetterScreenshot.app`).
- Plain compile: `swift build`.
- Tests live in the packages, not here: `scripts/test.sh`.
