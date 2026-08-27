# OverlayKit — selection overlay, Quick Access, pin-to-screen

Floating `NSPanel`/`NSView` UI shown over the desktop: the area-selection overlay, the post-capture
Quick Access thumbnail (and its stack), and pin-to-screen panels. Imported by the `App/` target.

## Key files (`Sources/OverlayKit/`)
- `SelectionOverlayController.swift` + `SelectionResult.swift` — drag-to-select-area overlay.
- `QuickAccessOverlayController.swift` + `QuickAccessStackController.swift` — the bottom-right
  post-capture floating thumbnail and its stack.
- `PinPanelController.swift`, `PinView.swift`, `PinGeometry.swift`, `DraggableImageView.swift` —
  pin-a-screenshot-to-screen panels (entry points: the menu bar's Pin from Clipboard and the History window;
  the Quick Access card's own Pin button was removed in v2.9.0).
- `QuickAccessContrast.swift`, `SRGB.swift`, `BandLuminance.swift`, `AspectFillMap.swift` — pure,
  unit-tested contrast math for the card's overlaid buttons: WCAG luminance, p10/p90 band percentiles,
  the aspect-fill card→image pixel mapping, and the tone + scrim-alpha solver that guarantees 4.5:1.
- `HUDController.swift` — transient on-screen HUD.

`PinGeometry` and the four contrast files above are pure and unit-tested; the controllers are AppKit UI
verified manually.

## Verify
`swift run --package-path Packages/OverlayKit OverlayKitTests`.
