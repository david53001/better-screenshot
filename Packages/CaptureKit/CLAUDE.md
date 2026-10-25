# CaptureKit — capture engine + pure capture logic

ScreenCaptureKit wrapper plus the pure, TDD'd logic for cropping, encoding, naming, positioning, and
text recognition. Imported by the `App/` target (mainly `App/Capture`).

## Key files (`Sources/CaptureKit/`)
- `CaptureService.swift` — ScreenCaptureKit capture wrapper. `capture(_:excludingWindowIDs:)` leaves the
  given windows out (the app passes guided-tour tag windows): full screen/area via
  `SCContentFilter(display:excludingWindows:)`; a window capture (`desktopIndependentWindow`) would include
  the window's **child windows** — tags are children of their host — so when an excluded window belongs to
  the captured window's app it sets `includeChildWindows = false` (macOS 14.2+).
  `freezeDisplays(excludingWindowIDs:)` (freeze screen) grabs every display while the selection overlay is
  **already up**, so it excludes **our whole app** (`excludingApplications:` + `exceptingWindows:` our listed
  windows minus the excluded IDs). Don't go back to excluding by window ID alone: a window that was just ordered
  front can be missing from `SCShareableContent`, and the overlay's dim then gets baked into the shot (2026-10-02).
  The content query must use `onScreenWindowsOnly: false`: on macOS 26 our menu-bar icon is Control Centre's
  window, so with the overlay unlisted our app wasn't in `applications` either and the ID-only fallback leaked
  the dim again (2026-10-07).
- `CaptureTarget.swift`, `CaptureSettings.swift` — what/how to capture.
- `CaptureGeometry.swift`, `ImageCropper.swift` — geometry + crop math (pure).
- `ImageEncoder.swift` — PNG/JPEG encode; `FileNamer.swift` — output filename rules.
- `OverlayPositioner.swift` — where post-capture overlays sit (pure).
- `TextRecognizer.swift` + `RecognitionResult.swift` — Vision OCR / QR ("Capture Text").
- `TempImageWriter.swift` — writes the drag-out / clipboard temp PNG into `$TMPDIR/BetterScreenshot-<UUID>/`
  **and sweeps expired ones** (`cleanExpired`, scoped to that prefix); `TempFileRetentionScale.swift` is its
  10s…1h/∞ setting scale, driven from `App/Capture/TempFileService`.
- `HotkeyAction.swift`, `HotkeyBindings.swift`, `HotkeyCombo.swift` — the hotkey **model** (binding
  data; registration itself lives in `App/SystemIntegration/HotKeyManager`).
- `LaunchAtLoginPrompt.swift` — the one-time "open at login?" rules: 5 completed captures, never if already
  enabled / already asked / a ≤ 3.1.0 user (`didRegisterLaunchAtLogin`), `isCalmMoment`, the flow as pure
  steps that apply their own side effects (`afterCapture` records the capture and marks asked when found
  enabled, `waitStep`, `shouldHideUnanswered`: an ignored card hides after 25 s; `Showing` + `cardHidUnanswered`:
  only a showing the user could have seen counts, ≤ 3, spaced ≥ 24 h apart even across relaunches;
  `fullScreenInFront`, which also knows a notched display's full-screen window starts below the notch row;
  `offersMenuItem` for the menus' **Open at Login…** item)
  and a storage protocol (`UserDefaults` in the app, an in-memory store in tests, so tests write no plist).
- `LaunchWindowPolicy.swift` — which window a launch opens (Dock app, 3.3.0): setup without Screen Recording,
  Welcome after the permission relaunch or for an unasked new user, else Settings — or nothing when macOS
  opened the app at login. Closures keep the relaunch flag's one-time read where it was.

## Conventions / invariants
- Coordinate convention (project-wide): annotations/regions are in base-image pixel space, **top-left
  origin**.
- Pure logic is test-first.

## Verify
`swift run --package-path Packages/CaptureKit CaptureKitTests` (or `scripts/test.sh` for all suites).
