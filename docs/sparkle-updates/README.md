# BetterScreenshot: Sparkle auto-updates + the one-time "open at login?" prompt

Written 2026-10-18 for a fresh session with no context. BetterScreenshot is a SwiftPM menu-bar app
(no Xcode project; Command Line Tools only) in
`/Users/davidghermansteinberg/Desktop/Home/Projects/Code/BetterScreenshot`, GitHub
`david53001/better-screenshot` (**public** repo). This work is on branch `feat/sparkle-updates`
(worktree `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/BetterScreenshot/.claude/worktrees/sparkle-updates`),
based on **local** `main` at `c29f6c3` (the ⌘⇧3 takeover, one commit ahead of `origin/main` and not
pushed yet). It copies the approach MacStats got first (`MacStats/docs/sparkle-updates/README.md` on
MacStats' `feat/sparkle-updates` branch); JVoice gets the same.

## Glossary

- **Sparkle** (https://sparkle-project.org): the standard open-source auto-update framework for Mac apps
  outside the App Store. Version used: **2.10.0**, exactly.
- **Appcast**: an RSS/XML file listing available versions. Each installed app downloads it from its
  `SUFeedURL` and compares the newest item's `sparkle:version` with its own `CFBundleVersion`.
- **EdDSA signature**: every update zip is signed with a private ed25519 key; the app carries the
  matching public key (`SUPublicEDKey`) and refuses any download whose signature doesn't match. This is
  what makes updates safe, independent of Apple code signing.
- **Code signing identity**: the certificate `codesign` signs the app with. macOS ties the **Screen
  Recording** permission (TCC, macOS's privacy-permission database) to it, through the app's
  *designated requirement* (`identifier "com.betterscreenshot.mac" and certificate leaf = H"<cert SHA-1>"`).
- **`CFBundleVersion`** (build number, an integer here) vs **`CFBundleShortVersionString`** (the
  "3.2.0" users see). Sparkle compares the build number.
- **rpath**: folders baked into the executable where the dynamic loader looks for frameworks;
  `@executable_path/../Frameworks` = `BetterScreenshot.app/Contents/Frameworks`.
- **XPC service**: a helper process bundled inside an app/framework (`*.xpc`).
- **Hardened runtime**: an opt-in signing flag (`-o runtime`) that adds restrictions, incl. "library
  validation" (only load libraries signed by the same Team ID or Apple).
- **ATS** (App Transport Security): macOS's rule that apps only use HTTPS unless their Info.plist makes an
  exception (the e2e test adds one for its 127.0.0.1 server).
- **Universal**: one executable with an Apple Silicon (arm64) and an Intel (x86_64) slice.

## What was added

### 1. Sparkle auto-updates

| Piece | Where |
|---|---|
| `.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")`, linked into the app target with rpath `@executable_path/../Frameworks` | `Package.swift`, `Package.resolved` |
| `SUFeedURL` = `https://github.com/david53001/better-screenshot/releases/latest/download/appcast.xml`, `SUPublicEDKey` = `JrE6EncJErY++AZZXYrrwcNmcVzY/M2wgDWcCkaBf6U=`, `SUEnableAutomaticChecks` = YES (daily check, no "may we check?" dialog). Version **3.2.0**, build **12** (3.1.0 was 11; no branch has a higher one) | `App/Info.plist` |
| Updater: `SPUStandardUpdaterController`, started at launch, "gentle reminders" (a background find opens Sparkle's window *behind* other apps, never stealing focus). So it isn't missed, the menu item reads **"Update Available (X)…"** and Settings says "Version X is available." with **Show Update…** until the user looks at Sparkle's window. No notification (BetterScreenshot never asks for that permission). | `App/Lifecycle/Updates.swift` (started in `AppDelegate`) |
| Menu bar: **Check for Updates…** above Settings… | `App/MenuBar/MenuBarController.swift` |
| Settings → **UPDATES** card (column B, under Pin to Screen): "Check automatically" switch (sub "Look for a new version once a day", ⓘ text in `SettingsHelp.checkForUpdates`), **Check for Updates…** / **Show Update…** button, "You have BetterScreenshot X." | `App/Settings/SettingsView.swift` (`updatesCard`) |
| Bundle: copies `Sparkle.framework` into `Contents/Frameworks` (ditto, keeps symlinks), removes its `XPCServices`, `Headers`, `PrivateHeaders`, `Modules`; deletes every absolute rpath except `/usr/lib/swift` (in every slice) and fails if an `@rpath` library other than Sparkle appears. Universal builds now copy each slice out right after building it (Swift 6.4's default `swiftbuild` system puts both triples in `.build/out/Products/<Config>`, so the old script lipo'd x86_64 twice and failed). `BETTERSCREENSHOT_APP` / `BETTERSCREENSHOT_SWIFT_FLAGS` / `BETTERSCREENSHOT_REQUIRE_IDENTITY` env vars | `scripts/build-app.sh` |
| Signing, inside-out, no `--deep`: `Autoupdate`, `Updater.app`, the framework (all `-o runtime`, as Sparkle ships them), then the app with `App/BetterScreenshot.entitlements` (no hardened runtime, as before) | `scripts/sign-app.sh` (new; `build-app.sh` calls it) |
| SDK pin: the CLT's default MacOSX27.0 SDK can't build SwiftUI macros, so builds use `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` when present (an `SDKROOT` you set wins) | `scripts/sdk-env.sh`, sourced by `build-app.sh` and `test.sh` |
| One-command release | `scripts/package-release.sh` |
| Real end-to-end update test | `scripts/sparkle-e2e-test.sh` |

**Not sandboxed** (checked: `App/BetterScreenshot.entitlements` has no `com.apple.security.app-sandbox`).
So Sparkle installs through its bundled `Autoupdate` / `Updater.app`; the framework's XPC services are
only for sandboxed apps (and only when `SUEnableInstallerLauncherService` / `SUEnableDownloaderService`
are set, which they aren't), and Sparkle's docs say a non-sandboxed app may remove them, so
`build-app.sh` does. The end-to-end test passes without them.

**Why the app has no hardened runtime:** it never had one (not notarized). Hardened runtime turns on
library validation, which would refuse a `Sparkle.framework` signed by a self-signed certificate (no
Team ID).

**Network:** the only network traffic Sparkle adds is the appcast + zip download from GitHub (no
system profile: `SUEnableSystemProfiling` is unset). This respects CLAUDE.md's "No cloud" rule (nothing
of the user's is uploaded).

### 2. "Open BetterScreenshot at login?" after 5 captures

Before: up to 3.1.0, the first launch turned launch at login on silently (`AppDelegate`, flag
`didRegisterLaunchAtLogin`). That is **removed**. Now:

- A **use** = one screenshot capture that produced an image: area, window, full screen, or Capture Text
  (after recognition ran). A cancelled selection or a failed capture isn't one (`CaptureCoordinator.onCaptureCompleted`,
  called at the end of `handle(_:)` and after Capture Text's HUD).
- After the **5th** use, the app checks once a second (for up to 120 s; the next capture tries again) for a
  **calm moment**: ≥ 3 s since that capture, no key pressed for ≥ 2 s (`CGEventSource.secondsSinceLastEventType`,
  needs no permission — checked), no mouse button down (no drag of the thumbnail in progress), no
  selection overlay / countdown / record strip / recording, and none of BetterScreenshot's windows in
  front (`NSApp.isActive` false — not while annotating or in Settings). Then it shows the card.
- **The card** (`Packages/OverlayKit/Sources/OverlayKit/PromptCardController.swift`): a notification-style
  card in the **top-right** corner of the screen under the pointer, 12 pt below the menu bar (bottom-right
  when Settings → Quick Access → Screen corner is top-right, so it never sits on the thumbnails). The app
  icon, **"Open BetterScreenshot at login?"**, "Your capture shortcuts keep working after a restart. You can
  change this any time in Settings.", **No Thanks** (outline) and **Open at Login** (white, primary).
  - Never takes focus: a borderless `.nonactivatingPanel` that can't become key; its buttons take the first
    click. So no keyboard shortcuts on it (there's no focus to receive them) — by design.
  - Never in a capture: its window IDs are in `CaptureCoordinator.tourTagWindowIDs` (excluded from area,
    window, full screen, Capture Text and the frozen still), and its window is registered with
    `TourTagRecordingGate`, which keeps it out of display recordings from its first frame (it's invisible
    to the recorder until the stream's filter excludes it). While a selection overlay is up, the overlay
    (screen-saver level) covers it.
  - Design (BetterScreenshot's DesignKit = the MacStats design language for floating surfaces): the app's one
    dark floating surface `HUDSurfaceView` (blur + black tint, continuous 16 pt corners, 0.5 pt hairline, one
    system shadow), held at least at the default opacity (`HUDSurfaceView.minimumOpacity`, new) so the
    Opacity slider can't make it lighter. All text is pure white (not the 80 % secondary, which measures 3.8:1):
    **≥ 4.86:1 over an opaque white page**, the measured value for the default tint
    (`docs/PROGRESS-2026-09-30-opacity.md`). Buttons: primary white fill + near-black text (≈ 18:1), secondary
    white outline + white text (same ≥ 4.86:1) — the tour tag's button pair; hover and press feedback.
  - VoiceOver announces the title and line when it appears.
- **No Thanks** → card goes, never asked again. **Open at Login** → `SMAppService.mainApp.register()`, then:
  enabled → "BetterScreenshot will open at login." for 1.6 s, then the card goes; `.requiresApproval` →
  "One more step / Allow BetterScreenshot in Login Items to finish." + **Done** / **Open Login Items**
  (`SMAppService.openSystemSettingsLoginItems()`); error → "Couldn't turn it on. / You can try again in
  Settings → Launch at login." + **Done**.
- The card stays until answered (one time ever). If the app quits while it's up unanswered, it is still due
  and comes back after a later capture.
- **Settings switch in sync:** `LaunchAtLogin.setEnabled` posts `LaunchAtLogin.didChangeNotification`; the
  Settings → Startup → Launch at login switch re-reads `SMAppService` on it (and on appear). Any choice made
  with the switch counts as answered (`setEnabled` marks it asked), and closes the card if it's up.
- **Asked at most once ever. Never asked if launch at login is already on** (checked when it becomes due and
  again right before showing).
- **Existing users**: if `didRegisterLaunchAtLogin` is set, ≤ 3.1.0 already turned it on for them; they either
  still have it (nothing to do) or turned it off on purpose (respected): never asked, and their uses aren't
  counted.
- Same rules as MacStats (5 uses, once, legacy flag, Settings counts as an answer). Differences, because this
  app has no panel to put a card in: a use is a capture, not a panel open; the card is a corner card shown at
  a calm moment instead of inside MacStats' panel; there are no "quick dismissals" (the card can't be glanced
  away — only answered).

**UserDefaults keys** (domain `com.betterscreenshot.mac`):

| Key | Type | Meaning |
|---|---|---|
| `launchAtLoginPromptUses` | Int | Completed captures counted so far (stops at 5) |
| `launchAtLoginPromptAsked` | Bool | Answered on the card, or chosen in Settings: never ask again |
| `didRegisterLaunchAtLogin` | Bool | Legacy, **read only**: ≤ 3.1.0 auto-enabled launch at login |

Code: rules + calm-moment test (pure, tested) `Packages/CaptureKit/Sources/CaptureKit/LaunchAtLoginPrompt.swift`;
tests `Packages/CaptureKit/Tests/CaptureKitTests/LaunchAtLoginPromptTests.swift` (12: threshold, already
enabled, already asked, legacy flag, counter cap, persistence, Settings choice, every calm-moment condition);
card `Packages/OverlayKit/Sources/OverlayKit/PromptCardController.swift`; flow
`App/MenuBar/LaunchAtLoginPromptController.swift`; wiring `App/Lifecycle/AppDelegate.swift`;
`App/SystemIntegration/LaunchAtLogin.swift`.

To see the card on a dev build without 5 captures (only where you're happy to change BetterScreenshot's own
settings, i.e. not on the owner's running copy): quit the app, `defaults write com.betterscreenshot.mac
launchAtLoginPromptUses -int 5; defaults delete com.betterscreenshot.mac launchAtLoginPromptAsked; defaults
delete com.betterscreenshot.mac didRegisterLaunchAtLogin`, make sure launch at login is off, launch, take one
screenshot, then don't type for a few seconds.

**Unmerged related branch:** `feat/launch-at-login` (61393b7, 2026-10-01) adds an "Allow it in System
Settings" hint under the Settings switch and a Settings-tour step whose text says new users "have it on
already". That text is wrong after this branch; if it's merged, change the step's comment/body (and the
hint's helpers `needsApproval` / `openSystemSettings`, which this branch also adds with identical code, will
conflict trivially).

## Where the keys live (and their backups)

- **Sparkle EdDSA private key**: login Keychain, item "Private key for signing Sparkle updates", account
  `ed25519`. Sparkle's tools read it from there. Off-Keychain backup: `~/Backups/sparkle-signing-key/` (its
  `README.md` explains the files and how to restore with
  `~/Developer/Sparkle/2.10.0/bin/generate_keys -f …`). Same key for all three apps. **Never commit, print or
  upload the private key.** If it's lost, installed copies can't be updated any more.
- **Code signing identity "BetterScreenshot Code Signing"**: keychain
  `~/Library/Keychains/betterscreenshot-signing.keychain-db` (password `betterscreenshot-local`, in
  `scripts/setup-signing.sh` on purpose: it only protects this local self-signed cert).
  **⚠ Problem found 2026-10-18:** the keychain now on this Mac holds a certificate created **today**
  (SHA-1 `08faa1f906d59fae5a9ccb84d00979030fb26b2b`). Every published release since v2.10.0 and the copy in
  `/Applications` are signed with `71ec62cdf447d86a147727f0184a1f83bc5135cb`. According to
  `~/Backups/2026-10-18-pre-sparkle/README.md`, the old keychain's password no longer matched the script, so it
  was moved to `~/Backups/2026-10-18-pre-sparkle/old-betterscreenshot-signing.keychain-db` and a new identity
  was made. A release signed with the new certificate makes **every user allow Screen Recording again**
  (CLAUDE.md: "Updates must never cost users their permission"). So `package-release.sh` refuses any
  certificate except `RELEASE_CERT` (= `71ec62cd…`). Options (owner decides): (a) recover the old keychain's
  password, put it back in `~/Library/Keychains/` and on the search list, and back it up; or (b) accept a
  one-time re-grant for 3.2.0: set `RELEASE_CERT` in `scripts/package-release.sh` to the new hash, say so in
  the release notes, and back up the new keychain.
- Sparkle CLI tools: `/Users/davidghermansteinberg/Developer/Sparkle/2.10.0/bin` (`sign_update`,
  `generate_appcast`, `generate_keys`). The same tools come with the SwiftPM artifact in
  `.build/artifacts/sparkle/Sparkle/bin`.

## How to cut a release (step by step)

All from the repo root on `main`, with this branch merged:

```bash
cd /Users/davidghermansteinberg/Desktop/Home/Projects/Code/BetterScreenshot
git switch main
# 0. (first time only) merge: git merge --no-ff feat/sparkle-updates
# 1. Bump the version in App/Info.plist:
#    CFBundleShortVersionString (e.g. 3.2.0 -> 3.3.0) AND CFBundleVersion (+1, e.g. 12 -> 13).
# 2. Tests:
scripts/test.sh
# 3. Commit the bump and push it (package-release.sh refuses a dirty tree or HEAD != origin/main):
git commit -am "release: v3.3.0" && git push origin main
# 4. Release notes (Markdown, outside the repo so the tree stays clean); they become the GitHub notes and
#    Sparkle's update text. Then build (universal) + sign + zip + EdDSA-sign + appcast:
$EDITOR /tmp/betterscreenshot-notes.md
scripts/package-release.sh /tmp/betterscreenshot-notes.md
# 5. Run the gh command the script printed, which looks like (--target = the packaged commit):
gh release create v3.3.0 "<repo>/dist/BetterScreenshot.app.zip" "<repo>/dist/appcast.xml" \
    --repo david53001/better-screenshot --target <HEAD sha> --latest --title "BetterScreenshot v3.3.0" \
    --notes-file "<repo>/dist/release-notes.md"
```

`package-release.sh` outputs `dist/BetterScreenshot.app.zip` (the asset both `scripts/install.sh` and Sparkle
download), `dist/appcast.xml` (one item: this version, `sparkle:version` = build number, minimum macOS,
Markdown notes, enclosure `https://github.com/david53001/better-screenshot/releases/download/vX.Y.Z/BetterScreenshot.app.zip`
with its EdDSA signature and length) and `dist/release-notes.md`. It publishes nothing itself.
(`dist/` is in `.gitignore`.)

Guards (it refuses; the overrides are for dry runs only, never for a real release):

| Refuses when | Override |
|---|---|
| `git status --porcelain` is not empty | `ALLOW_DIRTY=1` |
| `HEAD` isn't `origin/main` (after `git fetch origin main`) | `ALLOW_NOT_MAIN=1` |
| the built app's certificate isn't `RELEASE_CERT` (checked after the build) | `ALLOW_NEW_CERT=1` |
| a GitHub release with tag `vX.Y.Z` already exists, or `gh` can't tell | none: bump the version |
| `CFBundleVersion` isn't a whole number, or isn't above the published appcast's | none |
| "BetterScreenshot Code Signing" missing (no ad-hoc fallback for releases) | none |

### The `--latest` rule

Every installed copy reads `releases/latest/download/appcast.xml`, and `scripts/install.sh` reads
`releases/latest/download/BetterScreenshot.app.zip`: GitHub serves those from whichever release is marked
**Latest**. So:

- Every Mac release **must** be created with `--latest` and attach both `BetterScreenshot.app.zip` and
  `appcast.xml`.
- Every **Windows** release (tags `windows-vX.Y.Z`, from the `windows-port` branch) **must** be created with
  `--latest=false`, or the Mac feed 404s and every Mac copy stops seeing updates (and the curl installer breaks).
- Checked 2026-10-18: there are no release workflows (`.github/workflows/ci.yml` only builds + tests; Windows
  `windows/scripts/publish-app.ps1` only builds). `windows-v1.0.0` was created with `--latest=false` and is
  not Latest (`v3.1.0` is). The rule is already in `CLAUDE.md` and in `windows/docs/PROGRESS.md` on
  `windows-port` (its "Next Windows release" step uses `--latest=false`). Nothing needed fixing.
- First Sparkle release: 3.1.0 and older have no Sparkle, so their users get 3.2.0 once via the install
  one-liner (`curl -fsSL https://raw.githubusercontent.com/david53001/better-screenshot/main/scripts/install.sh | bash`);
  Sparkle takes over from there.

## How to re-run the end-to-end test

```bash
cd /Users/davidghermansteinberg/Desktop/Home/Projects/Code/BetterScreenshot/.claude/worktrees/sparkle-updates   # or the repo root after merging
scripts/sparkle-e2e-test.sh                    # temp dir, deleted afterwards
KEEP=1 scripts/sparkle-e2e-test.sh /some/dir   # keep logs/builds for inspection
```

Needs the "BetterScreenshot Code Signing" identity and the Sparkle key in the Keychain; about a minute
(one debug build into its own scratch folder). What it does: builds with `-DSPARKLE_E2E_TEST` — Sparkle
steps logged to stderr, a downloaded update installs immediately via Sparkle's `immediateInstallationBlock`
instead of on quit, and the app starts **nothing but the updater** (no status item, hotkeys, native-shortcut
changes, history, temp-file sweeps, onboarding; and it never restores the native ⌘⇧3/4/5 on quit), because
the real app's history folder, temp files and shortcut settings are shared, not keyed by bundle id. Makes an
OLD copy (build 100, "90.0") and a NEW copy (build 101, "90.1") with bundle id
`com.betterscreenshot.mac.sparkletest`, `SUFeedURL` = `http://127.0.0.1:8766/appcast.xml`,
`SUAutomaticallyUpdate` = YES, local-networking ATS exception, signed with the real identity; zips NEW and
signs it with the real EdDSA key; serves it with `python3 -m http.server` bound to 127.0.0.1 only; sets the
test id's `SULastCheckTime` to 2000 so the check is due; runs OLD and waits for the installed copy to become
build 101 (GOOD), then repeats with an appcast whose signature belongs to other bytes (BAD) and expects build
100 to stay. It never touches `/Applications`, the real bundle id's defaults or the running copy, quits
everything it started and deletes the test id's defaults, caches and Launch Services entries. Exit 0 = both
PASS.

Result 2026-10-18 (this Mac, macOS 26, Swift 6.4):

```
==> GOOD: signed update 100 -> 101
SPARKLE-E2E found 90.1 (build 101)
SPARKLE-E2E downloaded 101
SPARKLE-E2E ready to install 101; installing now
SPARKLE-E2E installing 101
installed copy: codesign --verify --deep --strict OK
Identifier=com.betterscreenshot.mac.sparkletest
Authority=BetterScreenshot Code Signing
running after relaunch: <pid> …/install/BetterScreenshot.app/Contents/MacOS/BetterScreenshot
==> BAD: zip whose EdDSA signature doesn't match
SPARKLE-E2E aborted: … Code=4005 "The update is improperly signed and could not be validated." … Code=3002
  "EdDSA signature does not match. Data of the update being checked is different than data that has been signed …"
GOOD update installed (build 101): PASS
BAD signature refused (still build 100): PASS
```

### Manual checklist for the first real update (3.2.0 → 3.2.1)

The e2e test installs at once; real users get Sparkle's window instead. The first time a later release
exists, on a Mac running the previous release (owner):

1. Wait for (or force: quit the app, `defaults write com.betterscreenshot.mac SULastCheckTime -date "2000-01-01 00:00:00 +0000"`,
   relaunch) the scheduled check. Expect Sparkle's update window to open **without taking focus**.
2. Menu bar: the item reads "Update Available (3.2.1)…". Settings → Updates: "Version 3.2.1 is available." +
   **Show Update…**.
3. Click either: Sparkle's window comes to the front. **Install Update** → **Install and Relaunch**.
4. The app relaunches as 3.2.1; captures work **without a new Screen Recording prompt** (only true if both
   releases are signed with the same certificate — see the ⚠ above).

## STATUS / NEXT STEPS

- 2026-10-18: both features built and committed on `feat/sparkle-updates` (not merged, pushed, installed or
  released). Commits: `2d4c8ee` (features), `1366d80` (Settings layout + card centring after render),
  the universal-build fix, and docs.
- Verified 2026-10-18:
  - `scripts/test.sh`: all 7 suites pass (DesignKit 9, CaptureKit 135 incl. 12 new, OverlayKit 50,
    EditorKit 155, RecordingKit 92, HistoryKit 41, TourKit 119).
  - `scripts/build-app.sh` (debug): builds, `codesign --verify --deep --strict` OK; rpaths only
    `/usr/lib/swift`, `@loader_path`, `@executable_path/../Frameworks`; framework holds only `Autoupdate`,
    `Resources`, `Sparkle`, `Updater.app`; designated requirement unchanged in form (identifier + cert leaf).
  - `scripts/sparkle-e2e-test.sh`: GOOD PASS + BAD PASS (output above); afterwards no test process, server,
    defaults domain or work dir left; the real `/Applications` copy kept running.
  - `scripts/package-release.sh` guards: untracked file → refused; HEAD ≠ origin/main → refused; full universal
    build with the current keychain → **refused: certificate 08faa1f9… ≠ 71ec62cd…** (works as intended); with
    `ALLOW_NOT_MAIN=1 ALLOW_DIRTY=1 ALLOW_NEW_CERT=1` (dry run): `x86_64 arm64`, signature OK, `appcast.xml`
    passes `xmllint`, the printed command has `--latest` and both assets. Nothing was published.
  - Off-screen renders (scratch probes, deleted): all four card states (layout, wrapping, buttons) and the
    real `SettingsView`, light + dark (Updates card in column B, button not truncated).
- **Not tested** (needs the owner or a real release): the card live in the running app (5 real captures — a
  second app instance would fight the real one for hotkeys and the native-shortcut settings, so it wasn't
  run); the blur/tint on screen (off-screen renders don't draw the blur, so contrast relies on the earlier
  4.86:1 measurement); a real Login Items `.requiresApproval` path; Sparkle's own window and "Install and
  Relaunch" (checklist above); the x86_64 slice running on an Intel Mac.

**NEXT STEPS (in this order):**

1. **Owner: decide the signing certificate** (⚠ section above). Until then no release can be cut without
   costing every user their Screen Recording permission.
2. Owner: review and merge `feat/sparkle-updates` into `main` (`git switch main && git merge --no-ff
   feat/sparkle-updates`), push `main` (it also carries the unpushed ⌘⇧3 commit `c29f6c3`).
3. Cut 3.2.0 with the steps above; install it on this Mac with the one-liner; then run the manual checklist
   with 3.2.1.
4. Optional: `feat/launch-at-login` (see the note in section 2) — merge it with the tour-step text fixed, or drop it.
