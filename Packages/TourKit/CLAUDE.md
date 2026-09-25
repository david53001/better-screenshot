# TourKit — interactive guided tours (v3 Part 7)

Design: `docs/superpowers/specs/2026-09-24-betterscreenshot-editor-recording-v3-design.md` **§14**, and
**§14.9** (tours are only ever offered to *new* users, and only after they answer "Show Me Around").
Status + lanes: `docs/PROGRESS-v3.md` (lane "Tours & help"). Windows-port notes:
`docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 7.

## What's here (`Sources/TourKit/`)
- `TourModel.swift` — `TourID` (persisted raw values — never rename), `TourSurface`, `TourEvent`,
  `TourStep` (anchor · Explain/Try · title · body), `TourTrigger`, `Tour`.
- `TourEvents.swift` — the one-way bus. Surfaces call `TourEvents.post(_:)` and
  `TourEvents.surfaceShown(_:in:)`; the app's `TourCoordinator` (`App/Tours/`) sets the handlers. No
  handler = no-op, so posting is always safe.
- `TourAnchor.swift` — `NSView.tourAnchor` (the accessibility identifier), `NSWindow.view(forTourAnchor:)`
  (searches content + title bar, skips hidden views), SwiftUI `.tourAnchor("…")`.
- `Catalog/` — every tour as data, **one file per area** (`WelcomeTours`, `EditorTours`, `RecordingTours`,
  `VideoEditorTours`, `ShellTours`) so parallel lanes don't collide; `TourCatalog.all` lists them.
- `Overlay/` — the tag (spec §14.3): `TagOverlayController()` is the real `TourTagPresenting` — a
  click-through decor panel (20% dim, red box, leader line) + a clickable tag panel, both child windows of
  the host that never become key; follows the host/anchor, hides with the anchor; Return = Next / Esc =
  Skip tour via a local monitor (not while typing). Pure `TagLayout` (placement) and `TagKeys` are
  unit-tested; all sizes/colours/strings in `TagStyle`; `windowNumbers` is for a capture's exclusion list.
- `Help/InfoButton.swift` — the ⓘ: `InfoButton.install(in: window, tour:, shortcuts:)` for titled windows
  (rightmost title-bar accessory, beside any existing one), `InfoButton(tour:shortcuts:)` for panels. Menu:
  Replay Tour (→ `TourEvents.replay`) · Keyboard Shortcuts (popover). Windows-port layout: parity doc §7.3.
- Engine, audience classifier, overlay, ⓘ button: added by the Part 7 lanes (see the progress file).

## Contracts (keep stable — other packages and lanes build on them)
- Anchor ids are `"<surface>.<name>"` (e.g. `editor.inspector.colour`, `strip.microphone`). A surface sets
  `view.tourAnchor = "…"` on the real control; the catalog step names the same id.
- A Try step's `advanceOn` event must be one a surface actually posts. Post at the point the action
  already happens (tool change, annotation added, menu opened…); never add UI just for tours.
- Surfaces depend on TourKit only for `TourEvents`, anchors and (for the ⓘ) `InfoButton`. Tour logic,
  persistence and triggers live in the app's `TourCoordinator`, never in a surface.
- Copy rules (enforced by tests): title ≤ 4 words; body ≤ 20 words, 1–2 sentences; Try steps start with
  a verb; shortcuts written as `{shortcut:<HotkeyAction raw value>}` so they show the user's own keys.

## Verify
`swift run -j 2 --package-path Packages/TourKit TourKitTests` (also run by `scripts/test.sh`).
UI probes: keep every probe window behind the owner's windows — set each window's level to
`CGWindowLevelForKey(.desktopWindow) + 1` and `orderBack(nil)`; never order them front or activate.
For the tag's own windows set `TagOverlayController.probeLevel` to that level (`@testable import TourKit`).
Synthetic clicks can't fire an `NSButton` in an inactive `NSWindow` even without an overlay (AppKit keeps
the first click to activate the app) — check routing with `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)`
and fire actions over non-activating panels.
