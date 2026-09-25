# CaptureKit — capture engine + pure capture logic

ScreenCaptureKit wrapper plus the pure, TDD'd logic for cropping, encoding, naming, positioning, and
text recognition. Imported by the `App/` target (mainly `App/Capture`).

## Key files (`Sources/CaptureKit/`)
- `CaptureService.swift` — ScreenCaptureKit capture wrapper. `capture(_:excludingWindowIDs:)` leaves the
  given windows out (the app passes guided-tour tag windows): full screen/area via
  `SCContentFilter(display:excludingWindows:)`; a window capture (`desktopIndependentWindow`) would include
  the window's **child windows** — tags are children of their host — so when an excluded window belongs to
  the captured window's app it sets `includeChildWindows = false` (macOS 14.2+).
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

## Conventions / invariants
- Coordinate convention (project-wide): annotations/regions are in base-image pixel space, **top-left
  origin**.
- Pure logic is test-first.

## Verify
`swift run --package-path Packages/CaptureKit CaptureKitTests` (or `scripts/test.sh` for all suites).
