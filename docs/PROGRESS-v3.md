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
| — | Coordinator | Windows doc §A (`6a1304e`), all merges, CHANGELOG/README/CLAUDE.md, full verification | **done** 2026-09-24 | `main` |

**Known follow-ups** (after all lanes merge):
- Mid-recording microphone device switch from the live pill (needs Part 4's device catalog + Part 5's
  pill) — spec §8.
- History thumbnail isn't regenerated after the video editor's Replace Original (pre-existing).

**Gotcha (stale root build):** after merging a branch that adds files to a `Packages/*` library, the
root `swift build` may fail with "cannot find X in scope" — delete `.build/debug.yaml` (the cached
build plan; regenerated) and rebuild. A full `swift package clean` also works but rebuilds everything.

**Gotcha:** the Agent tool's `isolation: worktree` creates worktrees from `origin/main` (`d577e0f`),
not local `main` — every agent must first `git merge --ff-only <local main hash>`.

**If a session ends mid-way:** check `git branch` / `git worktree list` for agent branches, read the
table above, merge what's finished, and relaunch only unfinished lanes with the spec sections named.
