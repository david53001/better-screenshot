# BetterScreenshot — macOS → Windows parity (start here)

**Written 2026-09-30 on the Mac, for a fresh Claude Code session on David's Windows PC.** You have no other
context. This file is the entry point: it lists **every** change the macOS app gained since the Windows port
last synced, says what the Windows port has today, and tells you exactly what to build. Most of the detailed
specs already exist in the companion document **`docs/MAC-TO-WINDOWS-PARITY-v3.md`** (≈3,700 lines, written
by the Mac sessions while building each part — exact layouts, verbatim strings, persisted keys, pure logic
with test cases, WPF notes). This file points into it by part number ("v3 Part 5", "v3 §7.3") and fully
specifies everything the v3 document does not cover (§4 below).

## 0. Orientation

### 0.1 The app, the two codebases, the branches
- **BetterScreenshot** is David's free, local clone of CleanShot X: area / window / full-screen capture,
  a Quick Access card after each capture, an annotation editor, screen + GIF recording with a video editor,
  Capture Text (OCR + QR), Pin to Screen, and a capture History. **No cloud, ever.**
- **macOS app**: Swift (SwiftUI + AppKit), local packages under `Packages/` (CaptureKit, OverlayKit,
  EditorKit, HistoryKit, RecordingKit, DesignKit, TourKit) + the app target `App/`. It is the behavioural
  source of truth.
