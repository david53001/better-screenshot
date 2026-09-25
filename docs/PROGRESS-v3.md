# v3 build progress (editor & recording overhaul)

**Status 2026-09-24: all Parts 0–6 built and merged into local `main`; not pushed, not tagged, no
version bump.** Verified: `scripts/test.sh` all green (388 tests), `scripts/build-app.sh release`
builds + signs. Nothing has been clicked through by a human yet — agents verified UI with headless
probes (synthetic events + snapshots in `docs/parity-v3/`). Suggested manual pass: record a real
window with mic + system audio (mute, switch window, pause), edit it (split/delete/speed/GIF), and
annotate a screenshot (text styles, corner scaling, highlighter, spotlight, blur strength, zoom).

Spec (approved by the owner 2026-09-24; the owner said **no separate implementation plans** — build
straight from the spec): `docs/superpowers/specs/2026-09-24-betterscreenshot-editor-recording-v3-design.md`.
Windows handoff (every part fills its section): `docs/MAC-TO-WINDOWS-PARITY-v3.md`.

**How the work is run.** A coordinating Claude session launches sub-agents, each in its own git
worktree + branch off `main`, then merges their branches into `main` (local only — **do not push**
until the owner says so), resolves conflicts, updates CHANGELOG / README / CLAUDE.md, and runs the
full verification (`scripts/test.sh`, `scripts/build-app.sh`). Builds inside agents use `-j 2` to
keep the Mac responsive.

| Wave | Lane | Parts | Status | Branch / commits |
|---|---|---|---|---|
| 1 | Editor foundation | Part 1 | **merged** into `main` (`5ec3353`) | `c4970e4`, `7ae880f`, `98c394c` |
| 1 | Video | Part 0 → Part 6 | **merged** into `main` (`1c35231`); card/History labels renamed "Edit video" / "Edit Video…" (`fc4eb2d`) | `a109557`…`cc021cd` |
| 1 | Recording setup | Part 4 | **merged** into `main` (`9308009`) — "Only this app" audio dropped (SCK single-app capture misses helper processes, e.g. browsers); fixed window recordings having no system audio | `cfdd8c8`…`82d1b08` |
| 1 | Live pill | Part 5 | **merged** into `main` (`85b214b`) — also fixed a pre-existing A/V drift after pausing on a static screen | `f88cf6c`…`82fc870` |
| 2 | Text | Part 2 | **merged** into `main` (`4347104`) | `c206a2f`, `0b324b9`, `f275179` |
| 2 | Redaction + tools | Part 3 | **merged** into `main` (`dc1c11e`) | `9b40dfe`…`fc056b0` |
| 3 | Tours & help | Part 7 (spec §14 + **§14.9: new users only, asked first**) | **merged** into `main` 2026-09-26: skeleton `c297463`/`2f71020` · 7A engine + audience + coordinator + question + menu + Settings row (`6b70d65`) · 7B tag overlay + ⓘ (merged with the switch to the real overlay) · `6823daa` tag windows list · 7E editor tours (`04da849`) · 7S Welcome/Quick Access/Settings/History + screenshot exclusion · 7R strip/pill/video-editor tours + recording exclusion (`2e2d21a`). 537 tests pass. **Needs the owner's manual pass** — see follow-ups | — |
| 4 | UI fixes | Fix the independent UI review's issues (`docs/reviews/2026-09-25-ui-review.md`, overall 5/10): editor · recording strip/pill/countdown · video editor · app shell (Settings, History, Welcome, menu, Quick Access, overlays) | **merged** into `main` 2026-09-25 (`e85734a` video, `45dfd46` editor, `0584da9` strip/pill/countdown, `76a2a57` app shell) — all review items fixed except C2 (partly: Settings keeps its own dropdown style) and V6/Q3 (judged acceptable). After-screenshots: `docs/reviews/2026-09-25-ui-fixes/`. 433 tests pass | `674ae95`…`1fced9b` |
| — | Coordinator | Windows doc §A (`6a1304e`), all merges, CHANGELOG/README/CLAUDE.md, full verification | **done** 2026-09-24 | `main` |

