# macOS → Windows parity — the 2026-09 editor & recording work

**What this is.** The macOS app (this repo, `main`) gained features in September 2026 that the
Windows port does not have. This document tells whoever ports them **exactly** what was built —
layout, items, labels, behaviour, defaults, persisted data, and pure logic — so the Windows version
can match without reading Swift. It is the reverse of `docs/WINDOWS-TO-MAC-PARITY.md`.

**The Windows port.** C#/.NET 9 + WPF on the `windows-port` branch, under `windows/`. Start with
`windows/README-win.md`, `windows/docs/PROGRESS.md`, and the per-module ground-truth files
`windows/docs/port-reference/0N-*.md`. Its recording engine is **ffmpeg** (`ddagrab`/`gdigrab` video,
WASAPI loopback system audio, `dshow` microphone) with pause implemented as one ffmpeg segment per
active span, concatenated at the end (`windows/src/BetterScreenshot.App/Recording/RecordingEngine.cs`).

**Conventions.** Sizes are macOS points; treat 1 pt = 1 WPF device-independent pixel. "SF Symbol"
names are macOS icon names — map them to the port's icon set in
`windows/src/BetterScreenshot.App/Resources/Icons.xaml`. Quoted UI strings are verbatim and should be
copied exactly. The design rationale for Parts 0–6 is in
`docs/superpowers/specs/2026-09-24-betterscreenshot-editor-recording-v3-design.md`.

**Each section below covers:** Layout (exact) · Items & behaviour · Data (persisted keys, defaults,
legacy decoding) · Pure logic to port 1:1 (with the macOS test cases) · Where it goes in the port ·
Platform notes (where Windows must differ).

---

## A. Already built on macOS, 2026-09-24 (commits `d845ad1`, `4a4316c`, `88f3a8f`)

_(pending — written by the coordinating session)_

---

## Part 0 — Trim window: Cancel restores the Quick Access card

**The bug (macOS, fixed).** A recording's Quick Access card has a ✂ **Trim** button. Pressing it
dismisses the card (reason `actionTaken`, so it is *not* added to "Restore Recently Closed") and opens
the trim / video-editor window. Closing that window never brought the card back, so cancelling looked
like it had deleted the recording.

**Behaviour now (port exactly).** The window that the card opens takes a `restoreCard` callback that
runs **exactly once, when the window closes, whatever closed it**:

| How the window closes | Cards afterwards |
|---|---|
| **Cancel** button or the window's close box, nothing saved | the original's card comes back in its corner |
| **Replace Original**, then **Done** / close box | the original's card comes back, its thumbnail re-extracted from the file (so it shows the *edited* file's first frame) |
| **Save as Copy** (the window closes itself) | the copy gets its own new card + History entry (as before) **and** the original's card comes back |
| **Export as GIF** (Part 6; window stays open), later closed | the GIF's card appears right after export; the original's card comes back on close |

- The restored card is a *new* card built the normal way (`presentCard(for:image:historyID:)` on macOS)
  with the **same History id** as the original, a **fresh thumbnail** (first frame, ≤ 640 px) and the
  normal corner / auto-dismiss settings. If the file no longer exists (thumbnail fails), no card.
- Opening the window from the **History** window's **Trim…** passes no callback: nothing is restored
  (there was no card).
- Only one trim window exists at a time. Opening a *different* file closes the current window first
  (which restores *its* card). Opening the *same* file again just brings the window forward; if that
  request came from another card of the same file, its restore is chained onto the window's close so
  both cards come back.

**macOS code.** `App/Recording/RecordingCoordinator.swift`: `presentTrim(url:restoreCard:)` (the
callback runs from the window's `onClosed`), `presentCard(for:image:historyID:)` (the card's `onTrim`
passes `restoreCard: { bringBackCard(for: url, historyID: historyID) }`), `bringBackCard(for:historyID:)`
(fresh thumbnail → `presentCard`). `TrimWindowController.onClosed` fires from `windowWillClose`, i.e. on
every close path including Save as Copy's own `close()`.

**Verified by** a headless probe (synthetic button clicks on a generated MP4): Cancel → restore ×1,
copy ×0 · close box → restore ×1 · Save as Copy → copy card ×1 **and** restore ×1 · Replace Original →
window stays open, Cancel reads "Done" → Done → restore ×1.

**Where it goes in the port.** The port has no trim window yet (it arrives with Part 6). Recording cards
are shown by `CaptureCoordinator.ShowRecordingCard(path, thumbnail, historyId)` in
`windows/src/BetterScreenshot.App/Capture/CaptureCoordinator.cs` (called from `OnRecordingFinished`);
`QuickAccessActions` (`windows/src/BetterScreenshot.App/Overlays/QuickAccessTypes.cs`) needs an optional
`OnTrim` (MP4 only), and the card's Trim button must dismiss with `DismissReason.ActionTaken` and then
open the editor with a `restoreCard` delegate that calls `ShowRecordingCard(path, freshThumb, historyId)`.

**Platform note.** The port's recording thumbnail today is a *screen grab taken at stop time*
(`RecordingCoordinator.CaptureThumb`), not a video frame. For the restored card after Replace Original,
extract the new first frame with ffmpeg instead:
`ffmpeg -v error -i "<file>.mp4" -frames:v 1 -vf "scale='min(640,iw)':-2" -y "<temp>.png"`.

---

## Part 1 — Editor side panel, hint line, zoom, tool shortcuts, opacity

_(pending — filled when Part 1 lands)_

---

## Part 2 — Text v2 (corner scaling, background, outline, presets)

_(pending — filled when Part 2 lands)_

---

## Part 3 — Redaction strength, Highlighter, Spotlight

_(pending — filled when Part 3 lands)_

---

## Part 4 — Recording setup strip v2 (device menus, level meter, hint line)

_(pending — filled when Part 4 lands)_

---

## Part 5 — Live recording pill v2 (mute, switch window, restart, discard)

_(pending — filled when Part 5 lands)_

---

## Part 6 — Video editor v2 (cut, per-segment speed/mute, GIF export)

_(pending — filled when Part 6 lands)_
