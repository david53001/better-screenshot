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
  `WelcomeTours` (welcome, quickAccess) and `ShellTours` (settings, history): steps, anchors and where each
  event is posted are in parity doc §7.4 / §7.8. Welcome's first anchor (`menuBar.icon`) lives in the status
  item's window, found through `TourCoordinator.extraAnchorWindows`.
- `TourAudience.swift` — §14.9's pure new/existing classifier (`classify(Signals)`: any non-tour key in the
  app's own domain, anything in the support folder, Screen Recording already granted, or an unknown bundle
  id → `.existing`) + `TourPreferenceKey` (the only five keys tours persist).
- `TourRules.swift` — `shouldAutoStart` (tours on — absent = off — **and** this version unseen),
  `shouldAskQuestion` / `shouldOpenWelcomeOnLaunch`, `tours(triggeredBy:)`; `TourText` resolves
  `{shortcut:<action>}` through a caller-supplied lookup.
- `TourEngine.swift` — one tour's pure state machine: start at a step · Next (Explain only) · Skip step ·
  Skip tour · Try steps advance only on their exact event · missing anchors and already-done Try steps
  skipped · pause/resume · `.finished(handsOverTo:)`; `start`/`resume` with nothing presentable →
  `.nothingToShow` (never burns a tour).
- `TourNames.swift` — `TourID.menuTitle` / `menuSymbol` for the Help & Tours menu.
- `Overlay/` — the tag (spec §14.3): `TagOverlayController()` is the real `TourTagPresenting` — a
  click-through decor panel (20% dim, red box, leader line) + a clickable tag panel, both child windows of
  the host that never become key; follows the host/anchor, hides with the anchor; Return = Next / Esc =
  Skip tour via a local monitor (not while typing; Esc also not while the host window's
  `TourEscapeClaiming.claimsEscape` is true — the editor's Esc-to-Select). Pure `TagLayout` (placement) and `TagKeys` are
  unit-tested; all sizes/colours/strings in `TagStyle`; `windowNumbers` is for a capture's exclusion list.
- `Help/InfoButton.swift` — the ⓘ: `InfoButton.install(in: window, tour:, shortcuts:)` for titled windows
  (rightmost title-bar accessory, beside any existing one), `InfoButton(tour:shortcuts:)` for panels. Menu:
  Replay Tour (→ `TourEvents.replay`) · Keyboard Shortcuts (popover). Windows-port layout: parity doc §7.3.
- The app side (`App/Tours/TourCoordinator`) drives all of the above.

## Contracts (keep stable — other packages and lanes build on them)
- Anchor ids are `"<surface>.<name>"` (e.g. `editor.inspector.colour`, `strip.microphone`). A surface sets
  `view.tourAnchor = "…"` on the real control; the catalog step names the same id.
- A Try step's `advanceOn` event must be one a surface actually posts. Post at the point the action
  already happens (tool change, annotation added, menu opened…); never add UI just for tours.
- Surfaces depend on TourKit only for `TourEvents`, anchors and (for the ⓘ) `InfoButton`. Tour logic,
  persistence and triggers live in the app's `TourCoordinator`, never in a surface.
- Copy rules (enforced by `CatalogLintTests` on `TourCatalog.all`): title ≤ 4 words; body ≤ 20 words,
  1–2 sentences; Try bodies start with a verb (not "The/This/Your/…"); anchors and `menuOpened`/
  `choiceMade`/`action` names are `<surface>.<name>`; no two Try steps in a tour wait for the same event;
  shortcuts written as `{shortcut:<HotkeyAction raw value>}` so they show the user's own keys (the valid
  names are listed in the test — add one there when `HotkeyAction` gains a case).
- A tour's steps can be shown only once its surface calls `TourEvents.surfaceShown` and its anchors
  exist; until then starting it is a no-op (`.nothingToShow`), not "seen".
- Word limits don't guarantee a body fits the tag's **two lines**: measure it in the tag's body label at
  236 pt (`Tests/TourKitTests/TagFitTests.swift` for Welcome/Quick Access/Settings/History; lane 7E's
  `EditorKit/Tests/EditorKitTests/EditorTourTests.swift` for the editor tours).
- `TagOverlayController.allWindowNumbers` must be left out of every screenshot/recording — the app passes it
  to `CaptureService.capture(_:excludingWindowIDs:)`. Tags are **child windows** of their host, so a
  single-window capture includes them unless it drops child windows (CaptureKit does, macOS 14.2+).

## Verify
`swift run -j 2 --package-path Packages/TourKit TourKitTests` (also run by `scripts/test.sh`).
UI probes: keep every probe window behind the owner's windows — set each window's level to
`CGWindowLevelForKey(.desktopWindow) + 1` and `orderBack(nil)`; never order them front or activate.
For the tag's own windows set `TagOverlayController.probeLevel` to that level (`@testable import TourKit`).
Synthetic clicks can't fire an `NSButton` in an inactive `NSWindow` even without an overlay (AppKit keeps
the first click to activate the app) — check routing with `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)`
and fire actions over non-activating panels.
