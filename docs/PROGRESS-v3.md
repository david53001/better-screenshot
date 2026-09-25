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
| 3 | Tours & help | Part 7 (spec §14 + **§14.9: new users only, asked first**) | **building since 2026-09-25**. Skeleton `Packages/TourKit` on `main` (model, events, anchors, per-area catalog files). **Phase 1** (parallel): 7A engine + audience + coordinator + Welcome question + menu + Settings row · 7B tag overlay + ⓘ button. **Phase 2** (after 7A/7B merge, parallel): 7E editor tours · 7R strip/pill/video-editor tours · 7S Welcome/Quick Access/Settings/History tours. Each lane: own worktree, fast-forward to local `main` first, `-j 2`, probes behind the owner's windows, updates its Part 7 subsection of the parity doc | — |
| 4 | UI fixes | Fix the independent UI review's issues (`docs/reviews/2026-09-25-ui-review.md`, overall 5/10): editor · recording strip/pill/countdown · video editor · app shell (Settings, History, Welcome, menu, Quick Access, overlays) | **merged** into `main` 2026-09-25 (`e85734a` video, `45dfd46` editor, `0584da9` strip/pill/countdown, `76a2a57` app shell) — all review items fixed except C2 (partly: Settings keeps its own dropdown style) and V6/Q3 (judged acceptable). After-screenshots: `docs/reviews/2026-09-25-ui-fixes/`. 433 tests pass | `674ae95`…`1fced9b` |
| — | Coordinator | Windows doc §A (`6a1304e`), all merges, CHANGELOG/README/CLAUDE.md, full verification | **done** 2026-09-24 | `main` |

**Known follow-ups** (after all lanes merge):
- Mid-recording microphone device switch from the live pill (needs Part 4's device catalog + Part 5's
  pill) — spec §8.
- History thumbnail isn't regenerated after the video editor's Replace Original (pre-existing).
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