- **Windows port**: C# / .NET 9 + WPF under `windows/` (`windows/BetterScreenshot.sln`;
  `windows/src/BetterScreenshot.{Core,Capture,Editor,History,Recording,Platform,App}`,
  `windows/tests/BetterScreenshot.Tests`). Read `windows/README-win.md`, `windows/docs/PROGRESS.md` and
  `windows/docs/port-reference/0N-*.md` first. Recording uses **ffmpeg**. Build + deploy:
  `pwsh windows/scripts/publish-app.ps1` (republish + relaunch after runtime-visible changes — a plain build
  doesn't update the tray app David runs).
- GitHub: `https://github.com/david53001/better-screenshot` (public).

| Branch | What it holds |
|---|---|
| `windows-port` | The Windows port. **You work here.** Before this doc: tip `eb16ae0`. It split from the Mac history at `d2b5eb6` (Windows' own commits since then: freeze screen `ba2ee04`/`b7aa0ef`/`2d5a874`, temp-copy lifetime setting `eb16ae0`). |
| `origin/main` | The macOS app, v3.1.0 + the Opacity setting, tour polish, current-desktop windows, freeze screen (tip `d895045`). ≈230 commits the port doesn't have. |
| `origin/ocr-structure-math` | The Capture Text structure + maths rework (62 commits, unmerged WIP, last updated 2026-09-29; pushed 2026-09-30 — `git show origin/ocr-structure-math:<path>`). Its sources are also copied into `docs/mac-reference/src/ocr-structure-math/`. |

- Read any Mac file from `main` without switching branches:
  `git fetch origin && git show origin/main:Packages/OverlayKit/Sources/OverlayKit/QuickAccessContrast.swift`.
  List files: `git ls-tree -r --name-only origin/main Packages/ App/`. Mac tests live next to each package
  (`Packages/<Kit>/Tests/<Kit>Tests/`).

### 0.2 Files shipped with this document
| Path | What |
|---|---|
| `docs/MAC-TO-WINDOWS-PARITY-v3.md` | The companion spec: A.1–A.3, Parts 0–9, Window placement (merged from `main` + the Part 8 written on `ocr-structure-math`). |
| `docs/parity-v3/*.png`, `docs/reviews/…` | The screenshots the v3 document links to. |
| `docs/mac-reference/CHANGELOG-mac.md` | The Mac CHANGELOG (v1 → v3.1.0). |
| `docs/mac-reference/CLAUDE-mac.md` | The Mac root brief (feature history v2.5–v3.1 in prose with the exact rules). |
| `docs/mac-reference/PROGRESS-*.md` | Mac progress notes: v3 (`PROGRESS-v3.md`), native look, Opacity, tours+freeze, OCR (`PROGRESS-2026-09-28-ocr.md`). |
| `docs/mac-reference/reviews/2026-09-29-ocr-speed-review.md` | The latest OCR speed + accuracy review. |
| `docs/mac-reference/design-language/` | David's cross-app design language (from his MacStats repo): `README.md`, `opacity-setting.md`, `betterscreenshot-native-redesign.md`. The PC has no MacStats checkout. |
| `docs/mac-reference/src/ocr-structure-math/` | Swift sources + tests of Capture Text from the unpushed branch. |

### 0.3 Rules
- David's global rules: plan big, do small; verify (build + tests) before calling anything done; touch only
  what the task needs; keep `windows/docs/PROGRESS.md` updated as you go (the session can end at any
  moment).
- **The owner's PC runs a stretched, non-native gaming resolution** (e.g. 1600×1080 stretched). Everything
  must stay crisp there; fix blur in-app, never ask David to change resolution. `Screens.RealFramebufferSize`
  in the port already handles the capture side.
- Never suggest undervolting/downclocking.
- **Guided tours: only ever offered to NEW users, and only after they say "Show Me Around".** Existing users
  (David!) must never be prompted. Never weaken this (v3 §7.1).
- **Capture History has no time expiry** — count cap only. Don't add an age prune.
- Background/wallpaper styling of screenshots was dropped by the owner — don't build or propose it.

### 0.4 Terms
- **Quick Access card** — the floating thumbnail after a capture (Copy / Save / Annotate / … buttons).
- **HUD** — a small dark floating panel over other apps: toast, record strip, recording pill, countdown,
  selection size chip, window-picker title chip, keystroke overlay, pin close button, card badge.
- **Docked panel** — a panel that only sits on the editor's own dark window (tool pill, inspector, trim card).
- **Material** (macOS) — a system blur of what's behind a window. Windows 11 equivalents: **Mica** / **Acrylic**
  via `DwmSetWindowAttribute(DWMWA_SYSTEMBACKDROP_TYPE = 38)`.
- **Contrast N:1** — WCAG 2.x contrast ratio; 4.5:1 is the minimum for normal text.
- **Tour / step / anchor / tag** — see v3 §7.2.
- **Vision** — Apple's OCR framework. Windows uses **Windows.Media.Ocr** (`OcrEngine`).

---

## 1. Summary — every Mac change since `d2b5eb6`, and the Windows status

Status: **MISSING**, **PARTIAL**, **DONE**, **WIN-AHEAD** (Windows has something the Mac doesn't), **N/A** (Mac-only).
Priority P1 (do first) / P2 / P3.

| # | Feature (Mac version, date) | Windows today | Prio | Spec |
|---|---|---|---|---|
| 1 | Windows→Mac parity P1–P3 (July): JVoice-style Settings, full-bleed Quick Access card, auto-dismiss, text chip, clamps, history cap 100, play sound | **DONE** (ported *from* Windows) | — | — |
| 2 | Quick Access hold duration 30 s…30 m…∞ (v2.5.0) + "∞" label (v2.6.1) | **DONE** (`Capture/OverlayDismissScale.cs`, mirrored in `a15d286`) — verify the ∞ label | P3 | §4.1 |
| 3 | Temp-file retention 10 s…1 h…∞, default 5 min (v2.7.0) | **DONE 638a152** — the Mac stops | P2 | §4.2 |
| 4 | Refocus the previous app after a screenshot (v2.8.0) | **DONE `00ea02e`** | P1 | §4.3 |
| 5 | History multi-select (⇧/⌘-click), multi-file drag-out, batch Copy/Delete/Reveal, confirmed bulk delete (v2.8.0) | **DONE 924239b** — Ctrl/Shift multi-select, multi-file drag-out, batch Copy/Delete/Show in Explorer, confirmed bulk delete | P2 | §4.4 |
| 6 | History UI-review fixes H1–H4 (full labels, size/length details, helpful empty state, Clear All in a ⋯ menu) | **DONE 924239b** — H1 min width 660, H2 size/length from headers + play badge, H3 empty state names the live chord, H4 Clear All in ⋯ | P2 | §4.4 |
| 7 | Guaranteed Quick Access button contrast (v2.9.0) | **DONE `87f528c`** | P1 | §4.5 |
| 8 | Quick Access card **Pin button removed** (v2.9.0) | **DONE `c0805ee`** | P2 | §4.5 |
| 9 | Capture Text: warm OCR during the drag, explicit languages, upscale < 2× (v2.10.0) | **DONE `e9f5511`** | P2 | §4.6 |
| 10 | Capture Text paragraph reflow `TextReflow` (v2.11.0) | **DONE `b82e20a`** | P1 | §4.6 |
| 11 | Capture Text structure + maths rework, "Recognize math" setting (unmerged Mac WIP) | **PARTIAL — maths passes deferred (Mac WIP)** 09b2dc0 — §8.2 clipboard format: tables (tabs, grid lines), code, lists, hyphen word list, QR dominance; scripts/fractions/display maths + Recognize math setting deferred | P2 | v3 Part 8 + §4.13 |
| 12 | Universal build + one-line installer; installer reports old → new version (v2.10, v3.1.0) | **N/A** for the Mac script; Windows analogue optional | P3 | §4.8 |
| 13 | Bundle id `com.betterscreenshot.mac`, macOS 26 menu-bar fix | **N/A** | — | — |
| 14 | Text tool: fonts, text boxes, in-place editing, "line above disappears" fix (2026-09-24) | DONE 5748be5 | P1 | v3 A.1 |
| 15 | Floating recording pill v1 + "Show recording controls in the video" | DONE e054f98 | P1 | v3 A.2 |
| 16 | Trim window v1 (lossless trim/mute, copy or replace) + Cancel restores the card | DONE 8f29067 | P1 | v3 A.3, Part 0 |
| 17 | Editor right-side inspector, hint line, zoom, single-key tools, per-object opacity, recent colours, eyedropper | DONE 5748be5 | P1 | v3 Part 1 |
| 18 | Text v2: corner scaling, background, B I U S, outline, shadow, presets | DONE 5748be5 | P1 | v3 Part 2 |
| 19 | Redaction strength + Blur/Pixelate/Black-out conversion + stale-patch fix; **Highlighter (H)**; **Spotlight (S)** | DONE 5748be5 | P1 | v3 Part 3 |
| 20 | Record strip v2 (labelled buttons, device menus, level meter, hint line) | DONE 72788e3 | P1 | v3 Part 4 |
| 21 | Live recording pill v2 (mute mic/system, camera, switch window/area, restart, discard) | DONE e054f98 | P1 | v3 Part 5 |
| 22 | Video editor v2 (cut/split, per-segment speed + mute, GIF export) | DONE 8f29067 | P1 | v3 Part 6 |
| 23 | UI-review fixes for editor / recording / overlays (E1–E12, V1–V5, X1–X6, Q1–Q2, O1–O3, T1–T6, C1–C5) | **MISSING** | P2 | v3 Parts 1–6 + §4.7 |
| 24 | Windows open centred on the screen in use, reopen as last closed | **MISSING** | P2 | v3 "Window placement" |
| 25 | Guided tours + ⓘ on every window + Help & Tours + Welcome question | **DONE** 6cf5ae8 (+5594d33 engine) | P1 | v3 Part 7 |
| 26 | Tours review fixes (colours #C62D22, counter, placement, shorter tours) | **DONE** 6cf5ae8 (leader obstacle routing simplified) | — | v3 §7.3–§7.8 |
| 27 | Native look (MacStats design language) v3.1.0 | DONE b91c187 | P1 | v3 Part 9 |
| 28 | **Opacity setting** (2026-09-30) | DONE b91c187 | P1 | §4.9 |
| 29 | Tour outline follows each control's shape; Settings tour **Opacity** step with live demo | **MISSING** | P2 | §4.10 |
| 30 | Windows open on the current desktop (Spaces → Windows virtual desktops) | **MISSING** | P2 | §4.11 |
| 31 | Freeze screen while selecting (Mac 2026-09-30) | **WIN-AHEAD** (Windows built it first, with a setting and window mode) | — | §4.12 |

---

## 2. Not to port
- Bundle id / ControlCenter blocked-host fix, macOS 26 menu-bar icon investigations, the Mac signing
  keychain rules, universal (arm64+x86_64) builds — macOS-only.
- Liquid Glass specifics (macOS 26) — v3 Part 9 already says: use the dark tinted surface, not glass.
- Anything the Mac *removed*: v2.6.0's age-based History expiry (fully reverted), the pure-black Settings.

## 3. Order of work (recommended)
1. **Correctness / small wins**: §4.5 contrast guarantee + Pin removal, §4.3 refocus, §4.6 reflow + OCR
   warm-up/upscale, §4.2 temp retention decision.
2. **Editor** (v3 A.1, Parts 1–3) — the biggest user-visible gap ("the amount of shapes, the
   customizability"): inspector panel first (everything else plugs into it), then Text v2, redaction
   strength, Highlighter, Spotlight.
3. **Recording** (v3 A.2, A.3, Parts 0, 4, 5, 6): pill → strip → trim → video editor.
4. **Native look** (v3 Part 9) **+ Opacity** (§4.9) — do together; they share one surface recipe.
5. **Window placement** (v3) + current desktop (§4.11).
6. **Tours** (v3 Part 7 + §4.10) — last, because they anchor on the final UI of every window.
7. History (§4.4), shell fixes (§4.7), Capture Text rework (v3 Part 8 + §4.13) when the Mac branch settles.
Each item: build → tests → publish + relaunch → try it → note in `windows/docs/PROGRESS.md` → commit.

---

## 4. Specs for everything the v3 document does not cover

### 4.1 Quick Access hold duration (v2.5.0) + ∞ label (v2.6.1) — DONE, verify
Mac: Settings → Quick Access Overlay → "Auto-dismiss after" runs over an ordered stop table
`OverlayDismissScale`: **30s · 1m · 2m · 5m · 10m · 15m · 30m · Never**; slider position = stop index;
a persisted value that isn't a stop snaps to the nearest; default `0` = Never; the Never stop is displayed
as **`∞`** (`neverLabel`). Windows mirrored it (`windows/src/BetterScreenshot.Capture/OverlayDismissScale.cs`,
`NeverLabel`). Check the Settings row shows "∞" and tests cover the snap.

### 4.2 Temp-file retention (v2.7.0) — PARTIAL, pick one behaviour
- **Mac**: Settings → Capture → **"Keep cached files for"**: how long the temporary PNG written for a
  drag-out, or for putting a file path on the clipboard, survives. Stops (`TempFileRetentionScale`):
  **10s · 30s · 5m · 10m · 30m · 1h · ∞**; stored as `tempRetentionSeconds` (default **300**; `0` = ∞);
  slider position = index. Files live in `$TMPDIR/BetterScreenshot-<UUID>/`; the sweeper deletes only
  directories with the `BetterScreenshot-` prefix older than the setting (so it never touches an in-progress
  GIF written straight to the temp root), **every 5 s and at launch** (the launch sweep cleans folders
  orphaned by a quit). Pure + tested: `TempImageWriter.cleanExpired(in:olderThan:now:)`.
- **Windows**: `TempRetentionScale.cs` — **5–30 minutes**, default 5 (`eb16ae0`, "make the temp-copy lifetime
  a 5–30 minute setting"; note `windows/docs/temp-retention.md`). That was a deliberate Windows decision a
  day after the Mac one.
- **Do**: ask David which he wants (one short question). If "match the Mac": replace the scale with the Mac
  stops, map the stored minutes to the nearest stop, keep the prefix-scoped sweep + launch sweep. If he says
  keep Windows' range, add only the ∞ stop if he wants it. Either way make sure the sweep also runs at launch.

### 4.3 Return focus to the previous app after a screenshot (v2.8.0) — MISSING (P1)
- Why: showing the selection overlay activates BetterScreenshot (it needs keyboard focus for Esc); after the
  capture the user was left in BetterScreenshot instead of the app they were working in.
- Mac rule (`CaptureCoordinator.rememberFrontmostApp()` / `restoreFrontmostApp()`, pure predicate
  `FocusRestore.shouldRestore(previousBundleID:ownBundleID:)` in CaptureKit):
  1. Every screenshot entry point records the frontmost app **before** anything is shown.
  2. After the pixels are grabbed (never before — the restored window order must not leak into the shot)
     reactivate it.
  3. Never record BetterScreenshot itself as "previous"; **never clear** the remembered app on restore — so a
     second capture hotkey pressed while a selection is already open keeps the real target.
  4. Exception: if BetterScreenshot is frontmost **and** no selection is up (capture started from one of our
     own windows), clear it — nothing to hand back to.
  5. Recording flows are not covered.
- Windows: record `GetForegroundWindow()` (skip if it belongs to our process — compare
  `GetWindowThreadProcessId` with `Environment.ProcessId`) at the hotkey; after the capture completes,
  `SetForegroundWindow(prev)` (the foreground lock is satisfied because we are the foreground process at
  that moment; if it fails, use the `AttachThreadInput` trick or `AllowSetForegroundWindow` from the hotkey
  path). Put the pure rule in `BetterScreenshot.Capture/FocusRestore.cs` with the Mac's tests
  (`git show origin/main:Packages/CaptureKit/Tests/CaptureKitTests/…FocusRestore…` — search the test
  `main.swift` for `shouldRestore`). Test by hand: capture from a browser → the browser has focus afterwards;
  press the area hotkey twice → still returns to the browser; full-screen games: check the freeze-screen path
  (§4.12) still captures before the game loses focus.

### 4.4 History: multi-select, drag-out, batch actions, H1–H4 (v2.8.0 + UI review) — MISSING (P2)
- **Selection arithmetic** (pure, `Packages/HistoryKit/Sources/HistoryKit/HistorySelection.swift`, port 1:1
  to `BetterScreenshot.History`):
  ```
  click(id, modifier, order, state):
    none    → selected = {id}, anchor = id
    command → toggle id in selected, anchor = id        (Ctrl on Windows)
    shift   → if anchor is missing/deleted: behaves like none
              else selected = order[min(a,i)...max(a,i)], anchor unchanged
  dragStart(id): if id already selected → drag the whole selection; else click(id, none) first
  ```
  `order` = displayed order (newest first). Plain clicks are applied on **mouse-up**, so a mouse-down on an
  already-selected item can start a multi-file drag without collapsing the selection.
- **Drag-out**: dragging drags every selected entry's file (`DataObject` with `DataFormats.FileDrop` =
  string[] of paths); **Copy** puts all selected images/files on the clipboard; **Delete** deletes all
  selected **after a confirmation** when more than one is selected; **Show in Explorer** reveals them
  (`explorer.exe /select,` for one; `SHOpenFolderAndSelectItems` for several).
- **H1**: min window width 660 pt; action buttons never truncate ("Annotate", "Edit Video…", "Show in
  Finder" → "Show in Explorer").
- **H2**: each cell shows the screenshot's pixel size (read from the PNG header only) or the recording's
  length (MP4 header / GIF frame delays, `MediaDuration`), cached per entry; recording thumbnails get a
  play badge. Pure text: `MediaInfoText` (duration / pixel size / badge "0:42 · MP4").
- **H3**: empty state names the user's live Capture Area shortcut: "Press ⇧⌘4 to take your first
  screenshot…" (Windows: the live chord, e.g. "Press Ctrl+Shift+4 …"), or says History is off when it is
  (pure `HistoryEmptyState`, tested).
- **H4**: "Clear All…" moves out of the action row into a **⋯** menu as **"Clear All History…"**
  (destructive). Windows today has a red "Clear All" button in the row (`HistoryWindow.xaml:12`) and a
  **Pin** button — keep Pin in History (it is where Pin to Screen lives now, see §4.5).
- History also got the native look (translucent window, cells highlight on hover) — v3 Part 9.

### 4.5 Guaranteed Quick Access button contrast + Pin button removal (v2.9.0) — MISSING (P1)
- **Why**: the card's overlaid buttons chose a light/dark glyph from the *mean* luminance of the image's
  bottom band. A mean can't describe a bimodal band (white headline on a dark background), so buttons were
  unreadable on real screenshots. Windows `windows/src/BetterScreenshot.App/Overlays/QuickAccessContrast.cs`
  still has that mean logic.
- **Mac design** (four pure, tested pieces in `Packages/OverlayKit/Sources/OverlayKit/` — read them with
  `git show origin/main:…`, port 1:1 to `BetterScreenshot.App/Overlays/` or a pure project):
  1. `SRGB.swift` — WCAG 2.x relative luminance with gamma expansion
     (`c ≤ 0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4`; `L = 0.2126R + 0.7152G + 0.0722B`) and contrast
     ratio `(L1+0.05)/(L2+0.05)`.
  2. `BandLuminance.swift` — the **p10 and p90** luminance percentiles over an RGBA8 buffer (not the mean).
  3. `AspectFillMap.swift` — maps a rect in card space to the **source pixels actually drawn there** under
     aspect-fill (`UniformToFill` in WPF); the old sampler read pixels that aspect-fill had cropped off.
  4. `QuickAccessContrast.plan(for:)` — for each glyph tone (white / black) solve in closed form the scrim
     alpha needed so the glyph clears **4.5:1** (`targetContrastRatio`) against the **worst** background
     in the band (p10 or p90 as appropriate), pick the cheaper tone, clamp the alpha to
     **[0.18 (`minScrimAlpha`), 0.85 (`maxScrimAlpha`)]**.
- **Controller rules** (`QuickAccessOverlayController`): build the button row **first**, so the sampled rect
  is the row's final on-screen frame; sample at **device resolution** (downsampling box-filters a white
  headline into its surround — measured 0.91 → 0.33 luminance on the real failing case, which would have
  shipped a fix that passed its own test at 1.55:1 on screen); the scrim holds `plan.scrimAlpha` **flat**
  from the row's top edge to the card's bottom (no fade under the glyphs). The guarantee holds only while
  the scrimmed region ⊇ the sampled region — never narrow the scrim or widen the sample without redoing
  the argument.
- **Delete** the old mean-based API (`averageLuminance`, `tone(forLuminance:)`, `lightThreshold`).
- **Pin button removed from the card**. Pin to Screen stays reachable from the tray menu ("Pin from
  Clipboard") and History. Windows: remove the `MakeButton("pin", "Pin to screen", …)` line in
  `Overlays/QuickAccessWindow.xaml.cs:69` and `OnPin` plumbing that becomes unused.
- **Tests**: port the Mac cases for `SRGB`, `BandLuminance`, `AspectFillMap`, `QuickAccessContrast` (bimodal
  band → tone + alpha; uniform white → dark glyph with min alpha; alpha clamp at 0.85).
- **Verify**: screenshots of a white page, a black page, a white headline on dark, a photo → every button
  glyph ≥ 4.5:1 against its scrimmed background (measure from a screen capture).

### 4.6 Capture Text: warm-up, languages, upscale (v2.10.0) + paragraph reflow (v2.11.0) — PARTIAL/MISSING (P1)
Windows today (`windows/src/BetterScreenshot.Platform/TextRecognizerService.cs`): `OcrEngine.TryCreateFromUserProfileLanguages()`,
`RecognizeAsync`, then `result.Lines.Select(l => l.Text)` joined — no boxes used, no reflow, no warm-up,
no upscaling. QR first (Recognition.cs).
1. **Warm-up during the drag**: Mac Vision's cold start was 0.5–1 s (returns after ~20 s idle); the model is
   warmed when the selection overlay appears so it loads while the user drags. On the ocr branch warm-up
   OCRs a real word image ("Warm up") because a blank image didn't load the model. Windows: create the
   `OcrEngine` and run one tiny `RecognizeAsync` on a rendered "Warm up" bitmap when the Capture Text overlay
   opens; measure first-capture time before/after.
2. **Explicit languages**: auto-detect leaked CJK punctuation into Latin text; the Mac maps the user's system
   languages to supported OCR languages with an en-US fallback. Windows: `OcrEngine.TryCreateFromLanguage(new
   Language(tag))` for the first user-profile language that `OcrEngine.IsLanguageSupported`, else en-US.
3. **Upscale captures below 2× pixel density** before OCR (at 1× the Mac OCR fragmented lines and ran ~60 %
   slower). Windows (most monitors are 1×!): upscale 2× (high-quality bicubic) when the capture's DPI scale
   < 2 and the result stays within `OcrEngine.MaxImageDimension`; measure accuracy + time — Windows OCR may
   behave differently; keep it only if it helps.
4. **Paragraph reflow** (`Packages/CaptureKit/Sources/CaptureKit/TextReflow.swift` on `main`; a much larger
   version is on the ocr branch — §4.13): rebuild paragraphs from per-line boxes so a wrapped bullet pastes
   as one line. A line continues the block above only if **all** hold:
   - it overlaps the block's column horizontally;
   - spacing matches the block: gap ≤ **1.0×** line height, pitch ≤ **1.25×** the block's median pitch,
     height ratio ≤ **1.5**;
   - it doesn't start with a list marker;
   - the previous line **wrapped**: its width plus the next line's first word would overflow the column's
     right edge (max right of all x-overlapping lines). This fit test keeps code line-per-line (known
     limit: a code block's longest line merges with its follower).
   Thresholds were measured on a real slide (intra-paragraph pitch jitter ≤ 1.07×, paragraph break 1.33×).
   Don't filter by OCR confidence (Vision scored junk at 1.00; Windows OCR gives none anyway).
   Windows: use `OcrLine.Words[i].BoundingRect` (union per line) as the line boxes, run the pure
   `TextReflow` (port it + `TextReflowTests`), then join.

### 4.7 Shell UI-review fixes not described in the v3 parts (2026-09-25) — MISSING (P2)
(Editor E*, recording/video V*, and tour items are in v3 Parts 1–7. These are the rest.)
- **X6 — an icon on every tray-menu item** (Mac: SF Symbol on each menu-bar item so titles line up; Record/Stop
  and Pause/Resume swap their icon with the title). Windows: `MenuItem.Icon` with the port's icon set on
  every item of `App/Tray/TrayIcon.cs`'s menu.
- **O1–O3 — Welcome "You're all set!" page**: shortcuts in an aligned grid (keys right-aligned against
  left-aligned descriptions) built from the user's **live** bindings in menu order (pure `HotkeyCheatSheet`
  in CaptureKit, tested; Capture Text included, unbound actions omitted); every page of the window is a
  fixed **440×380** with content centred so it doesn't jump. Windows: `App/Onboarding/`.
- **T1 — ⓘ help popovers wrap** (fixed 280-pt text column) instead of truncating after one line.
- **T2–T6, C3 — Settings wording/layout**: shortcuts help says "Click a shortcut, then press…" (there is no
  Change button); the shortcut field outlines on hover with a hand cursor + tooltip; Recording is split into
  **RECORDING** (format, frame rate, countdown, sources, camera size) and **IN THE VIDEO** (mouse cursor,
  clicks, keystrokes, controls); the History card's size note sits on its own line under "Clear History…";
  "Show mouse cursor" → **"Mouse cursor" Shown/Hidden** (same key `showsCursor`); "Show stop button in
  recording" → **"Show recording controls in the video"**; "Capture Full Screen" wording everywhere; help
  examples use the platform modifier order. (Column layout after later changes — see v3 §7.8 and Part 9.)
- **X1/C1 — countdown**: the digit is optically centred (baseline pinned so the cap height is centred) and a
  secondary line says **clicking skips it** ("Click to start now").
- **X2** — the area-selection size readout is a dark HUD chip placed **outside** the selection's corner
  (below it near the top edge), monospaced digits (pure `OverlayLabelLayout`, tested).
- **X3** — Pin's close button sits on a dark HUD circle (visible on light pins).
- **X4** — the window picker's title chip is capped to the window width, title truncates with an ellipsis.
- **X5** — toasts are dark HUDs and take an optional icon (copy / text / warning).
- **Q1** — the Quick Access card draws its picture once (no double decode).
- **Q2** — recording cards show a top-left badge "0:42 · MP4" (length read from the file header).

### 4.8 Installer / version report (v2.10.0, v3.1.0) — optional
Mac: `curl … scripts/install.sh | bash` downloads the latest release, replaces `/Applications/…`, keeps
settings/permissions; since v3.1.0 it prints "old → new version" and does nothing when already up to date.
Windows has `windows/scripts/publish-app.ps1` for David's own machine only. Only if David wants a public
Windows install/update path: a PowerShell one-liner (`irm …/install.ps1 | iex`) that downloads the latest
GitHub release zip, replaces the app folder, keeps `%APPDATA%` settings, and prints old → new / "already up
to date". Ask before building it.

### 4.9 Opacity setting (Mac 2026-09-30, `bb080cd`) — MISSING (P1; do with v3 Part 9)
The same setting exists in David's MacStats and JVoice (JVoice's Windows doc has its own version); the
shared spec is `docs/mac-reference/design-language/opacity-setting.md`.
- **Setting**: `CaptureSettings.uiOpacity`, Double 0…1, **default 0.5**, persisted key **`uiOpacity`** in the
  capture-settings dictionary (Windows: add to `BetterScreenshot.Capture/CaptureSettings.cs`
  `ToDictionary`/parse, clamp to 0…1, junk/NaN → 0.5; test default, round-trip, clamp, junk).
- **UI**: a new **APPEARANCE** card at the bottom of the third Settings column: "Opacity" label + ⓘ, a small
  bordered **Default** button (disabled when the value is 0.5), a continuous slider with caption-size
  secondary end labels **"Transparent"** (left) and **"Opaque"** (right), and the help line **"How much of
  what's behind the app shows through its windows and panels."** Instant-apply. The ⓘ text (verbatim):
  title "Opacity"; body "How see-through BetterScreenshot's windows, panels and floating controls are.
  Transparent lets more of what's behind them show through; Opaque makes them solid."; example "Default puts
  it back in the middle. Floating controls always keep enough dark tint that their text stays readable over
  a white page."
- **Mapping** (pure `OpacityCurve`, `Packages/DesignKit/Sources/DesignKit/UIOpacity.swift` — port 1:1):
  piecewise-linear through each surface's (0, 0.5, 1) points:

  | Surface | 0 (Transparent) | 0.5 (default) | 1 (Opaque) |
  |---|---|---|---|
  | Floating HUD: black tint alpha over the blur | **0.22** (clamp) | **0.42** | 1.0 and the colour becomes white 0.13 (solid dark grey) |
  | Docked panel (editor tool pill, inspector, trim card): blur alpha / tint | 0.5 / 0 | 0.85 / 0 | 1 / solid dark grey |
  | Window (Settings, editor, video editor, **History**): window-background colour layer over the material | **0.15** (clamp) | **0.52** | 1.0 (solid) |
  | Settings card fill (primary text colour at) | 0.03 | 0.04 | 0.05 |

  Hairlines don't change (cards: primary at 0.08, 0.5 pt; HUDs: white at 0.10).
- **Live**: one app-wide observable value (`UIOpacity.shared`); every HUD, docked panel and window subscribes
  and re-applies immediately (dragging the slider with a recording running updates the pill live). History
  now also uses the window material (it was opaque).
- **Contrast contract (measured on the Mac over an opaque white page)**: HUD white text 3.17:1 at 0,
  **4.86:1 at 0.5** (secondary 80 %-white 3.78:1), 13.96:1 at 1; Settings card primary/secondary in dark over
  white 4.90/3.06 at 0.5. On Windows the backdrop differs, so **re-measure** (screen capture over a white
  page, a black page and a busy page at 0 / 0.5 / 1) and adjust the anchors until: default primary ≥ 4.5:1,
  secondary ≥ 3:1; at 0 primary ≥ 3:1 over white. The ratios are the contract; the alphas are Mac-calibrated.
- **Don't touch** the Quick Access card's scrim/contrast (§4.5) or the tour tag colours — they're excluded.
- Known follow-ups on the Mac: not checked with "reduce transparency" on (Windows: Settings → Personalisation
  → Colours → Transparency effects off → backdrops go solid; our layers only add on top, so it should stay
  solid — check).

### 4.10 Tour polish (Mac `5764cc9`) — MISSING (with v3 Part 7)
- **Outline follows the control's shape**: the outline box's inner radius = the control's own corner radius +
  **4** (`boxPadding`, concentric), **6** for square controls (`TagStyle.boxRadius`), never rounder than a
  capsule of the box: `radius = anchorRadius > 0 ? anchorRadius + 4 : 6; radius = clamp(radius, 0,
  min(w,h)/2)`. Controls provide their radius: the editor tool pill (15), Settings' Keyboard Shortcuts card
  (10), the History cell (12); a padded panel section without its own background is outlined around its
  **content**, not its padding. WPF: read `Border.CornerRadius` of the anchored element (or an attached
  property `Tour.CornerRadius`).
- **Settings tour — new step 3 "Opacity"**, anchor `settings.opacity` (the Appearance card's content), body
  verbatim: **"Watch the app turn see-through, then solid. Drag to choose; Default resets it."** While it
  shows, the real slider sweeps every window and panel through the pure path `OpacityDemoPath`
  (`Packages/DesignKit/Sources/DesignKit/OpacityDemo.swift`):

  | Leg | Duration (s) | Target |
  |---|---|---|
  | hold (the tag appears first) | 0.6 | user's value |
  | down | 2.4 | 0 |
  | hold | 0.8 | 0 |
  | up | 3.2 | 1 |
  | hold | 0.8 | 1 |
  | back | 1.6 | user's value |
  | rest | 1.0 | user's value |

  Period 10.4 s, looping; each leg eased with smoothstep `x²(3 − 2x)`; start value NaN → 0.5, clamped to 0…1.
  The demo writes a **preview** value (`SettingsStore.opacityPreview`) that is pushed to the live surfaces but
  **never saved**; when the step leaves, the saved value is restored; if the user drags the slider or presses
  Default, the demo ends and keeps the user's value. The next step is "Keyboard shortcuts" — "Click any
  shortcut, then press new keys to change it. Esc cancels." Settings tour **version stays 1** (existing
  tour users aren't re-shown it). Port the path + its tests (`value(at:0) == start`, value at 3.0 s == 0,
  at 7.0 s == 1, loops at 10.4 s).
- v3 §7.8's Settings tour table predates this: insert the Opacity step as step 3 and renumber.

### 4.11 Windows open on the current desktop (Mac `c3af088`) — MISSING (P2)
Mac: every window gets "move to the active Space"; fixed-size windows (Settings, Welcome) may show over a
full-screen app; the remembered windows (editor, History, video editor) may not open on top of a full-screen
app's Space; a window still open on another desktop is **moved here and re-centred under the pointer**.
Windows equivalent — **virtual desktops**: before showing an existing window, check
`IVirtualDesktopManager.IsWindowOnCurrentVirtualDesktop(hwnd)`; if false, move it with
`IVirtualDesktopManager.MoveWindowToDesktop(hwnd, currentDesktopId)` — the current desktop's id is obtained
from a window you know is on it (e.g. a fresh hidden helper window, or the foreground window via
`GetWindowDesktopId(GetForegroundWindow())`). This COM interface (`CLSID_VirtualDesktopManager`
{AA509086-5CA9-4C25-8F95-589D3C07B48A}) is documented and stable; it can only move windows of your own
process, which is all we need. Then re-centre on the monitor under the cursor (v3 "Window placement"). Test:
open Settings, switch to desktop 2 (Win+Ctrl+→), open Settings from the tray → it appears on desktop 2.

### 4.12 Freeze screen — WIN-AHEAD; reconcile only these points
- Windows (`ba2ee04`, `b7aa0ef`, `2d5a874`, `windows/docs/freeze-screen.md`): still grabbed per monitor at the
  hotkey; overlays paint the still; crop from it; **setting `freezeScreen` (default on)**; applies to Capture
  Area, **Capture Text and Capture Window**; recording target picking passes `freeze: false`; opaque frozen
  overlays; square corners; still laid out at pixel size ÷ DPI (stretched-resolution safe); every crop falls
  back to the live capture.
- Mac (`70a1cf9`, a day later): **always on, no setting**; Area + Capture Text only (window capture and
  recording unchanged); falls back to live if the freeze fails; ~210 ms cold to grab all displays on a MacBook.
- Nothing to port. Keep Windows' setting and window mode. (If anything, the Mac could gain the setting — not
  your job on Windows.)

### 4.13 Capture Text rework (unmerged Mac branch `ocr-structure-math`) — spec in v3 Part 8, plus this
v3 Part 8 (§8.1–§8.9) specifies the "Recognize math" setting, the clipboard format, every rule and why,
the pipeline stage by stage, what's pure, where it goes, platform notes and the speed fixes. It was written up
to commit `bbbe646`. Six later Mac commits (all "0 outputs worse" on the 188-case corpus; 140/188 pass) add:
- **W01** `v² = u² + 2as`: the glyph alignment's "typical letter gap" is the **lower third** of the gaps, not
  the median (a spaced equation has as many word gaps as letter gaps).
- **W01** `½at²`: the low `2` of a `½` isn't a subscript (`vulgarPieces`); x-height evidence
  (`Line.hasXHeight`) counts only glyphs on the baseline; uppercasing (`s` → `S`) needs it.
- **W08/M06** `Sₙ = n/2(…)`: `segment` picks, among gaps within 80 % of the cut, the cuts whose words have the
  OCR's word lengths; a single OCR line whose DisplayMath rebuild has a stacked fraction takes that rebuild;
  row joins drop spaces inside brackets; a recovered line never gains a `?`.
- **W09** `m s⁻²` at 1×: when the first alignment was a misread, rebuild the word from the re-read's own
  alignment (recursive `glyphTexts(…, faithfulTo:)`, still no-harm-checked against the OCR's read); a touching
  `0⁸` splits (raised tail 0.35 cap); a letter on a script glyph right after a wide glyph that took one digit
  costs +1 (`2x²` read as `2x`).
- **Spacing on relation lines** (`TextReflow.separatedVariables`): `arex = 1andx` → `are x = 1 and x`,
  `2abcosC` → `2ab cos C`, `detA` → `det A`; never splits a real word (`Using`, `tacos`, `cost`).
- **V08** `2π`: a `π` read as `n` is decided by shape (`isPi`) only for a lone `n` (not after a letter, at most
  one after) on a line with a relation — `isPi` fires on many upright prose `n`s, never widen it.
- Latest release timings on the Mac (188 cases): math on median 87 / p90 169 / max 276 ms; off 69 / 143 /
  238 ms; equations ≈ 2× faster with Recognize math off (88 vs 42 ms).
- Full log, remaining failures and next steps: `docs/mac-reference/PROGRESS-2026-09-28-ocr.md` (session 5 at
  the top). Source: `docs/mac-reference/src/ocr-structure-math/` (CaptureKit sources + tests).
- **The maths output format is shared with JVoice** (dictation): see the JVoice repo's
  `docs/mac-reference/math-notation-format.md` on its `windows-port` branch
  (`https://github.com/david53001/jvoice/blob/windows-port/docs/mac-reference/math-notation-format.md`).
- **Windows engine differences that shape the port** (see v3 §8.7): Windows.Media.Ocr returns lines and
  words with bounding boxes but **no per-character boxes, no confidence, no "fast/accurate" levels, no
  language-correction switch** and no custom-word list. The Mac pipeline's pixel passes (ink map, glyph
  alignment, display-math rebuild, grid lines) work from the image + word boxes, so they port; the passes
  that re-read a crop with Vision become re-reads with `OcrEngine` on the crop; anything using Vision's
  confidence must use a pixel/no-harm check instead.
- **Recommendation**: this branch is still WIP on the Mac (not merged, not released). Port v3 Part 8's
  clipboard format + `TextReflow` layout first (big win for ordinary text), then the maths passes, and
  re-sync with the Mac branch before starting the maths passes. Build a Windows corpus harness
  (v3 §8.8) from your own screenshots — the Mac corpus images are private and not in the repo.

---

## 5. Where v3 needs a Windows-side note (read with the parts)
- **v3 Part 9 (native look)** + §4.9 here: implement as one surface recipe — windows = Mica/Acrylic backdrop
  (`DWMWA_SYSTEMBACKDROP_TYPE`) + window-colour layer at the Opacity alpha; floating HUDs = dark tinted
  surface (Acrylic where reliable, else a solid dark tint at the HUD alpha — check contrast); docked panels
  on the editor = blur + tint per the table. Follow the system light/dark (registry
  `HKCU\…\Themes\Personalize\AppsUseLightTheme`, watch `SystemEvents.UserPreferenceChanged`), accent colour
  from `UISettings`. The editor and video editor stay dark in light mode.
- **v3 Part 7 (tours)**: the JVoice Windows port will build the same tour kit (its doc:
  `https://github.com/david53001/jvoice/blob/windows-port/docs/MAC-TO-WINDOWS-PARITY.md` §10). Build it once
  as a clean C# library and reuse it in both apps if practical.
- **v3 "Window placement"**: combine with §4.11 (current virtual desktop) and the monitor under the cursor.

## 6. When you finish an item
1. `dotnet build` + `dotnet test windows/tests/BetterScreenshot.Tests` green.
2. `pwsh windows/scripts/publish-app.ps1`, relaunch, try it for real (and at the stretched resolution for
   anything visual).
3. Update `windows/docs/PROGRESS.md` and flip the item's status in §1 of this file to DONE with the commit.
4. Commit on `windows-port`; push when David says so.
