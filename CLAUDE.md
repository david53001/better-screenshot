# BetterScreenshot

A **free, local macOS clone of CleanShot X** (screenshot + screen-recording tool). Native Swift app.

> **Windows port:** a native **.NET 9 + WPF (C#)** port lives under [`windows/`](windows/) on the
> **`windows-port`** branch. This file and everything below it describe the **macOS** app (the behavioral
> source of truth). For the port, the guide + ledger are [`windows/README-win.md`](windows/README-win.md),
> [`windows/docs/PROGRESS.md`](windows/docs/PROGRESS.md), and [`windows/LOOP-PROMPT.md`](windows/LOOP-PROMPT.md).
> It's built/deployed with `pwsh windows/scripts/publish-app.ps1` (republish + relaunch after runtime-visible
> changes — a plain build doesn't update the `dist/` tray agent the owner runs).

## Hard constraints
- **No cloud.** No uploads, share links, accounts, or cloud sync — ever. Local features only.
- **macOS-native, non-sandboxed, menu-bar agent** (`LSUIElement`). Personal/local use; ad-hoc signed (no Apple Developer account required).
- **Min target: macOS 14 (Sonoma).**
- **Updates must never cost users their permission, settings, or data** (owner requirement, 2026-09-10).
  Screen Recording is keyed on the designated requirement `identifier "com.betterscreenshot.mac" and
  certificate leaf = H"71ec62cd…"` — every release since v2.10.0 is signed with the local identity
  "BetterScreenshot Code Signing" in `~/Library/Keychains/betterscreenshot-signing.keychain-db`
  (created by `scripts/setup-signing.sh`). Losing or regenerating that keychain changes the hash and
  forces every user to re-grant. Back it up; never release from a machine without it. `scripts/install.sh`
  may only ever replace `/Applications/BetterScreenshot.app` — settings live in
  `~/Library/Preferences/com.betterscreenshot.mac.plist`, history in
  `~/Library/Application Support/BetterScreenshot/History/`.
- **Bundle id is `com.betterscreenshot.mac` — never change it back to `com.betterscreenshot.app`.**
  macOS 26's ControlCenter holds an unremovable blocked-host record for the old id that permanently
  hides the menu-bar icon on the owner's machine (v2.8.1; forensics in
  `docs/INVESTIGATION-2026-08-06-menubar-icon-not-placed.md`).

## Stack
- Swift 5.9+, **SwiftUI + AppKit hybrid** (SwiftUI for settings/menus; AppKit `NSPanel`/custom `NSView` for overlays + the editor canvas).
- ScreenCaptureKit (capture/recording), Vision (OCR, later), CoreImage (blur/pixelate), Carbon `RegisterEventHotKey` (global hotkeys — avoids the Accessibility prompt).
- **Build:** SwiftPM — `swift build`, with `scripts/build-app.sh` assembling `dist/BetterScreenshot.app` (CLT-only, no Xcode; see `docs/BUILD-NOTES.md`). Library modules are local Swift packages under `Packages/`, tested via TestKit executable runners — run all suites with `scripts/test.sh`.
- **Testing:** TDD on pure logic (geometry, encode, model, renderer) via the local TestKit harness; system/UI behavior is manually verified against checklists in the plans.

## Architecture (v1)
Local Swift packages + a menu-bar app target:
- `CaptureKit` — ScreenCaptureKit wrapper + pure geometry/crop/encode/filename logic.
- `OverlayKit` — area-selection overlay + Quick Access thumbnail (`NSPanel`).
- `EditorKit` — annotation document model + custom `NSView` canvas + tools + flatten-to-image renderer.
- `HistoryKit` — capture history index/store + restore stack (pure logic + file IO).
- `App/` (target) — hotkeys, menu bar, settings, and capture→overlay→editor→output orchestration.

**Coordinate convention:** annotations live in base-image pixel space, top-left origin; rendering uses a flipped `NSGraphicsContext` so AppKit drawing (incl. text) is right-side-up.

