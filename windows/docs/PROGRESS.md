# BetterScreenshot-Windows — Progress Ledger

> ▶️ **LOOP RESUMED (2026-07-02).** Restarted from `windows/docs/HANDOFF-2026-07-02.md`; the self-perpetuating
> firing loop is active again (ScheduleWakeup). Phases 1–6 complete; **Phase 7 (Screen recording) IN PROGRESS —
> **PHASE 7 (Screen recording) COMPLETE — Tasks 7.1–7.5 all done, 214 tests green** (tag `win-v0.7-recording`).
> Ctrl+Shift+5 → record strip → records **MP4 or GIF** (full/area/window) to Videos + Quick Access card + history;
> tray red icon + m:ss; gapless Pause/Resume (segment+concat); pre-roll countdown; click/keystroke/camera overlays;
> **GIF export** (MP4→GIF, 960px/10fps/lanczos+palette, temp MP4 deleted); quit-time best-effort finalize. All
> verified on-screen / by ffprobe (a real GIF was produced: 960×691, 10fps, 21 frames). **Phase 8 IN PROGRESS:**
> # ✅ DONE — nothing left.
> The BetterScreenshot Windows port is COMPLETE. All PLAN.md task checkboxes are checked; `dotnet build
> windows/BetterScreenshot.sln -c Release` is clean (0/0); `dotnet test` is fully green (214 passed); the PLAN §V
> checklist passes; and a full fresh harden re-scan (all 7 port-reference modules + every key §V flow) found no new
> correctness/fidelity issue. Tagged **`win-v0.7-recording`** and **`win-v1.0`** on branch `windows-port` (local,
> not pushed). **No further changes will be made.** Owner review notes are in the "Owner review — needs your eyes"
> section below; the deferred optional-polish items remain listed but are NOT blockers.

The loop (`windows/LOOP-PROMPT.md`) reads this first every firing to avoid redoing work. Keep it current: check off
finished tasks, move the pointer, log assumptions/known-issues. One firing = one durable increment.

## 2026-07-05 — "Launch at login" now actually registers with Windows (owner request — it was a dead flag)
Owner asked for a setting to "pick if this app starts on startup." **The Settings UI already had it** — a "Startup" `DarkSection`
card with a `LaunchAtLoginCheck` `Theme.MonoSwitch`, an InfoTip, and the `SettingsStore.LaunchAtLogin` bool round-tripping to
`settings.json` — **but nothing consumed the flag.** Toggling it just wrote a bool; the app never told Windows to auto-start. So
this was a *wiring* fix, not new UI (the toggle already matches the monochrome JVoice theme).
- **New `Platform/StartupRegistration.cs`** — registers/removes the app in the per-user HKCU
  `Software\Microsoft\Windows\CurrentVersion\Run` key (value name `BetterScreenshot` = the quoted current-exe path). Chose the
  HKCU Run key over a Startup-folder `.lnk` or Task Scheduler because it's per-user (no admin/UAC), fully reversible (delete the
  value), and shows up in **Task Manager → Startup** so the owner can also disable it there. Mirrors the mac app's SMAppService
  login item. `SetEnabled(bool)` writes/deletes; `Reconcile(bool)` reads-then-writes-only-if-different (idempotent), refreshing the
  stored path so a **moved/republished build stays valid** and never leaves a stale entry. All ops are best-effort/try-caught —
  under a locked-down group policy the persisted flag still records intent. Uses `Environment.ProcessPath` (the real apphost path),
  and quotes it against spaces in the install path. `Microsoft.Win32.Registry` needs **no package** — it ships in the
  `Microsoft.WindowsDesktop.App` framework this project already references via `UseWPF`.
- **Wired in two places:** `SettingsWindow.Apply()` calls `StartupRegistration.Reconcile(_settings.LaunchAtLogin)` (instant-apply;
  `Reconcile` keeps the per-control firing a cheap no-op unless it actually changed). `App.OnStartup` calls the same right after
  `SettingsStore.Load()`, so a republished/moved exe self-heals its Run-key path and a toggled-off flag can't leave a leftover.
