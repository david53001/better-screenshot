# Codebase Scan Report

**Scanned:** /Users/davidghermansteinberg/Desktop/Home/Code/BetterScreenshot
**Date:** 2026-06-05
**Project profile:** Native macOS menu-bar app (Swift 5.9, SwiftUI + AppKit hybrid), ~5.2k LOC sources + ~1k LOC tests across 4 feature packages (CaptureKit, EditorKit, OverlayKit, RecordingKit) + TestKit + App target. Zero external dependencies.
**Agents run:** CORE-ARCH, CORE-QUALITY, CORE-TESTS, CORE-DEPS, CORE-DOCS, IMPROVEMENTS, FEATURE-GAPS (custom, vs CLEANSHOT-X-FEATURE-SPEC.md), SYSTEM-CORRECTNESS (CaptureKit/RecordingKit/coordinators), SECURITY-PRIVACY, PERFORMANCE, UI-CORRECTNESS (OverlayKit/EditorKit/App UI), UI-CONSISTENCY

---

## Executive Summary

The codebase is in very good health for its size: zero coupling between the four feature packages, a real pure-logic/UI split enforced by imports, zero TODO/FIXME debt, zero `try!`/`as!`/empty-catch, and genuinely good tests (pixel-level renderer assertions, real Vision OCR runs, injected clocks). The three most important things to address: (1) **silent data-loss paths** — screenshot saves and capture failures are swallowed with `try?`/`NSLog` and the save directory is never validated, so a moved folder or full disk loses captures with zero feedback; (2) **editor performance on large screenshots** — the canvas re-flattens the entire full-resolution document into a new `CGImage` on every mouse-move during a drag (the app's only 🔴); (3) **no CI** — 84 good tests exist but nothing runs them automatically. Beyond issues, the feature-gap analysis surfaced several high-value, low-effort wins (Repeat Previous Area, editor ⌘Z/⌘D bindings, capture history) that map cleanly onto the P4 roadmap.

## Health Scorecard

| Dimension                     | Score | Top Finding |
|-------------------------------|-------|-------------|
| Architecture                  | 🟢    | Excellent — zero kit-to-kit coupling; only drift is stale build docs in CLAUDE.md |
| Code Quality                  | 🟢    | Good — no debt markers; worst item is the swallowed save error |
| System Correctness (capture/recording) | 🟡 | Silent screenshot loss on write failure; save dir never ensured; writer-finish race |
| Security & Privacy            | 🟢    | Strong local posture; one medium: `sh -c` relaunch with interpolated bundle path |
| Performance                   | 🟡    | Editor canvas full re-flatten per drag tick on full-res images (🔴) |
| UI Correctness                | 🟡    | Editor Delete/`[`/`]` keys dead until first click; image-only buttons unlabeled for VoiceOver |
| UI / Design Consistency       | 🟡    | No shared design layer — 3 incompatible "dark pill" recipes; inconsistent error/copy feedback |
| Test Coverage                 | 🟡    | Deep where present; no CI, zero App-target coverage, Redactor tests don't assert obscuring |
| Dependencies                  | 🟢    | Zero external packages; tools-version 5.9 vs Swift 6 toolchain worth a bump |
| Documentation                 | 🟡    | CLAUDE.md build section contradicts reality (XcodeGen vs SwiftPM); README missing screenshots + 1 of 4 test commands |

---

## Critical Issues (Fix Now)

All 🔴/🟠 across dimensions, deduped:

1. 🔴 **Editor canvas re-flattens the whole document on every redraw/drag tick.** `Packages/EditorKit/Sources/EditorKit/EditorCanvasView.swift:149` calls `DocumentRenderer.render` unconditionally; `mouseDragged` sets `needsDisplay = true` per mouse-move (`:265`). `DocumentRenderer.render` (`DocumentRenderer.swift:8-32`) allocates a full base-image-sized RGBA context, re-rasterizes the full-res base image, redraws every annotation, and `makeImage()`s — per frame of a drag (~59 MB/frame on a 5K Retina shot). **Fix:** cache the flattened base (base + committed annotations), invalidate only on document mutation, composite just the in-progress preview during drags.

2. 🟠 **Silent screenshot loss on save failure.** `App/CaptureCoordinator.swift:183-189`: `guard let data = ImageEncoder.encode(...) else { return }` then `try? data.write(...)`. Encode-nil and write-throw both swallowed; in `saveOnly` mode that was the user's only copy. Flagged independently by 4 agents. **Fix:** do/catch + HUD error toast (HUD system already exists).

3. 🟠 **Save directory never ensured to exist.** Neither `CaptureCoordinator.save` nor `RecordingCoordinator` (`:152,186,194-202`) creates/validates `settings.saveDirectory` before writing; a user-chosen folder later deleted/renamed makes every save fail silently. **Fix:** `createDirectory(withIntermediateDirectories:)` before write, fall back + notify on failure.

4. 🟠 **Capture/OCR failures are silent.** `App/CaptureCoordinator.swift:84,98`: failures go to `NSLog` only — user presses hotkey, nothing happens, no feedback (incl. display-disconnected and sub-1px-selection cases). **Fix:** route errors through the existing HUD.

5. 🟠 **`ScreenRecorder` finish race.** `ScreenRecorder.swift:122-125`: `stop()` drains via `sampleQueue.sync {}` but then calls `markAsFinished()` on the main actor — an in-flight `append` that began during `stopCapture()` can land after finish (AVAssetWriter traps). **Fix:** serialize `markAsFinished()` inside `sampleQueue.sync`.

6. 🟠 **Mic-permission denial ignored.** `App/RecordingCoordinator.swift:137-139` discards `await MicCapturer.ensurePermission()`; recorder still adds a mic input (`ScreenRecorder.swift:100` swallows mic start with `try?`) → silent empty mic track, no user signal. **Fix:** clear `config.microphone` when denied; surface mic-start failure.

7. 🟠 **No CI.** No `.github/workflows` — 84 tests across 4 suites only run manually. **Fix:** one `macos-14` workflow running `swift build` + the four `swift run …Tests` commands.

8. 🟠 **Image-only buttons unlabeled for VoiceOver.** Quick Access buttons (`QuickAccessOverlayController.swift:127-135`), record-strip toggles (`RecordStripController.swift:36-58`), editor `IconToolButton`s — tooltip only, no `setAccessibilityLabel`. **Fix:** `button.setAccessibilityLabel(tip)` at each creation site.

9. 🟠 **Quick Access UI inconsistencies.** Unequal button widths between screenshot (5 buttons) and recording (4 buttons) cards — fixed 200px stack with `.fillEqually` (`QuickAccessOverlayController.swift:92-108`); Copy is silent on the overlay but shows a HUD from a pin (`CaptureCoordinator.swift:115` vs `:154`). **Fix:** equalize button sizing; one consistent copy-feedback rule.

---

## Architecture & Structure

**Score: Excellent.** Zero kit-to-kit imports (verified by grep) — all composition in `App/` via callback structs (`QuickAccessActions`, `PinActions`, etc.). Pure-logic layer is real: CaptureKit has no AppKit/SwiftUI imports; EditorKit's model/renderer are AppKit-free. `SettingsStore` is the single UserDefaults touchpoint.

Risks:
- 🟡 **Build-doc drift:** CLAUDE.md says XcodeGen + xcodebuild; reality is SwiftPM + `scripts/build-app.sh` (`project.yml` is an empty vestige). Update CLAUDE.md, remove/annotate `project.yml`.
- 🟡 **`EditorWindowController` is a 558-line god-object** — extract inspector/tool-pill builders (seam exists in `EditorChrome.swift`).
- 🔵 Two `SelectionOverlayController`/`HUDController` instances (one per coordinator) vs the deliberately shared Quick Access stack.
- 🔵 App target has zero unit tests (intentional per CLAUDE.md, but coordinators hold real branching logic).

## Code Quality & Patterns

**Score: Good.** Zero TODO/FIXME/HACK, zero `try!`, zero `as!`, zero empty catch; disciplined `[weak self]` (42 sites); consistent `@MainActor`.

- 🟡 Complexity hotspots: `EditorWindowController.swift` (558 ln), `EditorCanvasView.swift` mouse state machine (`:195-311`), `RecordingCoordinator.begin/stop` GIF-branch matrix (`:104-214`).
- 🟡 Duplication: displayID→NSScreen resolution in 3+ places; Quick Access presentation block duplicated across both coordinators; **`220×168` overlay size hardcoded in 3 files** (real coupling risk — centralize as `QuickAccessOverlayController.size`).
- 🟡 Stale stub plumbing: `CaptureCoordinator.editorPresenter` "Nil = stub" + "editor arrives in Plan 3" comments — editor shipped in v1; collapse to direct `presentEditor`.
- 🔵 `EditorCanvasView.onTextRequested` is effectively private with a misleading comment; MP4-fallback rename written twice in `RecordingCoordinator.stop()`.

## System Correctness & Edge Cases (CaptureKit / RecordingKit / coordinators)

Summary: 🔴 0 · 🟠 listed above (items 2,3,5,6) · 🟡 9 · 🔵 5.

Mediums worth fixing:
- 🟡 `stopForTermination` (`RecordingCoordinator.swift:219-231`) spins the run loop max 3s; a slow `finishWriting` on a long recording gets killed mid-write → truncated MP4. Use the async terminate-reply pattern or extend the deadline.
- 🟡 `CaptureService` hardcodes 2× capture scale (`:42-43,56-57`) while recording correctly uses `backingScaleFactor` — wrong on 1×/3× displays.
- 🟡 `ImageCropper.crop` uses `rect.integral` (rounds outward) — can include a 1px sliver outside the selection.
- 🟡 Even-dimension rounding can zero a 1px-tall area recording (`RecordingCoordinator.swift:134-135`) — floor at 2.
- 🟡 GIF temp MP4 leaks if `recorder.start` throws for GIF format (outer catch at `:167-172` never removes it).
- 🟡 `SystemScreenshotShortcuts.restoreNativeShortcuts` not guaranteed on crash/SIGKILL — uninstall while force-quit leaves native ⌘⇧4/5 disabled permanently (known sharp edge; documented).
- 🟡 Pre-first-video-frame audio buffers silently dropped (`ScreenRecorder.swift:161-164`) — few-ms audio gap at start.
- 🟡 Escalated from feature-gap agent: `captureFullscreen` hardcodes `CGMainDisplayID()` (`CaptureCoordinator.swift:53`) — multi-display users always get the main display; and `frontmostWindowID` (`:198`) relies on unguaranteed `SCShareableContent.windows` ordering — Capture Window may grab the wrong window.
- 🔵 `FileNamer` second-granularity names → rapid captures overwrite (no `withoutOverwriting`); GIFExporter has no max frame cap (30-min recording → 18,000 frames); keystroke overlay doesn't check `IsSecureEventInputEnabled` so typed passwords can appear in recordings (privacy-relevant — consider a guard).

## Security & Privacy

Summary: 🔴 0 · 🟠 0 · 🟡 1 · 🔵 2. Strong local posture: **zero networking confirmed** (no URLSession/sockets), pasteboard `clearContents()` before writes, temp files in per-user `0700` `$TMPDIR` under UUID dirs, timestamp-only filenames (no traversal surface), no screen content/OCR text ever logged.

- 🟡 **Shell-string injection in relaunch.** `App/PermissionManager.swift:27-30`: `/bin/sh -c "sleep 0.5; /usr/bin/open '\(Bundle.main.bundlePath)'"` — a single quote in the install path breaks quoting (path like `David's Apps` makes relaunch silently fail; crafted dir name = code exec). Fix: `Process` with `/usr/bin/open` + argv array, no shell.
- 🔵 Drag-out temp PNG cleanup is a 10s `asyncAfter` (orphaned if app quits inside the window). 🔵 Ad-hoc/self-signed signing = no hardened runtime/notarization (accepted, documented trade-off).
- Note: hardcoded keychain password in `scripts/` protects only a throwaway local signing cert — not a real secret, but generating it at first run would be cleaner.

## Performance

- 🔴 Editor canvas re-flatten per drag tick (Critical Issue #1).
- 🟡 `draw(_:)` ignores `dirtyRect` — full canvas redraw for any update (compounds #1). Same full-screen redraw pattern in `SelectionView` per drag tick (🔵 — GPU-composited, brief).
- 🟡 `Redactor.blur/pixelate` run CoreImage synchronously on the main actor at mouseUp (`EditorCanvasView.swift:288,293`) — hitch on large regions; offload like `runCaptureText` does for Vision.
- 🟡 Undo stack: ≤50 full document snapshots each retaining a base `CGImage`; multiple crops pin several full-res images. Bound by memory, not just count.
- 🔵 GIF thumbnail decodes all frames via `NSImage(contentsOf:)` (`RecordingCoordinator.swift:289`) — use `CGImageSourceCreateImageAtIndex(_, 0, _)`. 🔵 Serial frame decode in GIFExporter. 🔵 Clipboard copy round-trips full image on main actor.
- 🟢 Recording pipeline is sound: no per-frame copies, streamed GIF encode, paired teardown of all monitors/timers, zero idle cost.

## UI Correctness (OverlayKit / EditorKit / App UI)

Summary: 🔴 0 · 🟠 1 firm (a11y labels, Critical Issue #8) · 🟡 6 · 🔵 6. No leaks found — panels, monitors, observers, timers all torn down correctly.

- 🟡 **Editor keys dead until first click:** `window.initialFirstResponder` never set to the canvas, so Delete/`[`/`]` (handled in `keyDown`) no-op until the user clicks the canvas. Undo/redo work (key-equivalent path). Fix: `window?.initialFirstResponder = canvas`; also re-`makeFirstResponder(self)` after text commit (`EditorCanvasView.swift:419-424`).
- 🟡 **Counter badge placed by top-left, not centered on click** (`EditorCanvasView.swift:223-226` + `CounterAnnotation.swift:12-13`) — offset origin by `-diameter/2`.
- 🟡 Inline text field sits a few points lower than the committed annotation → visible jump on commit (`EditorCanvasView.swift:402-416` vs `TextAnnotation.swift:24`).
- 🟡 "Show keystrokes" toggle never re-checks after the user grants Accessibility — stays off until manually re-toggled (`SettingsView.swift:178-189`).
- 🟡 `RecorderWell` + custom swatch/tool buttons not keyboard-operable, no a11y role (`ShortcutRecorderField.swift:92-118`).
- 🔵 `applyStrokeColor` locks filled-rect fill alpha at 0.25; `launchAtLogin` is an onAppear snapshot; HUD toasts carry no VoiceOver announcement.

## UI / Design Consistency

Summary: 🔴 0 · 🟠 6 · 🟡 11 · 🔵 8. **Theme: no shared design-system layer** — every surface re-derives colors/radii/fonts/dark-pill recipes locally.

- 🟠 Three incompatible "dark pill" recipes: `.hudWindow` vibrant material (editor/HUD) vs flat `black@0.75` layer (keystroke overlay) vs opaque `windowBackgroundColor` (Quick Access card).
- 🟠 Two button vocabularies: custom-drawn dark-glass editor buttons vs stock `NSButton`s in overlays/strip; the editor action bar mixes three styles.
- 🟠 Silent error feedback + inconsistent copy feedback (merged into Critical Issues #4/#9).
- 🟡 `collectionBehavior` inconsistent: pins/bubble/strip join all Spaces; HUD toast and Quick Access overlay do **not** → won't appear over full-screen apps (`HUDController.swift:31-39`, `QuickAccessOverlayController.swift:55-63`). Surprising gap.
- 🟡 Record strip is a `.titled` panel with hidden title (chrome gap) while all sibling overlays are borderless; corner radii are one-offs (5/6/9/10/12/15/capsule); a dozen hand-tuned alpha-white values instead of tokens; no progress UI during GIF export/encode; Settings mixes `Form` (General/Recording) with a hand-rolled `VStack` (Shortcuts) and has a fixed 480pt width that visibly resizes between tabs; custom controls lack pressed/disabled states.
- 🔵 No type scale (10/11.5/12/13/19pt by hand); SF Symbol configs standardized only in the editor; "Done" bound to ⌘W.
- A live render would firm up: unequal QA button widths, record-strip chrome, settings tab-resize.

## Test Coverage & Quality

84 cases across 4 suites via the custom TestKit harness (executable runners — XCTest unavailable on CLT-only). Depth is genuinely good: pixel-level renderer assertions, real Vision OCR/QR runs, injected `Date`/`TimeZone`, zero flake indicators.

- 🟠 No CI (Critical Issue #7). 🟠 App target: 0 tests for 1,632 LOC — highest-value extraction: `SystemScreenshotShortcuts` symbolic-hotkeys dictionary transform (can clobber user prefs).
- 🟡 `RedactorTests` assert patch *dimensions* only — a regression returning the region unmodified (privacy failure) would pass. Assert pixels changed/variance dropped.
- 🟡 GIFExporter untested (only `GIFTiming` covered); OverlayKit tests cover only `PinGeometry`.
- 🔵 New test files must be hand-wired into `main.swift` — silent no-run footgun. 🔵 OCR tests depend on live Vision output (drift risk across OS versions).

## Dependencies & Package Health

**Zero external packages** — entire graph is Apple SDK + local path deps; TestKit correctly test-only; MIT license, no conflicts; nothing to lock.

- 🟡 `swift-tools-version: 5.9` everywhere vs Swift 6.2.3 toolchain — bumping to 6.0 would enable strict concurrency checking (would likely have caught the `ScreenRecorder` race, Critical Issue #5). Migrate package-by-package starting with TestKit/CaptureKit.
- 🟡 `.gitignore`s entire `.swiftpm/` — would suppress `Package.resolved` if a remote dep is ever added.
- 🔵 Keychain password hardcoded in scripts (see Security); rsa:2048 self-signed cert fine for purpose.

## Documentation & Developer Experience

- 🟠 **CLAUDE.md Stack section is wrong** (XcodeGen/xcodebuild vs actual SwiftPM + `scripts/build-app.sh`) — the file agents read first; one-sentence fix.
- 🟡 README test block lists 3 of 4 suites — `RecordingKitTests` silently omitted.
- 🟡 No screenshots/demo GIF in README for a visual end-user tool; no CONTRIBUTING.md; deploy flow (build → copy to /Applications → relaunch; `gh release create`) lives only in memory notes, not committed docs.
- 🟡 API doc gaps at coordinate-space boundaries: `CaptureService.capture(_:)` (main entry, no doc comment), `SelectionResult.globalRect` (Cocoa bottom-left origin — likeliest future bug source).
- 🟢 Strong: `HotkeyCombo`, `RecorderState`, `DocumentRenderer` flipped-context explanation, BUILD-NOTES.md honesty, thorough CHANGELOG.

---

## Recommended Improvements (Non-Blocking)

### Small (S)
- 💡 **Repeat Previous Area** (spec §1): store last `SelectionResult.globalRect`, add `HotkeyAction.repeatPreviousArea` + menu item. Highest value-per-effort feature in the scan.
- 💡 **Editor ⌘Z/⌘⇧Z menu/key bindings** — undo/redo currently title-bar buttons only. 💡 **⌘D duplicate**, **⌘⇧S save-as**, **⌘P print** (spec §3 fixed shortcut set).
- 💡 `scripts/test.sh` running all four suites with aggregate exit code; reference from README/BUILD-NOTES.
- 💡 GitHub Actions workflow (overlaps Critical #7).
- 💡 `.swift-format` config + format script; `.editorconfig`.
- 💡 Capture sound toggle (default off) — parity with native shutter sound.
- 💡 JPG quality setting (hardcoded 0.9 at `CaptureCoordinator.save`); filename-pattern setting (`FileNamer` fixed format, spec §11).
- 💡 Counter starting-number control; Large camera-bubble size.
- 💡 About/menu version display from `CFBundleShortVersionString`.
- 💡 Replace 2 force-unwrapped SF Symbols in `RecordStripController.swift:39,56` with the non-optional pattern used elsewhere.
- 💡 Self-timer capture (delay + fire).

### Medium (M)
- 💡 **Capture History + Restore Recently Closed** (spec §6): disk-backed ring buffer of recent captures + menu-bar history panel. Solves "dismissed before saving". Strictly local.
- 💡 **Highlighter + Pencil tools** (spec §3): freehand annotation types + path smoothing — most conspicuous editor gap.
- 💡 **Spotlight tool** (spec §3): dim-except-region; pairs with highlighter work.
- 💡 **Recording countdown + window-record target + pause/resume** (spec §2): strip has the toggle infra; needs window picker, countdown overlay, `RecorderState` pause transition.
- 💡 **`betterscreenshot://` URL scheme** (P5, spec §10): `CFBundleURLTypes` + `application(_:open:)` router onto existing coordinator methods — mostly thin routing, cheaper than its roadmap position implies. Exclude `action=upload`.
- 💡 **Hover-to-pick window capture** (spec §1) + **Hide Desktop Icons** (spec §8, Finder `CreateDesktop` toggle).
- 💡 Freeze Screen capture aid (snapshot display → select within static overlay).
- 💡 Migrate `SettingsStore` to `@Observable` (macOS 14 Observation framework).
- 💡 Collapse hand-rolled `[String:String]` serializers (`CaptureSettings`, `RecordingConfig`, `HotkeyBindings`) onto `Codable` — preserve the HotkeyBindings migration logic deliberately.
- 💡 Shared style layer: one dark-pill recipe, radius/spacing constants, semantic alpha-white tokens (addresses the UI-consistency theme).
- 💡 Honor Reduce Motion (`accessibilityDisplayShouldReduceMotion`) for overlay/HUD animations.
- 💡 String Catalog (`.xcstrings`) adoption for future localization.

### Large (L)
- 💡 **Background/wallpaper styling tool** (P4, spec §4): padding/gradient/rounded-corners/shadow "social post" mode — CleanShot's most visible differentiator.
- 💡 **Recording trim editor** (spec §2): trim start/end, mute, export via AVFoundation; entry from the recording Quick Access thumbnail. The largest remaining P2 gap.
- 💡 Scrolling capture (P4): frame-stitching is the hard part; lower frequency-of-use than the items above.

---

## Consolidated Recommendations

### Immediate (this sprint)
1. Fix the silent data-loss cluster: save do/catch + HUD errors, ensure save directory, HUD on capture/OCR failure (Critical #2–#4).
2. Cache the flattened editor base image (Critical #1).
3. Serialize `markAsFinished` with the sample queue; honor mic-permission denial (Critical #5–#6).
4. Add CI workflow (Critical #7) + fix CLAUDE.md build docs + add `RecordingKitTests` to README (one-line each).
5. A11y labels on image-only buttons; editor `initialFirstResponder` (Critical #8 + top UI medium).

### Short-term (1–2 months)
- Quick wins from the feature list: Repeat Previous Area, editor key bindings (⌘Z/⌘D/⌘⇧S), capture sound, JPG quality + filename settings.
- Capture History; recording countdown/window target/pause.
- Quick Access consistency fixes (button widths, copy feedback, `canJoinAllSpaces` on HUD/overlay).
- Strengthen RedactorTests (assert obscuring); extract + test `SystemScreenshotShortcuts` transform.
- Shell-free relaunch in `PermissionManager`; secure-input guard for keystroke overlay.
- Swift 6 tools-version migration (package-by-package).

### Long-term (roadmap)
- P4: background styling tool, scrolling capture, freeze screen.
- Recording trim editor.
- P5 URL scheme (build after Repeat/Hide-Icons land so the scheme can expose them).
- Shared design-system layer + `EditorWindowController` decomposition.
- Localization scaffolding if the repo attracts contributors.