## Source of truth — read these before working
- `CLEANSHOT-X-FEATURE-SPEC.md` — verified target feature inventory (what we're cloning).
- `docs/superpowers/specs/2026-06-02-betterscreenshot-v1-design.md` — the v1 design.
- `docs/superpowers/plans/` — bite-sized, TDD, self-contained implementation plans:
  - `…-plan-1-foundation-capture.md` — scaffold, hotkeys, permission, capture, save/copy.
  - `…-plan-2-quick-access-overlay.md` — post-capture floating thumbnail.
  - `…-plan-3-annotation-editor.md` — the editor (model, canvas, tools, export).
- P3 (shipped v1.3): `docs/superpowers/specs/2026-06-04-betterscreenshot-p3-ocr-pin-design.md` + `docs/superpowers/plans/2026-06-04-betterscreenshot-p3-ocr-pin.md` — Capture Text (OCR/QR, ⌘⇧7), Pin to Screen, Quick Access stack.
- Editor sticky defaults + Stack button (shipped 2026-06-25, on `main`, not tagged): `docs/superpowers/specs/2026-06-25-betterscreenshot-editor-defaults-and-stack-button-design.md` + `docs/superpowers/plans/2026-06-25-betterscreenshot-editor-defaults-and-stack-button.md` — the annotation editor remembers the last-used stroke/text color + size across sessions (persisted in `UserDefaults` key `editorDefaultStyle` via `SettingsStore.editorStyle`, injected into `EditorWindowController` as `defaultStyle`, saved on the `onStyleChanged` callback); and the editor's bottom-bar **Pin** button was replaced by a **Stack** button (`EditorWindowController.onAddToStack` → `CaptureCoordinator.keepInStack`) that adds the flattened edit to the bottom-right Quick Access stack + History. Pin-to-Screen was retained via the Quick Access overlay's own Pin action at the time; that button was removed in v2.9.0, so Pin now lives only on the menu bar (**Pin from Clipboard**) and in the History window. This change is a good worked example of the brainstorm → spec → plan → subagent-driven-development → merge flow for a small two-feature change.
- Windows→macOS parity backport (shipped 2026-07-04, on `main`, not tagged): design in `docs/WINDOWS-TO-MAC-PARITY.md` (grabbed from the `windows-port` branch, which holds a full C#/.NET WPF port of the app under `windows/`); plans in `docs/superpowers/plans/2026-07-04-parity-part{1,2,3}-*.md`. Brings the mac app to parity with the Windows port in three areas: **Part 1** — Settings rebuilt as a pure-black 960px three-column "JVoice" card masonry replacing the SwiftUI `TabView` (new custom controls under `App/Settings/Components/` + `SettingsTheme.swift`/`SettingsHelp.swift`; forced-dark window; instant-apply preserved); **Part 2** — the Quick Access post-capture card is now full-bleed with auto-contrasting overlaid buttons (`QuickAccessContrast`), a tone-matched scrim, variable-height stacking (`OverlayPositioner.stackedOrigins`), and a wired auto-dismiss timer + hover-pause (`OverlayDismissScale`; `overlayAutoDismissSeconds` default **0 = Never**); **Part 3** — optional auto-contrast editor text-background chip (`AnnotationStyle.textBackground`), clamp annotation drags to image bounds (`EditorBoundsClamp`), clamp area-selection to screen (`SelectionClamp`), history cap 200→100, plus a new `playSound` capture setting. **Not yet done: the stretched-resolution capture "black bar" item** (Part 3 §3.B #10) — needs the owner's stretched display to reproduce; no speculative capture-geometry change was made. A second good worked example of the brainstorm → spec → plan → subagent-driven-development → merge flow.
- Next features (designed 2026-06-05, awaiting plans — see Roadmap below for order):
  - `docs/superpowers/specs/2026-06-05-betterscreenshot-capture-history-design.md`
  - `docs/superpowers/specs/2026-06-05-betterscreenshot-recording-controls-design.md`
  - `docs/superpowers/specs/2026-06-05-betterscreenshot-trim-editor-design.md`
- `CHANGELOG.md` — per-release history.

## Roadmap (post-v1, each its own spec → plan)
~~P2 recording~~ (shipped v2.0/2.1) · ~~P3 OCR + pin-to-screen~~ (shipped v1.3) · ~~reliability + infra sprint~~ (shipped v2.2, 2026-06-05 — fixes from the scan, CI added) · ~~v2.3 capture history~~ (shipped 2026-06-05) · ~~editor sticky defaults + Stack-to-Quick-Access button~~ (shipped 2026-06-25, on `main`, not tagged — see Source of truth above) · ~~Windows→macOS parity backport~~ (shipped 2026-07-04, on `main`, not tagged — JVoice settings reskin + full-bleed Quick Access card + editor/capture backports; see Source of truth above. Outstanding: stretched-resolution "black bar" capture item, needs owner hardware) · ~~Quick Access hold duration~~ (shipped v2.5.0, 2026-08-01 — see below) · ~~guaranteed Quick Access button contrast + Pin button removal~~ (shipped v2.9.0, 2026-08-27 — see below).

**Quick Access hold duration** (shipped 2026-08-01, tag `v2.5.0`, built directly without a spec at the owner's request): the Settings → Quick Access Overlay → "Auto-dismiss after" slider now runs over an ordered stop table in `OverlayDismissScale` (`Packages/CaptureKit/Sources/CaptureKit/OverlayDismissScale.swift`) — **30s · 1m · 2m · 5m · 10m · 15m · 30m · Never** — where the slider position is the stop *index*, not a second count. `CaptureSettings.init(dictionary:)` snaps any persisted value that isn't a stop to the nearest one (same precedent as `historyCap` in `48e9c3a`). Default is still `0` = Never. The C# port mirrors the identical table in `windows/src/BetterScreenshot.Capture/OverlayDismissScale.cs` on the `windows-port` branch.

**Temp-file retention** (shipped 2026-08-01, tag `v2.7.0`, built directly without a spec at the owner's request): Settings → Capture → "Keep cached files for" controls how long the temporary PNG the app writes for a drag-out or for putting a file path on the clipboard survives in `$TMPDIR/BetterScreenshot-<UUID>/` (e.g. `/var/folders/8h/…/T/BetterScreenshot-4C7446B4-…/Screenshot 2026-08-01 at 18.25.57.png`). Stops live in `TempFileRetentionScale` (`Packages/CaptureKit/Sources/CaptureKit/TempFileRetentionScale.swift`) — **10s · 30s · 5m · 10m · 30m · 1h · ∞** — persisted as `CaptureSettings.tempRetentionSeconds` (default **300**, matching the old hard-coded behaviour; `0` = ∞). `TempImageWriter.cleanExpired(in:olderThan:now:)` does the work and is **scoped to the `BetterScreenshot-` directory prefix**, which is what keeps it away from the in-progress GIF `RecordingCoordinator` writes straight to the temp root. `App/Capture/TempFileService.swift` sweeps every 5s *and at launch* — the launch sweep matters because cleanup used to be a per-file `DispatchQueue.asyncAfter(300)` in `CaptureCoordinator` and `DraggableImageView`, which died with the process and orphaned a folder on every quit. Both of those timers (and `DraggableImageView.deletesFileAfterDrag`, now unused) were deleted.

**Refocus after capture + History drag/multi-select** (shipped 2026-08-06, tag `v2.8.0`, plan:
`docs/superpowers/plans/2026-08-06-betterscreenshot-refocus-and-history-multiselect.md`): every
screenshot entry point in `CaptureCoordinator` now records `NSWorkspace.shared.frontmostApplication`
up front and reactivates it once the capture finishes — after the pixels are grabbed, so the restored
window ordering can't leak into the shot. The predicate is
`FocusRestore.shouldRestore(previousBundleID:ownBundleID:)` in CaptureKit. The focus theft itself
comes from `SelectionOverlayController.present()`'s `NSApp.activate(ignoringOtherApps:)`, which the
borderless overlay needs to receive Escape; the Quick Access card and HUD are `.nonactivatingPanel`
and never stole focus. In the History window, selection is now `HistorySelectionState`
(`Packages/HistoryKit/Sources/HistoryKit/HistorySelection.swift`, pure + unit-tested) driven by
`App/History/HistoryItemInteraction.swift`, a transparent AppKit view per cell — SwiftUI on macOS 14
can express neither modifier-aware clicks nor a multi-file `NSDraggingSession`. Two invariants split
across `CaptureCoordinator.rememberFrontmostApp()` and `restoreFrontmostApp()` are deliberate, not
oversights: `rememberFrontmostApp()` skips recording BetterScreenshot itself as the "previous" app,
and `restoreFrontmostApp()` never clears `previousApp` — both so a second capture hotkey pressed
during an already-open selection doesn't lose the real target app. The single exception is
`rememberFrontmostApp()` clearing `previousApp` when we are frontmost *and* no selection is up: the
capture came from one of our own windows, so there is nothing to hand back to. Recording flows are
not covered — `RecordingCoordinator` has no refocus path.

> **v2.6.0 was the same feature aimed at the wrong target** and is fully reverted: it expired *History* entries. **Capture History has no time expiry** — `HistoryIndex.pruned(cap:)` applies the count cap only, and even the pre-v2.6.0 fixed 30-day prune is gone (owner: "that one is infinite and holds a certain number of screenshots"). Don't reintroduce an age prune in HistoryKit. The stop table shape is deliberately duplicated between `TempFileRetentionScale` and `OverlayDismissScale` rather than extracted.

**Both scales render their "never expire" stop as `∞`** (tag `v2.6.1`) via a `neverLabel` constant — the persisted value for that stop is still `0` and the internal `neverSeconds` / `neverPosition` names are unchanged, so only the displayed glyph differs. The C# port mirrors this in `OverlayDismissScale.NeverLabel`.

**Guaranteed Quick Access button contrast** (shipped 2026-08-27, tag `v2.9.0`, built directly without a
spec at the owner's request): the post-capture card's overlaid buttons no longer *guess* a glyph tone from
the mean luminance of the image's bottom 30% — a mean cannot describe a bimodal band, so no threshold on it
can be made correct. Four pure, unit-tested pieces now live in `Packages/OverlayKit/Sources/OverlayKit/`:
`SRGB.swift` (WCAG 2.x gamma-expanded relative luminance + contrast ratio), `BandLuminance.swift` (p10/p90
percentiles over an RGBA8 buffer, replacing the mean), `AspectFillMap.swift` (maps a card-space rect to the
source pixels `contentsGravity = .resizeAspectFill` actually draws there — the old sampler read pixels that
aspect-fill had cropped off screen), and `QuickAccessContrast.plan(for:)`, which closed-form solves the scrim
alpha each tone would need to clear `targetContrastRatio` (4.5) against the worst background, picks the
cheaper tone, and clamps to `[minScrimAlpha 0.18, maxScrimAlpha 0.85]`. `QuickAccessOverlayController` builds
the button row *first* so the sample rect matches the row's final on-screen frame, samples at **device
resolution** (downsampling further box-filters a white headline into its dark surround — measured 0.91 → 0.33
on the real failing case, which would have shipped a fix that passed its own test at 1.55:1 on screen), and
the scrim now holds `plan.scrimAlpha` **flat** from the row's top edge to the card bottom instead of fading to
~27% under the glyphs. The guarantee only holds while the scrimmed region is a superset of the sampled one —
do not narrow the scrim or widen the sample without redoing that argument. The mean-based
`averageLuminance` / `tone(forLuminance:)` / `lightThreshold` API was deleted. The C# port's
`windows/src/BetterScreenshot.App/Overlays/QuickAccessContrast.cs` still has the old mean logic and was **not**
updated. Same release removed the Quick Access card's **Pin** button (Pin to Screen still reachable from the
menu bar and History); the `sourceRect` plumbing through `CaptureCoordinator.run`/`handle`/`presentOverlay`
is now unused by the overlay path and only `pin(_:near:)` still reads it.

**Capture Text paragraph reflow** (shipped 2026-09-10, tag `v2.11.0`, built directly without a spec at the
owner's request): `TextReflow` (`Packages/CaptureKit/Sources/CaptureKit/TextReflow.swift`, pure + unit-tested)
rebuilds paragraphs from Vision's per-visual-line boxes before `RecognitionResolver` joins them, so a wrapped
bullet pastes as one line. A line continues the block above only if it overlaps that block's column, the
spacing matches the block (gap ≤ 1.0× line height, pitch ≤ 1.25× the block's median, height ratio ≤ 1.5),
it doesn't start with a list marker, and the previous line *wrapped* — its width plus the next line's first
word overflows the column's right edge (max right of all x-overlapping lines). That fit test is what keeps
code line-per-line; its known limit is that a code block's longest line merges with its follower. Thresholds
were measured on the owner's slide screenshot (intra-paragraph pitch jitter ≤ 1.07×, paragraph break 1.33×).
Vision's confidence is useless for filtering photo junk (it scores "CREAM STEA" at 1.00) — don't try. Same
release added the README **Update** section (re-run the install one-liner).

**Next up — spec ready** (`superpowers:writing-plans` from the spec, then execute with `superpowers:subagent-driven-development`; the spec lists its own probes/risks — run probe tasks first, and verify named symbols against live code before planning):
1. **Trim Editor** — `docs/superpowers/specs/2026-06-05-betterscreenshot-trim-editor-design.md`

(Recording Controls — countdown · window target · pause/resume — shipped as `v2.4.0` on 2026-06-25.)

**Background/wallpaper styling: dropped by owner decision (2026-06-05) — do not build or re-propose.**

Later (no spec yet): scrolling capture · freeze/self-timer/repeat-area · small quick wins (Repeat Previous Area, editor ⌘D/⌘⇧S bindings, capture sound, JPG-quality + filename settings; details in the local `CODEBASE-SCAN.md` if present) · P5 `betterscreenshot://` URL automation.

## Executing the plans
Plans use checkbox steps. Execute task-by-task with the **superpowers:subagent-driven-development** (fresh subagent per task) or **superpowers:executing-plans** skill. Each task ends in a commit; each plan ends in a git tag (`v0.1-capture-core`, `v0.2-quick-access`, `v1.0`). Plan 1 Task 1 runs `git init` and `brew install xcodegen` (prerequisite).

## Working norms (from the user's global CLAUDE.md)
Simplicity first; surgical changes (touch only what the task needs); state assumptions and ask when unclear; define verifiable success criteria and loop until tests pass.
