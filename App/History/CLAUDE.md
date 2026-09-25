# App/History — capture history

- `HistoryService.swift` — app-side glue over `Packages/HistoryKit`: records captures/recordings into
  the history store and exposes them to the rest of the app.
- `HistoryWindowController.swift` — the history browser window (lists past captures, restore/reveal).
  Minimum width 660pt so the action-bar labels never truncate (re-check if you add a button); "Clear
  All History…" lives in the trailing ⋯ menu, not the action row. Cells show `HistoryService.detail(for:)`
  ("1600 × 1000" / "0:42"); the empty state text is `HistoryKit/HistoryEmptyState` (tested).
  Guided tour (v3 Part 7): `makeWindow()` (internal, for probes) installs the title-bar ⓘ (Replay Tour +
  the grid's modifier clicks); `show()` posts `TourEvents.surfaceShown(.history)`. Anchors:
  `history.grid` (grid scroll view, or the empty state), `history.item` (the newest cell only),
  `history.actions` (bottom bar). Events: `action("history.selected")` after a click changes the
  selection, `action("history.dragged")` when a drag starts. Steps: `docs/MAC-TO-WINDOWS-PARITY-v3.md` §7.8.
- `MediaDuration.swift` — a recording's length (MP4 header via AVFoundation, GIF frame delays via
  ImageIO); also used by `RecordingCoordinator` for the Quick Access card's "0:42 · MP4" badge.
- `HistoryItemInteraction.swift` — transparent AppKit layer over each grid cell. Exists because
  SwiftUI on macOS 14 can neither read a click's modifier keys nor start a dragging session with more
  than one file. Selection arithmetic itself is pure and lives in `HistoryKit/HistorySelection.swift`.

Index/store/restore-stack/thumbnail logic (pure + file IO) lives in `Packages/HistoryKit` and is
unit-tested there. Invariant inherited from HistoryKit: saved **recordings are referenced, never
copied or deleted**; screenshots are copied + thumbnailed; count-cap pruning happens at load (no age
prune — Capture History has no time expiry). Verify via HistoryKit tests plus opening the history
window in the built app.

Dragged files are always the **persistent** ones — the history-owned PNG under
`~/Library/Application Support/BetterScreenshot/History/` for screenshots, the user's saved file for
recordings — never a `$TMPDIR` copy, so the "Keep cached files for" sweep can't delete a file out
from under a drop target.