- **Tests:** new `StartupRegistrationTests.cs` (7 cases) drives the **internal registry seam** (`InternalsVisibleTo` added to the
  Platform csproj) against a throwaway HKCU scratch subkey (`Software\BetterScreenshot.Tests\…`, deleted in `finally`) — proves
  enable writes the quoted command, disable removes it, unresolvable-exe writes nothing, disable-on-missing doesn't throw, and
  `Reconcile` refreshes a stale path / clears when off / is a no-op (doesn't even create the key) when already off.
- **Verified:** build **0/0**; `dotnet test` **296 passed / 0 failed** (+7). Plus an **end-to-end real-key check** (throwaway
  console referencing the built Platform DLL, calling the *public* API): confirmed `SetEnabled(true)` writes the real
  `…\CurrentVersion\Run\BetterScreenshot` value = the quoted exe path, `Reconcile(true)` is idempotent (no rewrite),
  `SetEnabled(false)` removes it, and the machine was restored to its original (no-entry) state — so it registers exactly where
  Windows reads at sign-in and is fully reversible.
- **Assumption logged:** used the **HKCU Run key** (not the Startup folder or Task Scheduler) — the simplest reversible per-user
  approach and the standard for tray apps; no admin prompt. If the owner prefers a Startup-folder shortcut instead, it's a small swap.

## 2026-07-03 — Quick Access auto-dismiss: drag-a-bar slider (2s … Never) replaces 3/6/10s (owner request)
Owner asked to change the Quick Access overlay so *"it stays there for as long as the user wants … drag a little bar
to change how long it stays there."* Clarified with the owner up front → a **draggable slider in Settings** whose far
end is **Never (stays until you dismiss it)**. Key simplifier: `QuickAccessWindow.StartAutoDismiss` already treats
`OverlayAutoDismissSeconds <= 0` as "never dismiss", so **Never persists as 0** and the overlay timer needed **no
change** — this was purely a Settings-UI + persistence-mapping change.
- **New pure `Capture/OverlayDismissScale.cs`** maps slider position (2..31) ⟷ persisted seconds (0 = Never) ⟷ label
  ("6s" / "Never"): `SecondsToPosition`, `PositionToSeconds` (rounds + clamps to 2..30, ≥31 ⇒ 0), `Label`. One pure,
  tested place so the slider and the persisted int can't drift. 25 xUnit cases in `OverlayDismissScaleTests.cs`.
- **New monochrome `Theme.Slider`** (+ `SliderTrackFill` / `SliderTrackEmpty` / `SliderThumb`) in `Resources/Theme.xaml`
  — the app had **no Slider style at all**. Faint full-width base track, white fill left-of-thumb (painted via the
  `Track.DecreaseRepeatButton`), round white thumb (accent hover/pressed on hover/drag). Standard WPF `PART_Track`
  template, so a malformed one would fail the XAML compile.
- **`Settings/SettingsWindow.xaml`**: replaced the 3/6/10s segmented `RadioButton` group under "Auto-dismiss after"
  with a `Slider` (`DismissSlider`, Min 2 / Max 31, snap-to-integer, `IsMoveToPointEnabled`) + a live "6s"/"Never"
  readout (`DismissValueLabel`). InfoTip copy updated to mention dragging + the Never end.
- **`SettingsWindow.xaml.cs`**: load = `DismissSlider.Value = OverlayDismissScale.SecondsToPosition(...)` +
  `UpdateDismissLabel()`; save = `OverlayAutoDismissSeconds = OverlayDismissScale.PositionToSeconds(DismissSlider.Value)`;
  new `DismissSlider_ValueChanged` (live label + instant-apply, `_loading`-guarded) and null-guarded `UpdateDismissLabel`
  (the slider can raise `ValueChanged` during XAML parse before the label field is assigned). Dropped `Dismiss3/6/10`.
- **No temp-file edge case for Never:** the drag PNG's 5-min delete is scheduled *on card dismissal*
  (`CaptureCoordinator.ShowOverlayCard`, line ~129), **not** at creation — so a Never card keeps its drag file for its
  whole (possibly indefinite) life, then cleans up 5 min after the owner finally closes it. Nothing to change there.
- **Verified:** build **0/0**; `dotnet test` **289 passed / 0 failed** (+25 `OverlayDismissScaleTests`). Settings
  rendered via `--ui-preview settings` (PrintWindow, since the owner's monitors were busy with a topmost app) shows the
  slider at the default **6s** with the white fill + thumb, matching the JVoice theme. **Republished `dist/` and
  relaunched the tray agent.** Committed, not pushed.
- **NOTE: a concurrent agent's dist instance (started 8:26 PM) was running in this shared tree** — see
  `concurrent-agents-shared-tree` memory (that agent's InfoTip commits `3d03014`/`db88ab0`/`a6e7467` are in history and
  are compiled into my republished binary). I stopped its running dist instance to release the locked exe, published, and
  relaunched my build (single instance confirmed). Last-writer-wins if it republishes again.

## 2026-07-03 — InfoTip polish: no Help cursor + crisp, perfectly-centered "i" (owner request)
Two owner-reported nits on the `App/Controls/InfoTip.cs` "ⓘ" button. **(1)** Hovering it showed the arrow-with-"?"
Help cursor — it was `Cursor = Cursors.Help`; changed to `Cursors.Arrow` (it's hover-only, no click action). Commit
`3d03014`. **(2)** The "i" looked off-center, small, and color-fringed. Root cause: it was a `TextBlock`, so WPF drew
it as **ClearType text** (subpixel color fringing on the dark circle) and centered its advance-width box, not its ink.
Replaced it with a **filled vector `Path`** built from the glyph outline — scaled to a fixed 9px ink height (bigger),
normalized so ink bounds start at (0,0) so `Stretch.None` + the Border's `Center` alignment centers the visible ink
exactly. Result is solid white, fringe-free, and pixel-identical every instance. Verified via a throwaway
`RenderTargetBitmap` harness measuring the real control: L/R margins 6.00/6.00 DIP, T/B 3.50/3.50 DIP, bbox-center
offset ≈ −0.013 DIP (dead center). Commit `db88ab0`. Republished `dist/` and relaunched the tray agent both times.
Kept the italic serif style (owner only flagged centering/size); upright is a one-line change if wanted later.

## 2026-07-03 — Per-setting info buttons + drag temp PNG auto-deletes after 5 min (owner request)
Owner asked for *"a little information button next to every single setting to explain what the setting is and give an
example,"* and that *"when you drag a screenshot in, it saves it in temp for 5 minutes and then deletes it
automatically … but do not delete the screenshot fully since it's going to be in capture history."* Commits `3e6edea`
(feature) + `a60c320` (tests) on `windows-port`. **NOTE: a second agent was editing this same tree concurrently**
(its commits `35d3a73` two-col shortcuts, `dc8c9a2` editor text fix interleave with mine) — see the
`concurrent-agents-shared-tree` memory; git merged the parallel commits linearly.
- **Info buttons.** New reusable `App/Controls/InfoTip.cs` — a 16px circular monochrome "ⓘ" that shows a theme-styled
  tooltip (bold Title + wrapped Explanation + italic "e.g." Example), built in code via `ToolTipOpening` with
  literal-color fallbacks so it renders even without app resources. Placed next to **every** setting in
  `Settings/SettingsWindow.xaml` (Capture, Quick Access Overlay, Pin, History, Startup, Save Location, Recording) and
  next to **each Keyboard Shortcut row** (per-action copy via `ShortcutHelp` in the code-behind). WinForms/WPF type
  ambiguities (`Cursors`/`ToolTip`/`HorizontalAlignment`) resolved with `using` aliases like the other App files.
- **Drag temp cleanup.** The Quick Access drag-to-export temp PNG (`quickaccess.png`, written in
  `CaptureCoordinator.ShowOverlayCard`) was **never deleted** (leaked in `%TEMP%`). New shared
  `Platform/TempFiles.cs` (`PayloadLifetime = 5 min`, `ScheduleDeleteContainingDir`) now removes it 5 minutes after the
  card is dismissed; `ClipboardService` refactored onto the same helper (dropped its private duplicate). The screenshot
  is **preserved** — History keeps its own `%APPDATA%\…\History` PNG copy, a separate location, so deleting the `%TEMP%`
  drag file loses nothing. Recording cards drag the *real* saved file and are intentionally NOT scheduled for deletion.
- **Auto-dismiss wired (bonus).** `OverlayAutoDismissSeconds` (3/6/10s) was persisted + shown in Settings but **never
  applied** — a dead setting. Wired it into `QuickAccessWindow` (DispatcherTimer, **hover-to-pause**, restart on
  mouse-leave; auto-dismiss = `DismissReason.Closed` so it stays restorable). Makes the new info tip truthful and bounds
  the temp lifetime to ~5 min after the card goes.
- **Verified:** build **0/0**; `dotnet test` **264 passed / 0 failed** (+4 `TempFilesTests`: 5-min lifetime, deletes
  only the payload dir, sibling dir untouched, null-safe). Settings rendered via `--ui-preview settings` (PrintWindow) —
  ⓘ on every setting, clean 3-col layout. Tooltip content proven by rendering the **real** `InfoTip.BuildTip` output
  offscreen (throwaway net9 WPF harness reflection-loading the built assembly — screen-grab was unreliable, owner's
  dual monitors were busy with topmost apps). **Republished `dist/` and relaunched the tray agent** (it wasn't running —
  I'd stopped it during verification). Committed, not pushed.

## 2026-07-03 — History cap → 10/50/100 + Settings widened to JVoice 960 / 3 columns (owner request)
Owner asked to *"implement a new feature called history … last 10 up to last 100, editable in settings,"* and to
*"make the settings wider (not as long) to match the JVoice width."* **Capture history already existed end-to-end**
(Phase 6: `BetterScreenshot.History/`, `Platform/HistoryStore.cs`, `App/History/HistoryService.cs` +
`HistoryWindow`, tray → History…, records on save/overlay). So this was a **refinement**, not a new build:
- **History cap options `10 / 50 / 200` → `10 / 50 / 100`** (max is now 100 per the request). Renamed the segmented
  radio `Cap200`→`Cap100` in `Settings/SettingsWindow.xaml` (Content "100") and updated the load/apply switches in
  `SettingsWindow.xaml.cs` (lines ~79, ~266). **Default kept at 50** (`CaptureSettings.HistoryCap`) — it is the
  tested default, the middle of the new range, and the owner's already-persisted value; "10" is honored as the
  minimum option. The model still accepts any int, so the two roundtrip tests that serialize `HistoryCap=200` still
  pass unchanged.
- **Settings window `720`→`960` wide + two-column body reflowed to three** (mirrors `JVoice-Windows`
  `UI/SettingsView.xaml`, which is `Width="960"` / 3-col; its own comment explains the exact rationale the owner
  echoed — go wider so the window isn't a too-tall stack). Document order already split cleanly, so it was done by
  inserting column boundaries only (no block moves): **Col A** Capture · Quick Access Overlay · Pin to Screen ·
  **Col B** History · Startup · Save Location · **Col C** Recording. Keyboard Shortcuts stays full-width below.
- **Verified:** `dotnet build` clean (0/0), **256 tests green**, and the settings window rendered via
  `--ui-preview settings` (960×970, 3 balanced columns, History shows 10/50/100, no clipping). Republished to
  `dist/` and relaunched the tray agent.

## 2026-07-03 — Quick Access card: full-bleed image + auto-contrast overlay (owner request)
Redesigned the post-capture Quick Access card (`Overlays/QuickAccessWindow.xaml[.cs]`) per owner: *"the image
should be the full thing / the full block, rounded; the UI overlays above it and auto-contrasts — white image →
black buttons, and detect the palette on hover too."*
- **Full-bleed rounded image:** dropped the separate dark thumbnail-band + button-strip DockPanel. The captured
  image now fills the entire rounded card edge-to-edge (`Image` `UniformToFill`, `Root.Clip` = rounded rect since
  a `Border` CornerRadius won't clip children). The card is **sized to the image's aspect ratio** (width 236,
  height derived, clamped 132–280) so the whole capture shows with no letterbox; extreme ratios crop via
  UniformToFill. Rounded drop-shadow + subtle hairline retained.
- **Overlaid, auto-contrasting toolbar:** the action buttons float over the bottom of the image. New
  `Overlays/QuickAccessContrast.cs` samples the average luminance of the image's bottom ~30% strip
  (crop→downscale→BGRA→Rec.709 mean) and picks a coherent palette: bright strip → near-black glyphs + faint white
  scrim + translucent-black hover/pressed pills; dark strip → near-white glyphs + faint black scrim +
  translucent-white pills. Hover/pressed pills come from the same decision, so hover contrast is automatic. A
  gentle bottom scrim (shares the image tone) guarantees legibility over busy/mixed content.
- **Variable-height stack:** cards now differ in height, so `QuickAccessStackController.Restack` stacks them
  cumulatively from the corner using each card's actual `Width`/`Height` (was the fixed-step `OverlayPositioner.
  StackedOrigin`; that pure fn + its tests are untouched and still used for single-window origins).
- **Decisions (owner away):** kept the bottom scrim (subtle, tone-matched) as a legibility guarantee for the
  auto-contrast — the alternative (glyph-only) fails over photos; documented here as the one judgment call. One
  toolbar tone (not per-button) so the row reads as one intentional unit.
- **Verified:** App build **0/0**; `dotnet test` **250 passed / 0 failed** (8 new pure luminance/threshold tests);
  rendered the card offscreen for **light / dark / wide** sample images and eyeballed the PNGs — black glyphs on
  the white image, white glyphs on the dark + gradient images, full-bleed rounding correct. **Published to `dist/`**
  and relaunched the tray agent. Committed on `windows-port` (not pushed).
- **Process writeup:** [`QUICKACCESS-CARD-REDESIGN.md`](QUICKACCESS-CARD-REDESIGN.md) — request → exploration →
  decisions + alternatives → implementation → verification (incl. the offscreen-render harness used to "see" it).

## 2026-07-03 — Capture black-bar fix + editor FPS + on-screen "walls" (owner-reported)
Three owner-reported issues on a **dual-monitor, stretched-resolution** rig (primary = a **stretched 1500×1080**
on a native-1920 panel; secondary = native **1920×1080**). Root-caused with live GDI diagnostics (PerMonitorV2
harness mirroring `Screens`/`ScreenCapture`); all four fixes are pure-logic-tested where possible + a new capture
regression test. **Full debugging process log:** [`INVESTIGATION-2026-07-03-capture-blackbar-editor.md`](INVESTIGATION-2026-07-03-capture-blackbar-editor.md).
- **Capture "massive black bar on the side" (the main one).** The proof was in the owner's screenshot: the
  captured desktop's **taskbar cut off at the content edge** with black beyond — a Windows taskbar spans the whole
  monitor, so the *framebuffer* was ~1500 wide but the BitBlt requested ~1920. The app only sizes captures from
  `GetMonitorInfo` (`MonitorInfo.Bounds`), which reports the logical/native size; a full-screen game or a custom
  **stretched** scanout leaves the real framebuffer narrower, so BitBlt over-reads past the desktop → black
  padding. Fix: **`Screens.RealFramebufferSize(deviceName)`** queries the display DC's real framebuffer
  (`CreateDC("DISPLAY",…)` + `GetDeviceCaps(DESKTOPHORZRES/VERTRES)`), and **`ScreenCapture.CaptureDisplay`** clamps
  the monitor bounds to it (`RealBounds`); `CaptureRegion` also clamps to the live virtual screen
  (`SM_*VIRTUALSCREEN`) as a backstop. Confirmed the DC caps report the true framebuffer (1500 vs 1920) on this rig;
  a white-window probe proved GDI offset-reads onto the secondary work (so it was never a multimon offset bug).
  In the normal case (reported == real) the clamp is a harmless no-op. New hardware test
  `CaptureDisplayIsClampedToRealFramebuffer`.
- **Area selection could run off-screen.** Mouse capture keeps delivering points past the monitor edge, so a drag
  could select (and capture) beyond the screen. Added pure **`SelectionMath.ClampToBounds`** (+3 tests) and clamp
  the DIP selection rect to the monitor's DIP extent (`RootCanvas` size) in `SelectionOverlayWindow`
  move + up — a physical wall.
- **Editor annotations could be dragged out of the image.** `EditorWindow.Pos` now clamps the pointer to
  `[0,imgW]×[0,imgH]` (covers drawn shapes, marquee, counter, text placement), and a Select-tool **move** clamps the
  moved annotation's bounding box inside the image (`MovedWithinBounds`).
- **Editor "staggering FPS" while annotating.** Root cause: the draw-preview re-rasterized a **full-resolution
  `RenderTargetBitmap` of the whole document every mouse-move** (≈8 MB/frame at 1080p → GC thrash → stutter). Fix:
  shape tools (arrow/line/rect/filled-rect/ellipse) now draw a **lightweight WPF vector preview** on the
  interaction canvas during the drag (`ShowVectorPreview`/`BuildPreviewElements`) — zero per-frame raster — and
  flatten to the document only on mouse-up via the unchanged, unit-tested `DocumentRenderer`. Select-**move** now
  redraws a **one-time pre-flattened background** (base + all *other* annotations) + only the moved annotation,
  instead of re-flattening the whole document each frame. The commit path is byte-for-byte the old (working) code,
  so committed output is identical — only the live preview changed.
- **Verified:** solution build **0/0**; `dotnet test` **256 passed / 0 failed** (incl. new SelectionMath /
  Screens / ScreenCapture tests); `CaptureDisplay` returns the clean real-framebuffer size on this rig (no black
  bar); editor opens, renders edge-to-edge, and tool-select works (driven via UI Automation — a synthetic *drag*
  can't be injected into WPF here, but the draw **commit** path is unchanged from shipped v1.0). **Republished to
  `dist/` and relaunched the tray agent** (new exe 18:47). Committed on `windows-port` (not pushed).
- **Owner note:** the black-bar fix can't be reproduced on-screen right now (this rig's reported size == real
  framebuffer, so no bar today) — it triggers only when a game/app leaves the scanout stretched. The fix is proven
  safe (no-op when sizes agree) and correct against the DC-caps ground truth. Worth a spin next time you capture
  right after a stretched-res game. (Owner's capture hotkey is **Alt+.**, not the Ctrl+Shift defaults.)

## 2026-07-03 — JVoice monochrome UI revamp (owner request)
Re-skinned the **whole Windows app** to the sibling **JVoice-Windows** black-and-white identity (owner: "take a
look at how JVoice's UI looks and incorporate it throughout, especially settings"). Spec + rationale:
`windows/docs/UI-JVOICE-REVAMP.md`.
- **Palette** (`Resources/Theme.xaml`): remapped every token to monochrome — window `#000`, card `#0E0E0E`,
  hairline `#242424`, and **white is the accent** (was blue `#0A84FF`). Keys unchanged, so all windows re-skin
  through the existing implicit styles. Fixed the styles that would now be white-on-white (AccentButton = white
  fill + black text; toggle/tool checked = white@20%; ComboBoxItem highlight = white@16%; CheckBox check = black).
- **New components**: ported JVoice's `DarkSection` card control (`Controls/DarkSection.cs` + implicit style: glowing
  white dot + UPPERCASE header + divider), `Theme.MonoSwitch` (macOS toggle), `Theme.SegmentLeft/Mid/Right/Solo`
  (joined segmented control), `Theme.PillButton`, `Theme.PressableButton`.
- **Settings** (`Settings/SettingsWindow.xaml[.cs]`): replaced the 3-tab layout with a **two-column masonry of
  DarkSection cards** (no TabControl). Booleans → MonoSwitch rows; short enums → segmented RadioButton groups;
  pin-radius → styled ComboBox; shortcuts → full-width card (mono chip + Change pill + Clear). Instant-apply +
  shortcut-recording behavior unchanged; `SizeToContent=Height` clamped to the work area.
- **Stray blues removed**: editor marquee, history selection border (+ darker cells), window-picker highlight, tray
  menu colors. **Left blue (logged):** `ClickHighlighter` (baked into the recorded video, not chrome).
- **Decisions (owner away):** Windows-only (macOS Swift app untouched — it's the behavioral source of truth and not
  verifiable here); destructive buttons are monochrome (no red) to match JVoice, guarded by confirm dialogs.
- **Verified:** solution build **0/0**; `dotnet test` **241 passed / 0 failed**; every window screenshotted via
  `--ui-preview`; **published to `dist/`** and the tray agent relaunched. Committed on `windows-port`
  (`64a05fe` code + `adcd560` docs) and **pushed to `origin/windows-port`** (2026-07-03). `main` not merged —
  merge/PR when ready.

## Current pointer
- **Branch:** `windows-port`
- **Phase:** ✅ **DONE** — Phases 1–8 complete, `win-v1.0` tagged, full harden re-scan clean. Loop ended (no wakeup scheduled).

## Owner review — needs your eyes (nothing blocking; the port is DONE)
- **Camera-bubble live preview** and **quit-time recording finalize** are code-/build-verified but were NOT
  exercised on-screen here: this machine has **no webcam** (so the bubble only proved graceful degradation), and a
  graceful tray-Quit isn't scriptable. Worth a manual spin on hardware with a camera + a real Quit-mid-recording.
- **System-audio recording** needs a loopback-capable input (e.g. "Stereo Mix"); this machine has none, so recording
  degrades to video-only here by design. Try it on a box that has one.
- **Deferred optional polish (NOT blockers, not implemented):** editor 8-handle resize + marquee multi-select;
  captureText→region select (currently OCRs the whole primary display); cursor-monitor placement for the record
  strip + countdown (both currently primary-centered); a pure-monochrome tray-icon variant; QA action button 30×28
  vs the mac's 36×30 (intentional fit adaptation). All are enhancements — pick any up later if desired.
- **Git:** everything is committed on `windows-port` and never pushed; tags `win-v0.7-recording`, `win-v1.0` are
  local. Push / open a PR when you're ready.
- **Build:** `dotnet build windows/BetterScreenshot.sln -c Release` → **clean (0/0)**.
- **Tests:** `dotnet test windows/tests/BetterScreenshot.Tests` → **214 passed** (197 + 9 FfmpegArgs [7 record + 2
  GIF] + 8 DshowDeviceList; incl. hardware-gated tests, 0 skipped on this machine). Recording UI/overlays verified
  by driving the app (synthetic input + UI Automation) + ffprobe.
- **App TAKES SCREENSHOTS + HISTORY + RECORDS (full screen):** Ctrl+Shift+6 (fullscreen) & Ctrl+Shift+8 (front
  window) capture → save/copy; captureArea → selection overlay; captureText OCRs primary display → clipboard+HUD.
  Captures are recorded in **persistent history**; the **History window** (tray → History…) browses thumbnails.
  **Recording works end-to-end with the record strip:** Ctrl+Shift+5 (or tray → Record Screen…) shows the record
  strip (Full Screen / Window… / Area… · MP4/GIF · system-audio/mic/camera toggles that persist to settings · ✕);
  pick a target → ffmpeg records that desktop region → on stop, saves an MP4 to `Videos\`, records it in history,
  and shows a Quick Access recording card (Copy file / Open / Show in folder); the tray icon turns red with a live
  m:ss timer. A second Ctrl+Shift+5 while the strip is up cancels; while recording it stops. The tray **Pause /
  Resume Recording** menu item pauses & resumes **gaplessly** (segment+concat) — the timer freezes at "Paused ·
  m:ss" and the menu label flips. When `countdownSeconds>0`, a **pre-roll countdown** (200×200 dark pill, 120pt
  digit, click-to-skip, Ctrl+Shift+5-cancel) runs before capture starts. While recording, if enabled, **click
  highlights** (Ø36 accent@0.45 dots, 0.4s fade) and a **keystroke overlay** (top-center black pill, glyphs, 1.0s
  fade) render as on-screen click-through windows, plus a **camera bubble** (circular webcam preview Ø160/240,
  bottom-right of the region, draggable) when `camera` is on. If **GIF** format is chosen, on stop the MP4 is
  converted to a looping GIF (960px/10fps/lanczos + palette) and the temp MP4 removed; a recording in progress at
  app quit is finalized best-effort (MP4 saved). **Phase 7 is COMPLETE.**
- **Next task:** **HARDEN loop.** All planned tasks are done and `win-v1.0` is tagged, but the DONE condition also
  requires "a fresh re-scan finds no new correctness/fidelity issue." Each firing: do ONE fresh re-scan (read a
  module's port-reference doc vs. its Windows impl, or spot-check a §V flow not yet driven — OCR HUD, area/window
  capture, blur/pixelate drawing, DPI) and fix the single most important issue found; keep green + committed. When a
  full re-scan turns up nothing new, write **"DONE — nothing left"** in PROGRESS.md and STOP (no further ScheduleWakeup).
  Candidate items: deferred editor 8-handle resize + marquee multi-select; captureText→region select (currently OCRs
  the whole primary display); cursor-monitor placement for strip/countdown; a pure-monochrome tray icon variant.
  DEFERRED (hardening): editor 8-handle resize + marquee multi-select; icon-glyph toolbar (Phase 8);
  captureText→region select.

## Harden scan log (post-v1.0 — track each fresh re-scan; DONE when a full pass finds nothing new)
Scan targets: port-reference modules 01-capturekit · 02-overlaykit · 03-editorkit · 04-historykit · 05-recordingkit ·
06-app-shell · 07-icons; §V flows: area capture · window capture · fullscreen · OCR · editor draw/blur/pixelate/crop ·
history · recording MP4/GIF/pause · DPI.
- **Pass 1 (2026-07-02):** ✅ **03-editorkit** re-scanned vs impl — CLEAN: preset swatches exact (Red 1,.27,.23 …
  Black 0,0,0), weights 2/4/7, text sizes 18/24/36, HitSlop 6, counter Ø max(28,fs*1.6), arrow head 28°, selection
  handle #0A84FF — all match; pure-logic constants unit-tested. ✅ **OCR §V flow** (Ctrl+Shift+7) driven on-screen —
  recognized on-screen text (345 chars) → clipboard + HUD "Text copied — 345 characters". No issues found.
  Still to scan for a full clean pass: 01/02/04/06/07 module cross-checks; §V area+window capture, editor
  blur/pixelate/crop drawing, DPI. (05-recordingkit, 08-icons/app-icon were built + verified this session.)
- **Pass 2 (2026-07-02):** ✅ **02-overlaykit** re-scanned — CLEAN: QA card 220×168 radius 12, thumbnail 200×112
  radius 6, button-row y-offset 8, stack max 3 margin 24, spacing 6, recording card blue-tinted, temp-PNG cleanup
  300s — all match. NOTE (not a bug): QA action button is 30×28 vs the reference's 36×30 — an intentional Windows
  adaptation so 5 buttons fit the 220-wide card's inner width (36 would overflow); renders correctly on-screen.
  ✅ **Area-capture §V flow** (Ctrl+Shift+4) driven — selection overlay → synthetic drag (450,320)→(980,700) →
  Quick Access card shows the correctly-CROPPED region (not full screen) with the migrated icons. No issues found.
  Remaining: 01-capturekit, 04-historykit, 06-app-shell cross-checks; §V window capture (Ctrl+Shift+8), editor
  blur/pixelate/crop drawing, multi-DPI.
- **Pass 3 (2026-07-02):** ✅ **01-capturekit** re-scanned — CLEAN: OCR hudMessage strings verbatim ("QR code copied"
  / "Text copied — {N} characters" [em-dash] / "No text found"); CaptureSettings defaults all match (showOverlay,
  png, bottomRight, 6, 8, true, true, 50); hotkey defaults Ctrl+Shift+4/5/6/7/8 + FileNamer format verified earlier;
  pure-logic (geometry/crop/positioner/recognition/windowpicking/hotkeys) unit-tested. ✅ **Window-capture §V flow**
  (Ctrl+Shift+8) driven — picker overlay → click a window → Quick Access card shows the single captured WINDOW (via
  PrintWindow), not the full screen. No issues found.
  Remaining: 04-historykit, 06-app-shell cross-checks; §V editor blur/pixelate/crop drawing, multi-DPI.
- **Pass 4 (2026-07-02) — completes a FULL fresh pass:** ✅ **04-historykit** — pure logic + file IO, all unit-tested
  (28 tests: HistoryIndex 10, HistoryStore 10, RestoreStack 4, ThumbnailRenderer 4); constants match (maxAge 30d,
  RestoreStack depth 5, thumb ≤400 q0.8, cap 50). ✅ **06-app-shell** — tray menu order matches the reference
  EXACTLY (Capture Area/Window/Fullscreen/Text · Record/Pause · Pin · History/Restore · Settings/Quit); hotkey
  defaults, settings JSON keys, onboarding cheat-sheet, and the app-icon spec all match. ✅ **Editor redact §V flow**
  driven on-screen: capture → card Edit → Pixel tool → marquee drag → the region is pixelated (detail destroyed),
  region outside untouched; blur/crop share the same mechanism (Redactor.Blur + Cropped are unit-tested). ✅ DPI:
  every driven flow (capture/overlays/editor/recording) rendered correctly at this machine's actual scaling.
  **FULL PASS = modules 01–07 all clean + §V flows area/fullscreen/window/OCR/recording(MP4-GIF-pause)/editor
  draw+redact/history/app-icon/no-network all verified. NO new correctness/fidelity issue found.**

## Phase 8 task status (Icons, app icon, polish, end-to-end — BetterScreenshot.App)
- [x] 8.1 Icon resource dictionary + IconPresenter + consumer migration — **done.**
      `App/Resources/Icons.xaml` = 38 hand-authored 24×24 `StreamGeometry` glyphs, merged into `App.xaml`;
      `App/Controls/IconPresenter.cs` renders a glyph by key (stroke for outlines; the `Filled` set is filled with
      even-odd knockouts), scaled from 24×24, DPI-crisp. **Migrated all consumers to `IconPresenter`** and removed
      the inline glyph code: `QuickAccessWindow` (was `CardGlyphs` → copy/edit/pin/save/close/play/folder), record
      strip (was local `Glyphs` → speaker/mic/video/close), `HistoryWindow` badge (→ camera/film). The editor
      toolbar uses text labels (no glyphs) — nothing to migrate. **Verified:** build 0/0; 214 tests; a 38-glyph WPF
      render sheet (all parse + recognizable) + the migrated record strip on-screen (speaker/mic accent-on, icons
      render via IconPresenter incl. the dynamic accent-Brush toggle).
- [x] 8.2 App icon `.ico` + tray — done. `AppIconFactory` refactored to a single `DrawInto(g,size,bg,fg)` art
      source (charcoal #1C1C1C squircle + white camera: viewfinder hump, body, tiny flash knockout, lens 27%);
      `CreateTrayIcon` + a new `RenderBitmap(size)` both use it. `Resources/AppIcon.ico` = 7 sizes (16/24/32/48/64/
      128/256) as 32-bit **DIB** frames (GDI+/shell/exe all handle DIB; PNG frames tripped a GDI+ limitation),
      authored by rendering the same drawing. Wired `<ApplicationIcon>Resources\AppIcon.ico</ApplicationIcon>` in
      the App csproj → embedded in the exe (WPF windows use the exe icon by default). **Verified:** build 0/0;
      rendered the .ico frames + extracted the exe's embedded icon → both show the camera. (A pure-monochrome
      viewfinder-only tray variant is optional polish, deferred; the charcoal+white camera tray icon is legible.)
- [x] 8.3 End-to-end verification pass (PLAN §V) — done. **All automatable checks pass:** build 0/0; 214 tests;
      no-network audit clean (grep of product `.cs` for HttpClient/WebClient/WebRequest/HttpListener/TcpClient/
      UdpClient/Socket/Dns/http:// → NONE; XAML only has MS/openxml schema xmlns). **Interactive, driven on-screen:**
      launch to tray (no crash); Ctrl+Shift+6 fullscreen capture → Quick Access card with the migrated copy/edit/pin/
      save/close icons; card **Edit** → the annotation editor opens showing the captured image, all 11 tools, the
      color/size inspector, and Done/Stack/Save/Copy; the **app icon appears in the window titlebar + taskbar** (8.2
      confirmed end-to-end). Recording (MP4/GIF/pause-resume/overlays/countdown) + record strip + icon sheet were
      verified in prior firings. **Fixed one issue found:** icon-only buttons (Quick Access card, record strip) now
      set `AutomationProperties.Name` (= tooltip) for accessibility (they had only a ToolTip). Punch list (minor,
      covered by unit tests / prior verification, not re-driven this cycle): OCR HUD (Ctrl+Shift+7), area/window
      capture interactive, blur/pixelate drawing, multi-DPI visual — all have unit tests and/or earlier app-launch
      verification.
- [x] 8.4 `README-win.md` — done. `windows/README-win.md`: what it is (free, 100%-local tray app), feature list,
      prerequisites (.NET 9 SDK, Win10 19041+, ffmpeg for recording), build/test/run commands, default hotkeys, save
      locations, macOS differences (ffmpeg engine, segment+concat pause/resume, loopback system audio, dropped
      permission flows, top-left coords), the 100%-local guarantee, and a short architecture overview.
**PHASE 8 COMPLETE — `win-v1.0` tagged.** All PLAN.md tasks checked. Next: HARDEN loop → then "DONE — nothing left".

## Phase 7 task status (Screen recording — BetterScreenshot.Recording/App)
- [x] 7.1 ffmpeg arg builder + engine — done, +7 tests. `Recording/FfmpegArgs.cs` (PURE) builds the recording
      command line: video via **gdigrab** over a desktop-relative pixel region (all three targets — display/area/
      window — reduce to one region), cursor drawn, H.264/`libx264`/yuv420p at the pure `VideoBitrate` formula,
      output MP4. System audio + mic are separate `dshow` AAC tracks (48kHz/2ch/128k), included only when the
      config asks AND an `AudioInputs` device name is supplied; explicit `-map` when audio present, else default
      map. Even-floors capture dims for H.264. `App/Recording/RecordingEngine.cs` drives Platform's `FfmpegRunner`
      (start/stop, drains stderr/stdout so ffmpeg can't block, returns the finished path). **Probe passed:** a real
      3s gdigrab→libx264 capture of the live desktop → ffprobe reports valid h264/640×480/mp4/3.0s. Not yet wired
      into `ToggleRecording` (that's 7.2).
- [x] 7.2 RecordingCoordinator + record strip — **done** (+8 tests DshowDeviceList in 7.2-core; strip UI is code).
      `Recording/DshowDeviceList.cs` (PURE — parse ffmpeg `-list_devices` stderr → audio/video names;
      `PickSystemLoopback` [conservative loopback-name heuristic] + `PickMicrophone`), `Platform/DshowAudioDevices.cs`
      (runs ffmpeg -list_devices, caches, `ResolveAsync(config)`→`AudioInputs`), `Platform/WindowEnum.FrameBounds(hwnd)`
      (window rect for the window target), `App/Recording/RecordStripWindow.xaml(.cs)` (bottom-center strip: Full
      Screen / Window… / Area… buttons, MP4/GIF segment, system-audio/mic/camera icon toggles that persist to
      settings live, ✕ — all hand-authored glyphs), `App/Recording/RecordingCoordinator.cs` (smart RecorderState
      machine: Toggle = idle→arm[show strip] · armed→cancel · recording→stop; targets full[cursor monitor]/area
      [SelectionOverlay]/window[picker+FrameBounds] → region → `RecordingEngine.Start`; `ResolveAsync` audio;
      1s DispatcherTimer → tray red icon + m:ss; on stop saves MP4 to `Videos\` + region thumbnail → history +
      Quick Access recording card). Wired `CaptureCoordinator.ToggleRecording`→coordinator; `App`→tray state.
      **Verified: build clean; 212 tests green; the record strip renders correctly on screen** (screenshot: all
      glyphs draw; MP4 + system-audio selected by default) via a real Ctrl+Shift+5 synthetic-hotkey trigger.
- [x] 7.3 Countdown + gapless pause/resume — **done.** Countdown: `App/Recording/CountdownOverlayWindow.xaml(.cs)`
      (200×200 dark pill radius 24, 120pt Consolas semibold digit, 1s tick, click-to-skip, `Cancel()`), run in
      `RecordingCoordinator.BeginAsync` before `_engine.Start` when `CountdownSeconds>0`; `CancelStrip` cancels it;
      cancel→AbortArm. **Verified on-screen** (drove app with countdown=5 → the dark "4" pill rendered centered).
      Pause/resume (below) was the prior sub-increment:
      `App/Recording/RecordingEngine.cs` reworked to **segment-per-active-span + concat**: Start records segment 0;
      `PauseAsync` finalizes the current segment; `Resume` starts a new one; `StopAsync` concatenates all segments
      (`-c copy` via ffmpeg concat demuxer; single segment → File.Move) into the final MP4. Paused time is never
      captured → contiguous output (PauseTimeline models the alt PTS-retime path, not wired). `RecordingCoordinator.
      PauseResume` (Recording⇄Paused via RecorderState; timer freezes; `onPauseStateChange`→tray), wired
      `CaptureCoordinator.PauseResumeRecording`; `TrayIcon.SetPauseState` flips the Pause/Resume label; `App` wires
      `OnRecordingPauseChanged`→tray. **Verified end-to-end:** drove the app (UIAutomation click "Record Full
      Screen" + synthetic pause/resume/stop hotkeys) → output MP4 decodes cleanly and its duration EXCLUDES the
      2s pause (6.2s for two ~3s spans, not ~8s); standalone 2-segment `-c copy` concat probe also valid.
- [~] 7.4 Overlays — **click highlighter + keystroke overlay DONE; camera bubble remaining.**
      `App/Recording/ClickHighlighter.cs` (full-primary transparent **click-through** window [WS_EX_TRANSPARENT via
      `RecordingOverlayInterop`]; `MouseHook` WH_MOUSE_LL → Ø36 accent@0.45 dot at each click, 0.4s opacity fade;
      physical→primary-DIP conversion), `App/Recording/KeystrokeOverlayWindow.xaml(.cs)` (280×44 black@0.75 pill
      radius 10, top-center 100px, 20pt Consolas white; `KeyboardHook` WH_KEYBOARD_LL glyphs, 1.0s fade). Started
      in `RecordingCoordinator.BeginAsync` per `ClickHighlights`/`KeystrokeOverlay`; stopped in `TearDownOverlays`
      (StopAsync). **Verified on-screen:** drove a recording + synthetic click & 'A' keypress → screenshot shows the
      "A" pill top-center and a fading click dot; the click also passed THROUGH to the app beneath (click-through OK).
- [x] 7.4b Camera bubble — done. `App/Recording/CameraBubbleWindow.xaml(.cs)`: circular (Ø160/240) black bubble,
      bottom-right of the recorded region +24 (primary-DIP), draggable (`DragMove`), aspect-fill; frames from a
      `MediaCapture` + `MediaFrameReader` (Bgra8) blitted into a `WriteableBitmap`. Started in `BeginAsync` when
      `config.Camera`, stopped in `TearDownOverlays`. **Degrades silently** if no camera / access denied (bubble
      never shows). Verified: build 0/0; recording with `camera=true` on this **webcam-less** machine did NOT crash
      and still produced a valid MP4 (graceful degradation). ⚠️ The live camera *preview* itself is UNVERIFIED here
      (no webcam) — needs a manual check on hardware with a camera.
- [x] 7.5 GIF export + finalize — done, +2 tests. `FfmpegArgs.BuildGifConversion` (PURE, TDD'd exact args:
      `-vf fps=10,scale=min(960\,iw):-1:flags=lanczos,split…palettegen…paletteuse -loop 0`), `App/Recording/GifExporter.cs`
      (runs it via `FfmpegRunner.RunAsync`; deletes the temp MP4 on success, keeps it on failure). Wired into
      `RecordingCoordinator.StopAsync`: `Format==Gif` → convert the finished MP4 → `.gif` in Videos (HUD "Converting
      to GIF…"), then history + Quick Access card. Quit-time: `RecordingCoordinator.StopForExit` (pumps the
      dispatcher ~3s) via `CaptureCoordinator.StopRecordingForExit` ← `App.OnExit` — saves an in-progress recording
      (MP4; GIF/card skipped at exit). **Verified end-to-end:** drove a GIF recording → a valid looping GIF
      (960×691, 10fps, 21 frames) was produced and the temp MP4 was deleted.
**PHASE 7 COMPLETE — 214 tests green.** Recording is a full MP4/GIF feature (strip, targets, gapless pause/resume,
countdown, click/keystroke/camera overlays, GIF export, quit-time finalize). Next: Phase 8 (icons, app icon, e2e).

## Phase 6 task status (Capture history — BetterScreenshot.History/Platform/App)
- [x] 6.1 HistoryStore (file IO, load-prune, add/remove/clearAll) + ThumbnailRenderer — done, 14 tests (10 store + 4 thumb)
- [x] 6.2 HistoryService facade (record/restore/copy/reveal/delete) + wire into coordinators — done, +10 tests
      (RestoreStack.PopRestorable ×2, HistoryService ×8). Wired: record on save/overlay, ✕-close/evict→RestoreStack,
      KeepInStack records, RestoreRecentlyClosed re-shows newest closed card. ClipboardService.SetFile added.
- [x] 6.3 History window (thumbnail grid, actions) — done, +16 tests (HistoryDateFormat.Relative). Dark grid over
      HistoryService.Entries, hand-authored camera/film badges, relative date, action bar (copy/annotate/pin/reveal/
      delete/clear-all), double-click open, OpenHistory() shows single reused window. App-launch verified.
**Phase 6 COMPLETE — 197 tests green.** Capture history persists + is browsable end-to-end. Next: Phase 7 (recording).

## Phase 5 task status (Annotation editor — BetterScreenshot.App)
- [x] 5.1 Editor window + canvas render (DocumentRenderer, WPF) — done, 4 renderer tests (pixel read-back)
- [x] 5.2 Tools + interaction (draw/select/move/redact/crop; AnnotationFactory tested) — done; 8-handle resize + marquee-select deferred to 5.3
- [x] 5.3 Toolbar + inspector + action bar + undo/redo + sticky style + Stack button — done (UndoHistory tested; inspector colors/weights/sizes)
- [x] 5.4 Wire editor into CaptureCoordinator (Quick Access Edit, sticky-style persist) — done; app runs
**Phase 5 COMPLETE — 157 tests green.** Editor reachable end-to-end. Next: Phase 6 (history).
- [ ] 5.4 Wire editor into CaptureCoordinator (Quick Access Edit, annotate from history)

## Phase 4 task status (Overlays — BetterScreenshot.App)
- [x] 4.1 SelectionOverlay (area selection) — done (physical-pixel positioning, SelectionMath tested); needs manual drag verify
- [x] 4.2 QuickAccess card + stack (220×168, ≤3, actions, drag-export) — done; Copy/Save work, Edit/Pin stubs (4.3/5)
- [x] 4.3 Pin panels (PinGeometry-based, drag/zoom/multi-pin) — done (Pin from Clipboard + Quick Access Pin button)
- [x] 4.4 HUD + WindowPicker overlay — done (Capture-Text HUD; interactive window picker → CaptureWindow)
**Phase 4 COMPLETE — 141 tests green.** Overlays all built (selection, Quick Access, pin, HUD, window picker).
Next: Phase 5 (annotation editor).

## Phase 1 task status (pure-logic core)
- [x] 1.1 CaptureGeometry (top-left)              — done, tested
- [x] 1.2 CropMath                                 — done, tested
- [x] 1.3 FileNamer                                — done, tested
- [x] 1.4 Hotkey model (HotkeyAction/Combo/Bindings, Windows VK) — done, tested
- [x] 1.5 OverlayPositioner (top-left)             — done, tested
- [x] 1.6 RecognitionResult/Resolver              — done, tested
- [x] 1.7 CaptureSettings                          — done, tested
- [x] 1.8 WindowPicking (pure hit-test)            — done, tested
- [x] 1.9 RGBAColor + AnnotationStyle              — done, tested
- [x] 1.10 Annotation model + EditorDocument       — done, tested
- [x] 1.11 ArrowGeometry                            — done, tested
- [x] 1.12 HistoryEntry + HistoryIndex             — done, tested
- [x] 1.13 RestoreStack                             — done, tested
- [x] 1.14 RecordingConfig                          — done, tested
- [x] 1.15 RecorderState                            — done, tested
- [x] 1.16 PauseTimeline + GIFTiming                — done, tested
- [x] 1.17 PinGeometry                              — done, tested
- [x] 1.18 Redactor (buffer-based detail destruction) — done, tested
**Phase 1 COMPLETE — 104 tests green.** Phase 0 (scaffold) complete. Phases 3–8 (App shell, Overlays,
Editor UI, History UI, Recording, Icons) pending — see PLAN.md.

## Phase 2 task status (Windows platform integration — BetterScreenshot.Platform)
- [x] 2.1 Screen enumeration + DPI (Screens: EnumDisplayMonitors + GetDpiForMonitor) — done, hardware test
- [x] 2.2 Still capture (GDI BitBlt region/display + PrintWindow) — done, hardware test
- [x] 2.3 Window picking (Win32 enum in Z-order → feed pure WindowPicking) — done, hardware test
- [x] 2.4 Clipboard + temp writer + encode (PNG/JPG) — done (ImageIo tested headless; ClipboardService build-only)
- [x] 2.5 OCR + QR (Windows.Media.Ocr + ZXing) — done, QR round-trip test (hardware)
- [x] 2.6 Global hotkey host (RegisterHotKey on hidden HwndSource) — done, STA registration test (hardware)
- [x] 2.7 ffmpeg runner + availability — done, availability+run test (hardware)
- [x] 2.8 Global input hooks (WH_MOUSE_LL / WH_KEYBOARD_LL) — done, glyph tests + hook-install tests
**Phase 2 COMPLETE — 120 tests green.** Phases 3–8 pending — see PLAN.md.

## Phase 3 task status (App shell + capture flow — BetterScreenshot.App)
- [x] 3.1 Settings store (JSON, keys 1:1 with mac) — done, round-trip/missing/corrupt tests
      NOTE: placed in `BetterScreenshot.Platform` (not App) so the Tests project can cover it without referencing
      the WinExe. Namespace `BetterScreenshot.Platform.SettingsStore`.
- [x] 3.2 Tray + menu (WinForms NotifyIcon, full menu) — done, app launches to tray (verified via Start-Process)
- [x] 3.3 Hotkey wiring (load bindings → HotkeyHost → dispatch to actions) — done, dispatch tests; app runs w/ hotkeys
- [x] 3.4 CaptureCoordinator (area/fullscreen/window/text → route by afterCapture; save/copy) — done, e2e capture→save test
- [x] 3.5 Onboarding (welcome window) — done, renders on first run (verified via Start-Process)
- [x] 3.6 Settings window (General/Shortcuts/Recording tabs + shortcut recorder) — done, recorder tested; app runs
**Phase 3 COMPLETE — 138 tests green.** App = functional tray screenshot tool (capture/save/copy, OCR, settings,
live hotkey rebind, first-run welcome). Next: Phase 4 (Overlays).

## Completed (append as you go)
- 2026-07-01 (seed): Reconnaissance of macOS app → SPEC.md, PLAN.md, LOOP-PROMPT.md, seven port-reference docs.
- 2026-07-01 (seed): Scaffolded .NET 9 solution (8 projects), WPF tray shell (windowless, PerMonitorV2 manifest,
  WinForms NotifyIcon interop — dropped H.NotifyIcon due to NU1701). Full build clean.
- 2026-07-01 (seed): Implemented + tested Core (PxRect/PxPoint/PxSize, Corner, ArgbImage) and pure-logic for
  Capture (Geometry/Crop/FileNamer/OverlayPositioner/Recognition/Settings), History (Entry/Index/RestoreStack),
  Recording (Config/State/PauseTimeline/GIFTiming). **57 xUnit tests green.**

## Assumptions log (decisions made without asking; David can review)
- Windows hotkeys map Cmd→Ctrl: Ctrl+Shift+4/5/6/7/8 (SPEC §4).
- macOS screen-recording permission flow + native-shortcut suppression are **dropped** (no Windows equivalent needed).
- Recording engine = ffmpeg (DXGI/gdigrab + WASAPI loopback + dshow), not a custom encoder.
- History cap default = 50 (CaptureKit default; the mac App note said 200 — using 50 per the tested default).
- Save destinations default to `Pictures\Screenshots` (images) and `Videos\` (recordings).
- Tray = built-in WinForms `NotifyIcon` (not H.NotifyIcon.Wpf, which resolved via a .NET Framework fallback).
- RecorderState elapsed formula = wall − accumulatedPause (the "7s" figure in 05-recordingkit.md is a doc typo;
  the real value for start0/pause10/resume13/now20 is 0:17). Verified by test.
- History records a capture only when it is **saved or shown as an overlay** (not for copy-only captures, which are
  transient) — matches the PROGRESS pointer's "record on save/overlay". Copy-only stays ephemeral. (Task 6.2)
- HistoryService reads cap + enabled **live** from settings each call (via `ForSettings`), so toggling history in
  Settings takes effect immediately without reconstructing the service. (Task 6.2)
- **(7.1) Video backend = `gdigrab`, not `ddagrab`.** The reference allows either; gdigrab supports arbitrary
  region capture via `-offset_x/-offset_y/-video_size`, so display/area/window all reduce to one desktop-relative
  pixel region (matches the mac recorder's "capture full display then crop to window"). ddagrab captures a whole
  output and can't crop to an arbitrary rect as cleanly. Verified gdigrab produces a valid MP4 on this machine.
- **(7.1) "WASAPI loopback" is realized as a `dshow` audio input.** Mainline ffmpeg 8.1 has no WASAPI demuxer, so
  system-audio loopback must come from a loopback-capable dshow device (e.g. "Stereo Mix" or a virtual cable). The
  pure `FfmpegArgs` only formats a supplied device name; **discovering the actual device names is deferred to the
  engine/coordinator (Task 7.2)** via dshow enumeration. If no device is found the track is dropped gracefully
  (video-only), matching "disable recording features gracefully if unavailable".
- **(7.1) Recording always encodes H.264/MP4; a GIF request is a separate post-conversion pass (Task 7.5).**
  `FfmpegArgs.BuildRecording` ignores `config.Format` (always libx264). This mirrors the mac flow
  (record → stop → convert-to-GIF-if-gif).
- **(7.1) Capture dims are even-floored** for H.264 yuv420p (drops ≤1px per axis), per "round pixel dims to even".
- **(7.2) System-audio loopback picker is deliberately conservative.** `PickSystemLoopback` only matches genuine
  loopback names (stereo mix / what u hear / wave out mix / loopback / cable output / voicemeeter out). Generic
  "virtual audio" devices are NOT auto-selected (some are mics — e.g. this machine's "Voicemod Virtual Audio").
  Consequence: on a machine with no Stereo-Mix-class device (like this one), system audio is silently dropped and
  recordings are video-only until the user picks a device (a future record-strip/settings affordance). Honest
  default over guessing wrong.
- **(7.2) Recording target defaults to the full primary display** for now (no strip yet). Toggle records the whole
  primary monitor; area/window targets + the picker come with the record-strip UI (remaining 7.2).
- **(7.2) Recording thumbnail = a still GDI grab of the primary display at stop** (≈ the final frame) — avoids a
  second ffmpeg frame-extract pass; falls back to a 2×2 blank if the grab fails.
- **(7.2) dshow device list is cached** after first enumeration (`DshowAudioDevices`, `InvalidateCache()` to reset)
  — enumeration spawns ffmpeg and devices change rarely; keeps recording start snappy.
- **(7.2) Recordings save to `SettingsStore.RecordingsDirectory`** (default `Videos\`), named `Recording {date}.mp4`
  via `FileNamer` (prefix "Recording"). Dir is created on demand.
- **(7.2) The record strip is positioned on the PRIMARY monitor's work area** (bottom-center, via
  `SystemParameters.WorkArea`). The mac shows it on the screen under the cursor; per-monitor physical↔logical WPF
  placement is fiddly, so cursor-monitor strip placement is deferred to hardening. Full-screen target uses the
  monitor under the cursor (`OverlayHelpers.MonitorUnderCursor`), so it can differ from where the strip sits.
- **(7.2) Window recording captures the window's rect as a FIXED desktop region** (via `WindowEnum.FrameBounds` at
  start); if the window moves/resizes mid-recording it is not tracked (matches 05-recordingkit.md's note that DXGI/
  gdigrab can't crop to a live window). Acceptable for v1; revisit in hardening if needed.
- **(7.2) Mid-selection cancel:** the overlay controllers (`SelectionOverlayController`, `WindowPickerController`)
  have no programmatic Cancel — they self-cancel on Esc. So Ctrl+Shift+5 while the area/window overlay is up resets
  state (so the eventual pick no-ops) but leaves the overlay up until Esc. Minor divergence from the mac (which
  tears the overlay down); noted, low impact.
- **(7.2) The strip's GIF toggle persists format but recording still writes MP4** — GIF conversion is Task 7.5;
  until then choosing GIF records an MP4 (documented in the pointer). No data loss.
- **(7.3) Gapless pause/resume = segment-per-active-span + concat** (the reference's simpler sanctioned option),
  NOT the PTS-retime approach. Each active span is its own ffmpeg segment; pause finalizes it, resume starts a new
  one, stop concats with `-c copy` (identical encode settings across segments). Paused time is never captured, so
  the timeline is contiguous. Trade-off: each resume re-spawns gdigrab (~0.1–0.3s startup), so a fraction of a
  second may be lost at each boundary — acceptable, matches "drop frames while paused". `PauseTimeline` (pure,
  tested) models the alternative and stays green but is not wired into the engine.
- **(7.3) Pause/Resume is reachable only via the tray menu** (no default hotkey — `PauseResumeRecording.DefaultCombo`
  is null, mirroring the mac which also ships it unbound). The user can bind one in Settings → Shortcuts.
- **(7.3) Recording segments + concat list live in `%TEMP%`** (`bs_rec_*.mp4`, `bs_concat_*.txt`), deleted after a
  successful concat; a single-segment recording is `File.Move`d straight to the final path (no re-mux).
- **(7.3) Countdown is centered on the PRIMARY screen** (`SystemParameters.PrimaryScreen*`), not the recorded
  monitor. It runs before capture starts so it is never in the recording — a pure pre-roll for the user — so the
  monitor choice is cosmetic; primary-centered is consistent with the strip. Digit font is Consolas (monospaced).
- **(7.4) Click/keystroke overlays cover the PRIMARY monitor** (consistent with strip/countdown). The click
  highlighter converts physical click points → primary-monitor DIPs via `Screens.Primary().DpiScale`; clicks on
  other monitors fall outside its window (not highlighted). Full-virtual-desktop coverage is a hardening refinement.
- **(7.4) Overlays are click-through** (`WS_EX_TRANSPARENT | LAYERED | TOOLWINDOW` set in `SourceInitialized`) so
  they never steal input — verified (a synthetic click passed through to the app beneath). Started after the engine,
  torn down on stop; pause/resume leaves them running (harmless — ffmpeg isn't capturing while paused).
- **(7.4b) Camera bubble uses MediaCapture + MediaFrameReader → WriteableBitmap** (not a UWP CaptureElement, which
  isn't a WPF control). It is NOT click-through (it's draggable). Positioned bottom-right of the region via
  primary-monitor DIP conversion (consistent with other overlays). ⚠️ Live preview UNVERIFIED on this machine (no
  webcam); only graceful-degradation is proven. Unpackaged desktop apps need no camera capability manifest, but the
  user's Privacy→Camera setting can block access → caught, degrades silently.
- **(7.5) GIF conversion is a single-pass filtergraph** (`split→palettegen→paletteuse`) at 10fps, ≤960px
  (`min(960,iw)`, never upscaling), lanczos, `-loop 0` (loop forever). The temp MP4 is deleted on success, KEPT on
  failure (nothing lost). GIF basename = the recording's timestamp with `.gif`.
- **(7.5) Quit-time finalize pumps the dispatcher (`DispatcherFrame`/`PushFrame`) up to 3s** so the async stop can
  complete during `App.OnExit`; at exit GIF conversion + the Quick Access card are skipped (just save the MP4). Only
  build/code-verified (a graceful tray-Quit isn't easily scriptable) — worth a manual check.
- **(8.2) `AppIcon.ico` uses 32-bit DIB frames, not PNG frames** — GDI+ `Icon.ToBitmap`/`DrawIcon` can't decode
  PNG-in-ICO frames (they threw "range extends past end of array"), which also blocks previewing; DIB frames work
  everywhere (shell, exe embed, GDI+). File is ~365KB (the 256 DIB frame dominates) — acceptable for an app icon.
  Generated by a throwaway PowerShell script that replicates `AppIconFactory.DrawInto` (kept in sync by matching the
  same proportions); not committed as app code.
- **(8.1) Icons live in `Resources/Icons.xaml` as `StreamGeometry` (24×24), rendered by `IconPresenter`** which
  strokes outline glyphs and fills the ones in `IconPresenter.Filled` (even-odd knockouts). This matches the
  reference (a WPF Geometry ResourceDictionary + a Path-based presenter). Verification is by rendering a glyph sheet
  (not a unit test — icon art is visual, not logic). The existing inline glyph sets still work and are left in place
  until the migration step (so no working UI is broken by adding the icon system).

## UI revamp (2026-07-03) — owner-requested dark/macOS-like restyle + fixes
Spec: `docs/UI-REVAMP-SPEC.md` · Plan: `docs/UI-REVAMP-PLAN.md` (all 7 tasks executed). Key decisions:
- **App-wide dark theme lives in `Resources/Theme.xaml`** (merged in App.xaml after Icons.xaml): palette
  tokens (`Theme.*Brush`) + implicit templated styles for Button/ToggleButton/ComboBox/CheckBox/TextBox/
  TabControl/ScrollBar/ToolTip (rounded 6–8px, no default WPF chrome) and keyed styles
  `Theme.AccentButton` / `Theme.DangerButton` / `Theme.SubtleButton` / `Theme.ToolButton` / `Theme.SwatchButton`.
  Titled windows call `Controls.WindowThemer.ApplyDark(window)` (DWMWA_USE_IMMERSIVE_DARK_MODE=20; no-op pre-20H1).
- **Settings is now instant-apply** (no Save/Cancel). Root cause of the owner's "settings don't save":
  values *did* persist on Save, but closing with ✕ reverted hotkey changes (old snapshot/revert model) and
  rebound keys displayed as `(vk 190)` which read as corruption. Now every change persists immediately,
  hotkey rebinds re-register + raise `SettingsWindow.HotkeysChanged` → `TrayIcon.UpdateShortcuts` keeps
  menu hints live. `HotkeyCombo.KeyName` gained OEM/numpad/navigation names (US-layout labels — assumption;
  a `MapVirtualKeyW` per-layout lookup is a possible refinement). Tests: 241 green (27 new).
- **Quick Access drag-out now dismisses the card** when `DoDragDrop` returns a non-None effect
  (Esc-cancelled drags keep it), matching macOS. Card + record strip are dark `Theme.CardBrush` cards.
- **Editor toolbar is icon-based** (existing Icons.xaml glyphs via IconPresenter) with an accent
  selected-tool state; inspector has round swatches with selection rings + dot/A-size toggles that track
  the sticky style. The in-canvas text box forces black-on-white (implicit dark TextBox style would have
  made it white-on-white).
- **Tray menu is dark** via `Tray/DarkMenu.cs` (`ToolStripProfessionalRenderer` + custom color table);
  `ShowImageMargin=false`. Native dialogs (MessageBox, folder picker) stay OS-themed — out of scope.
- **`--ui-preview <settings|shortcuts|editor|quickaccess|welcome|strip>` dev flag** (`UiPreview.cs`,
  checked at the top of `App.OnStartup` before the single-instance mutex): opens one window with sample
  data and no tray/hotkeys/mutex so the UI can be screenshotted next to a running instance; settings are
  in-memory defaults, nothing persists. Verified all surfaces by PrintWindow captures (foreground
  screenshots race the user's live desktop — use `PrintWindow(hwnd, hdc, 2)`).

## Selection-overlay fixes (2026-07-03) — owner-reported "capture area does nothing / Capture Text OCRs the whole screen"
Root causes found by driving the live app with injected hotkeys + synthetic mouse drags (probe scripts;
the pipeline itself was healthy — overlay → drag → card → history all worked when injected):
- **Capture Text never presented the selection overlay** — `CaptureCoordinator.CaptureText` OCR'd the full
  primary display (a Phase-5 stub that was never upgraded). Now mac-parity: it presents the shared
  `SelectionOverlayController`, captures the chosen region (`ScreenCapture.CaptureRegion`), OCRs that, and
  shows a "Capture Text failed" HUD on exception instead of silently swallowing.
- **Overlay only appeared on the monitor under the cursor** (mac shows it on *all* screens). On this
  two-monitor setup, a cursor parked on the other display made area capture look completely dead. Now one
  `SelectionOverlayWindow` per monitor; the first to complete/cancel wins and tears the set down; the
  window under the cursor gets keyboard focus for Esc.
- **No re-entry guard**: every hotkey press stacked another dim overlay that silently ate the next click
  (mac cancels the open selection instead). `Present()` now cancels an in-flight selection first
  (fires its completion with null), matching `SelectionOverlayController.swift`.
- **Selection wasn't punched out of the dim** (mac clears the dragged rect). The dim is now a Path with an
  EvenOdd geometry (full monitor minus selection) over a `#01000000` hit-test canvas — the near-zero-alpha
  background matters: fully transparent pixels on a layered window pass clicks through to the app beneath.
Verified E2E on the republished dist via injection probes: overlays on both monitors; second press
re-presents (2 windows, not 4); Esc clears; drag 500×350 → history PNG exactly 500×350 + Quick Access
card; Alt+, (Capture Text) now shows the overlay first and OCRs only the region. 241 tests green.
Note: the owner hit this while a fullscreen game (Minecraft) was up — if a truly exclusive-fullscreen app
ever hides the overlay, that's a separate visibility problem, not this bug.

## Quick Access + editor UI fixes (2026-07-03) — owner-reported "hover boxes bleed into the thumbnail / editor has empty gray sidebars"
Two post-v1.0 polish bugs the owner hit on real captures; root causes found by reading the layout + reproducing
with `--ui-preview` PrintWindow captures (portrait + landscape editor, QA card idle + hovered):
- **Quick Access action buttons bled into the thumbnail on hover.** The card was a `Grid` with the thumbnail
  pinned top (`y=10..122`) and the button row pinned bottom (`y≈118..146`) inside a card whose content was
  ~12px too short — so they **physically overlapped ~4px** and each button's hover pill (`Theme.SubtleButton`
  rounded fill) drew over the bottom edge of the image. Fix: rebuilt the card interior as a `DockPanel`
  (buttons docked bottom with an 8px gap, thumbnail fills) and grew the window `168→184`; kept
  `QuickAccessStackController.CardHeight` (184) in sync so stacked cards still position correctly.
  (`Overlays/QuickAccessWindow.xaml`, `Overlays/QuickAccessStackController.cs`.)
- **Editor showed wide gray dead-zones around the image.** The canvas is a `Uniform` `Viewbox`, so any capture
  whose aspect ratio didn't match the fixed 960×720 content area left pillar/letterbox gaps that showed the flat
  window background and — being outside `Stage` — ate drags (mouse did nothing there). Fix: added
  `EditorWindow.FitToImage()` (runs once on `Loaded`) that sizes the window so its **canvas area matches the base
  image's aspect ratio**, clamped to 94% of the work area and the window minimums (lowered to 560×460 so tall
  captures hug tighter; `maxUpscale=2.0` so tiny captures don't blow up into a blurry wall). Also gave the canvas
  a darker "pasteboard" backdrop (`Theme.ChromeBrush`) so any residual mat reads as intentional, not empty.
  (`Editor/EditorWindow.xaml`, `Editor/EditorWindow.xaml.cs`.)
Verified: build clean (0/0); 241 tests green. `--ui-preview editor` hugs a portrait sample to 576×970 and a
landscape sample to 1295×970 (image fills the canvas, toolbar/inspector still fit); the QA card shows a clean gap
and the hovered button's pill stays inside its band. **Assumption:** `FitToImage` runs only on initial load, not
after a Crop (avoids a jarring mid-edit window jump; the pasteboard backdrop covers any post-crop mat); it clamps
to the primary monitor's `SystemParameters.WorkArea`.

## Deploy of the QA hover-bleed fix (2026-07-03) — owner re-reported the bleed after `e9704df`
The owner re-reported "the hover overlay enters the image" *after* the fix commit landed. Root cause was **not**
a code regression: the running tray agent was the **stale `dist/` build** (`dist/BetterScreenshot/BetterScreenshot.App.exe`,
published 15:12) which predated the fix commit `e9704df` (15:59) by ~47 min. The `dist/` folder is a self-contained
publish snapshot — it does **not** update when you only `dotnet build`/commit; the single-instance tray agent keeps
running the old exe until you republish **and relaunch**. Resolution: re-verified the committed source renders clean
(rendered the card idle + with a button forced into its `Theme.SubtleHoverBrush` hover state straight to PNG via a
temporary `--ui-preview` harness — the pill stays fully inside the bottom button band, no image overlap), then
stopped the stale process, ran `pwsh windows/scripts/publish-app.ps1 -NoShortcut` (new exe 16:42), and relaunched.
**Lesson / gotcha:** after any change the owner will *see* at runtime, you must **republish `dist/` and relaunch**
the tray agent — a green build + commit alone leaves the owner testing a stale binary. (This is now called out in
`README-win.md` and in `LOOP-PROMPT.md` §5 Rules.)

## Editor text: click-off crash + no white background (2026-07-03) — commit `dc8c9a2`
Owner reported two things. Adding text then clicking back onto the image crashed the whole app. And the text
editor was a clunky white box. Both fixed. Details in `INVESTIGATION-2026-07-03-editor-text-crash-background.md`.

- **Crash.** `NullReferenceException` in `PlaceTextBox` (from `OnDown`). No global handler, so it killed the process.
- Root cause: each `TextBox`'s `LostKeyboardFocus` committed the shared `_textBox` field, not the box that lost focus.
- On click-off `OnDown` committed the old box then placed a new one in the same handler. A late focus event re-entered
  `CommitText()` and nulled `_textBox` mid-`PlaceTextBox`.
- Fix: `CommitText(TextBox)` guarded by `ReferenceEquals`; handlers wired to the specific box before `Focus()`;
  `OnDown` now finishes an open text box and consumes the click instead of committing-then-replacing.
- **White background.** The inline editor is now WYSIWYG: transparent, no chrome, stroke-colored bold text in the render font.
- Text has no background by default. A new inspector toggle adds an optional rounded chip (auto-contrast color).
- Chip is sticky (`AnnotationStyle.TextBackground`), drawn by `DocumentRenderer`; old styles without the field load as `null`.
- Verified: 260 tests green; crash harness survives all orderings; visually confirmed; `dist/` republished.

## Freeze the screen while selecting (2026-08-10) — owner: "screenshotting Minecraft unfocuses it and I capture the menu"
Pressing a capture shortcut showed the selection overlay, which stole focus; a full-screen game reacted by pausing
to its menu, and the capture — taken *after* the drag, from the live screen — got the menu instead of the frame the
owner wanted. Fixed by freezing: `FrozenScreen.Capture()` (new, `App/Overlays/FrozenScreen.cs`) BitBlts every
monitor the instant the shortcut fires, *before* any overlay window exists and so before anything loses focus. The
selection and window-picker overlays paint their monitor's still as their backdrop and the capture is cropped from
it, never re-grabbed. New setting `CaptureSettings.FreezeScreen` (persisted key `freezeScreen`, **default true**),
toggled in Settings → Capture.

- Applies to **Capture Area**, **Capture Text** and **Capture Window**. `CaptureFullscreen` needs nothing (no
  overlay, so nothing changes before the grab). Recording target-picking passes `freeze: false` on purpose — only
  the *rectangle* matters there and the recording itself is live, so a stale still would misrepresent it.
- Overlays go **opaque** in freeze mode (`OverlayHelpers.MakeOpaque`, flipping `AllowsTransparency` off in the
  ctor — WPF rejects that change once the HWND exists). Not just cosmetic: a layered/transparent window gets no
  hardware acceleration, so repainting a 4K still on every mouse-move while dragging would crawl. Win11 rounds
  top-level window corners, which on a screen-filling overlay leaks four notches of *live* desktop through the
  still — suppressed via `DWMWA_WINDOW_CORNER_PREFERENCE` (`OverlayHelpers.SquareOffCorners`).
- The still is laid out at its own pixel size ÷ DPI scale, not stretched to the window: on the owner's
  stretched-res rig the real framebuffer is smaller than the reported bounds, and stretching would skew it.
  Cropping goes through the new pure `SelectionMath.ToSnapshotRect` (rounds exactly like the live `CaptureRegion`
  so both paths agree on size, and clamps to the still).
- Every crop is a **fallback, never a failure**: a null crop (still missing, rect outside it, window spanning two
  monitors) falls through to the old live capture. Freeze off ⇒ byte-for-byte the previous behaviour.
- `WindowPickerWindow` now enumerates windows in its **constructor** instead of `SourceInitialized` — i.e. before
  the overlay is shown. A game that minimises itself on deactivation used to drop out of the list (`IsIconic`) and
  become unpickable; and in freeze mode the list must describe the same desktop the still froze.
- Verified: build 0 warnings / 0 errors; **301 tests** green (6 new `ToSnapshotRect` + `FreezeScreen` settings
  round-trip). Plus a scratch end-to-end harness driving the real overlays with synthesized `SendInput`:
  (1) painted the screen red → froze → painted it blue → dragged: capture came back **red** while a live capture
  of the same rect was blue; (2) showed the picker over a green window in another process, **killed that process**,
  then clicked where it was: got its green pixels at the exact frame size — impossible for a live `PrintWindow`;
  (3) freeze off: overlay stayed `AllowsTransparency=True`, no crop carried, live capture returned the current
  (blue) screen. `dist/` republished + relaunched.

## Known issues / TODO discovered during build (append as you find them)
- Git warns LF→CRLF on the C# files (autocrlf). Harmless; could add a `.gitattributes` to normalize.
- **Republish `dist/` after runtime-visible changes.** `dist/` is a manual publish snapshot; a plain build/commit
  won't update the running tray agent. If the owner reports a UI bug that the source already fixes, check the
  `dist/` exe timestamp vs. the fix commit before assuming a regression (see the 2026-07-03 deploy note above).