**Known follow-ups** (after all lanes merge):
- **GitHub CI is red, and was before v3** (every push since at least 2026-09-08): `.github/workflows/ci.yml`
  runs on `macos-14`, whose older Swift compiler rejects `App/Capture/TempFileService.swift:24` ("reference
  to captured var 'self' in concurrently-executing code"); the owner's local toolchain accepts it. Fix by
  moving CI to a newer runner/Xcode (e.g. `macos-15`) and/or making that closure capture safely, then check
  the rest of the build on that compiler.
- **Not released yet:** everything since `v2.11.0` (v3 Parts 0–7, UI-review fixes, window placement, tours)
  is on `main` only. The README's install one-liner fetches the latest GitHub *release*, so users get it only
  after a release is tagged and published (signed with the stable identity — see root `CLAUDE.md`).
- Mid-recording microphone device switch from the live pill (needs Part 4's device catalog + Part 5's
  pill) — spec §8.
- History thumbnail isn't regenerated after the video editor's Replace Original (pre-existing).
- Tours review (2026-09-26): `docs/reviews/2026-09-26-tours-review.md` — **6/10**, 0 High · 17 Medium · 24
  Low. Fixing all of them in two parallel lanes from `21613cb` (which added `TourStep.requires` and
  `TourStep.placement`): engine/tag/keys (branch `worktree-agent-a75dc49b138318f9a`: T1–T8, S3, W4, I1,
  requires/placement) · content/copy/anchors (branch `worktree-agent-a72e97f56f750295a`: E2, R1–R3, P1–P4,
  X2–X4, V2–V4, S1–S2, W1–W3, Q1–Q3, H1–H2, C1, E3). **Both merged 2026-09-26**, plus W3's unbound
  shortcut text ("(not set)") and W1's side-tag sliding done by the coordinator (`bc151bf`). Everything
  fixed except: **R3 partly** (the strip's hint-step leader still crosses the System audio menu — no gap
  within reach); **T8** documented only (panel-hosted tours can't take Return/Esc — by design); **E4** trades
  covering Undo/Redo for covering the side panel's heading. Next: optionally re-run the `reviewer` skill for
  the post-fix score.
- Part 7 leftovers (2026-09-26): (a) **manual checks in the real app** — a real click on an outlined
  button in a titled window (synthetic clicks can't prove it), and the Welcome tour's menu-bar-icon step
  with the real status item (only tested with a stand-in); (b) the tag body can be cut off if it exceeds 2
  lines — fit tests cover all tours now, keep them passing when editing copy; (c) scrolling Settings while
  a step shows can put the box outside the window (overlay doesn't clip to the scroll view); (d) on a
  1470-pt screen some tags fall back to covering part of the panel/card they explain; (e) replaying a tool
  tour from the menu while another tool is active starts on a "drag" step with the wrong tool; (f) Help &
  Tours → Recording Setup Tour only queues until the strip next opens; (g) Capture Window child-window
  exclusion needs macOS 14.2+; (h) `App/Tours/NoOpTourTagPresenter.swift` is unused by the app (probes
  only); (i) re-run the `reviewer` skill for a post-fix score.
- UI-fix leftovers (2026-09-25): (a) two copies of the shared dark HUD style —
  `Packages/OverlayKit/Sources/OverlayKit/HUDStyle.swift` and
  `Packages/RecordingKit/Sources/RecordingKit/RecordingHUDStyle.swift` (same values; RecordingKit doesn't
  depend on OverlayKit) — merge if a shared module appears; (b) keyboard Tab between record-strip controls
  only works with macOS keyboard navigation on — verify on the real app; (c) 60% white secondary text on
  the HUD over very light content measures ~4.3:1 (just under WCAG's 4.5:1); (d) recording toasts raised
  by `RecordingCoordinator` are dark but have no icon (`HUDController.show(_:symbol:)` supports one);
  (e) re-run the `reviewer` skill to get the post-fix score.

**Gotcha (stale root build):** after merging a branch that adds files to a `Packages/*` library, the
root `swift build` may fail with "cannot find X in scope" — delete `.build/debug.yaml` (the cached
build plan; regenerated) and rebuild. A full `swift package clean` also works but rebuilds everything.

**Gotcha:** the Agent tool's `isolation: worktree` creates worktrees from `origin/main` (`d577e0f`),
not local `main` — every agent must first `git merge --ff-only <local main hash>`.

**If a session ends mid-way:** check `git branch` / `git worktree list` for agent branches, read the
table above, merge what's finished, and relaunch only unfinished lanes with the spec sections named.
