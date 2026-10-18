# OverlayKit — selection overlay, Quick Access, pin-to-screen

Floating `NSPanel`/`NSView` UI shown over the desktop: the area-selection overlay, the post-capture
Quick Access thumbnail (and its stack), and pin-to-screen panels. Imported by the `App/` target.

## Key files (`Sources/OverlayKit/`)
- `SelectionOverlayController.swift` + `SelectionResult.swift` — drag-to-select-area overlay.
- `QuickAccessOverlayController.swift` + `QuickAccessStackController.swift` — the bottom-right
  post-capture floating thumbnail and its stack. Guided tour (TourKit, v3 Part 7): the stack posts
  `TourEvents.surfaceShown(.quickAccess, card)` once a **screenshot** card sits in its slot; anchors
  `quickAccess.card` / `.actions` (Copy · Edit · Save, grouped in their own stack so ✕ stays outside the
  outline; same 4 pt spacing) / `.edit`; events `quickAccess.copy` / `.save` / `.edit`
  (before the card closes) / `.dragged` (drop on a target). While a tour tag is attached (a TourKit tag
  panel among the card's child windows) the auto-dismiss countdown restarts instead of closing and a drop
  doesn't close the card. Details: `docs/MAC-TO-WINDOWS-PARITY-v3.md` §7.4.
- `PinPanelController.swift`, `PinView.swift`, `PinGeometry.swift`, `DraggableImageView.swift` —
  pin-a-screenshot-to-screen panels (entry points: the menu bar's Pin from Clipboard and the History window;
  the Quick Access card's own Pin button was removed in v2.9.0).
- `QuickAccessContrast.swift`, `SRGB.swift`, `BandLuminance.swift`, `AspectFillMap.swift` — pure,
  unit-tested contrast math for the card's overlaid buttons: WCAG luminance, p10/p90 band percentiles,
  the aspect-fill card→image pixel mapping, and the tone + scrim-alpha solver that guarantees 4.5:1.
- `DraggableImageView.swift` — the card's drag source. A plain `NSView`, **not** an `NSImageView`: on
  macOS 26 `NSImageView` adds its own image subview above every sublayer, which covered the card's
  aspect-fill picture and contrast scrim (doubled images, illegible buttons). Its `image` is only the
  drag preview.
- `HUDController.swift` — transient on-screen toast (optional SF Symbol).
- `PromptCardController.swift` — a notification-style question card in a screen corner (app icon, title,
  line, ≤ 2 buttons; white-filled primary + outlined secondary, first-click, never key, so no keyboard path).
  `HUDSurfaceView` held at least at the default opacity so its all-white text stays ≥ 4.86:1. Joins every Space
  but, per AppKit, **not** full-screen ones (no `.fullScreenAuxiliary`; the app also waits while anything
  full-screen is in front). The secondary stays an
  outline, not the design language's filled small button: a 0.08–0.12 white fill would drop its white text to
  ≈ 4.1–3.8:1 (see `PromptCardButton`). Fonts are text styles (`.body` 13 pt semibold, `.callout` 12 pt).
  `allWindowNumbers` for capture filters. Used by the one-time launch-at-login question.
- `HUDStyle.swift` — the one shared dark HUD look (`.hudWindow` blur, `.vibrantDark`, `.active`, 40% black
  tint, 1px 10% white border). Toasts, the selection size chip, the pin close button and the Quick
  Access badge use it; new small floating surfaces should too.
- `OverlayLabelLayout.swift` (selection size chip placement, window-picker title chip truncation) and
  `MediaInfoText.swift` ("1600 × 1000", "0:42", "0:42 · MP4") — pure and unit-tested.

`PinGeometry`, the four contrast files, `OverlayLabelLayout` and `MediaInfoText` are pure and
unit-tested; the controllers are AppKit UI verified manually.

## Verify
`swift run --package-path Packages/OverlayKit OverlayKitTests`.
