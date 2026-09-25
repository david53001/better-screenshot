# App/Capture — screenshot capture orchestration

- `CaptureCoordinator.swift` — drives one capture end to end: area-selection overlay
  (`OverlayKit`) → capture/crop/encode/OCR (`CaptureKit`) → post-capture Quick Access thumbnail
  (`OverlayKit`) → optional annotation editor (`EditorKit`) → output (save / copy / add to History
  via `HistoryKit` / add to the Quick Access stack).

Key collaborators it owns: the Quick Access overlay (`quickAccess`). `keepInStack(...)` adds a
flattened edit to the bottom-right Quick Access stack and History (this is the editor's **Stack**
button target).

Guided tours (v3 Part 7): every screenshot (`run` — area, window, full screen — and `runCaptureText`)
passes `tourTagWindowIDs` (= TourKit's `TagOverlayController.allWindowNumbers`) to
`CaptureService.capture(_:excludingWindowIDs:)` so a tour tag never lands in the user's image, and posts
`TourEvents.post(.captureTaken)` right after the pixels are captured, before the card appears (the
Welcome tour's "Take a screenshot" step). Details: `docs/MAC-TO-WINDOWS-PARITY-v3.md` §7.4.

Pure capture logic (geometry, crop, encode, filename, OCR) lives in `Packages/CaptureKit` and is
unit-tested there; this file is the app-side orchestration. Verify by running a capture in the built
app.
