# BetterScreenshot: Sparkle auto-updates + the one-time "open at login?" prompt

(Draft, 2026-10-18 — full write-up follows once the end-to-end test has run.)

Branch `feat/sparkle-updates`, worktree
`/Users/davidghermansteinberg/Desktop/Home/Projects/Code/BetterScreenshot/.claude/worktrees/sparkle-updates`,
based on local `main` (c29f6c3, one commit ahead of `origin/main`).

## STATUS / NEXT STEPS

- Commit 1 (2d4c8ee): Sparkle wiring, release script, launch-at-login prompt + tests. Debug build OK,
  CaptureKit tests pass.
- Next: `scripts/sparkle-e2e-test.sh` (not written yet), full test run, UI render check, this README.
- **Blocker for a real release:** the "BetterScreenshot Code Signing" identity in
  `~/Library/Keychains/betterscreenshot-signing.keychain-db` was regenerated on 2026-10-18 (new
  certificate SHA-1 `08faa1f9…`); every published release and the installed app use `71ec62cd…`.
  The old keychain is at `~/Backups/2026-10-18-pre-sparkle/old-betterscreenshot-signing.keychain-db`
  (its password is unknown). `package-release.sh` refuses to package with a different certificate.
