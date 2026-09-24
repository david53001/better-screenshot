# v3 build progress (editor & recording overhaul)

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
| 1 | Editor foundation | Part 1 | launched 2026-09-24 | — |
| 1 | Video | Part 0 → Part 6 | launched 2026-09-24 | — |
| 1 | Recording setup | Part 4 | launched 2026-09-24 | — |
| 1 | Live pill | Part 5 | launched 2026-09-24 | — |
| 2 | Text | Part 2 | waits for Part 1 merge | — |
| 2 | Redaction + tools | Part 3 | waits for Part 1 merge | — |
| — | Coordinator | Windows doc §A (2026-09-24 features), merges, docs | in progress | `main` |

**Known cross-lane follow-ups** (do after both lanes merge):
- Mid-recording microphone device switch from the live pill (needs Part 4's device catalog + Part 5's
  pill) — spec §8.

**If a session ends mid-way:** check `git branch` / `git worktree list` for agent branches, read the
table above, merge what's finished, and relaunch only unfinished lanes with the spec sections named.
