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
| Updater: `SPUStandardUpdaterController`, started at launch, "gentle reminders": a background find opens Sparkle's window *behind* other apps, without taking focus — **except** when Sparkle chooses "immediate focus", its documented default when the app was launched recently (e.g. at login) or the Mac had been idle: then the window opens in front, as in most Mac apps (verified 2026-10-18 by `E2E_UI=1 scripts/sparkle-e2e-test.sh`; round 1 of this doc wrongly said "never stealing focus"). So a window behind others isn't missed, the menu item and the Settings button both read **"Update Available (X)…"** (`Updates.actionTitle`) until the user looks at Sparkle's window. No notification (BetterScreenshot never asks for that permission). | `App/Lifecycle/Updates.swift` (started in `AppDelegate`) |
| Menu bar: **Check for Updates…** above Settings… | `App/MenuBar/MenuBarController.swift` |
| Settings → **UPDATES** card (column B, under Pin to Screen): "Check automatically" switch (sub "Look for a new version once a day", ⓘ text in `SettingsHelp.checkForUpdates`), **Check for Updates…** / **Update Available (X)…** button (same label as the menu), "You have BetterScreenshot X." | `App/Settings/SettingsView.swift` (`updatesCard`) |
| Bundle: copies `Sparkle.framework` into `Contents/Frameworks` (ditto, keeps symlinks), removes its `XPCServices`, `Headers`, `PrivateHeaders`, `Modules`; deletes every absolute rpath except `/usr/lib/swift` (in every slice) and fails if an `@rpath` library other than Sparkle appears. Universal builds now copy each slice out right after building it (Swift 6.4's default `swiftbuild` system puts both triples in `.build/out/Products/<Config>`, so the old script lipo'd x86_64 twice and failed). `BETTERSCREENSHOT_APP` / `BETTERSCREENSHOT_SWIFT_FLAGS` / `BETTERSCREENSHOT_REQUIRE_IDENTITY` env vars | `scripts/build-app.sh` |
| Signing, inside-out, no `--deep`: `Autoupdate`, `Updater.app`, the framework (all `-o runtime`, as Sparkle ships them), then the app with `App/BetterScreenshot.entitlements` (no hardened runtime, as before) | `scripts/sign-app.sh` (new; `build-app.sh` calls it) |
| SDK pin: the CLT's default MacOSX27.0 SDK can't build SwiftUI macros, so builds use `/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` when present (an `SDKROOT` you set wins) | `scripts/sdk-env.sh`, sourced by `build-app.sh` and `test.sh` |
| One-command release | `scripts/package-release.sh` |
| Real end-to-end update test (automatic install; `E2E_UI=1`: Sparkle's real windows; `CROSS_CERT=1`: OLD signed with another certificate) | `scripts/sparkle-e2e-test.sh`, `App/Lifecycle/SparkleE2EUI.swift` (only in its `-DSPARKLE_E2E_TEST` build) |

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
  needs no permission — checked), no mouse button down (no drag of the thumbnail in progress), the menu-bar
  menu closed (`MenuBarController.isMenuOpen`, from its `NSMenuDelegate`: during menu tracking neither
  `NSApp.isActive` nor the mouse buttons show it), no selection overlay / countdown / record strip /
  recording, none of BetterScreenshot's windows in front (`NSApp.isActive` false — not while annotating
  or in Settings), and **nothing full-screen in front**: the frontmost app has no on-screen window (layer ≥ 0)
  that fills a screen — exactly the screen's frame, menu bar included (a full-screen app on a display without a
  notch, a Keynote presentation, a full-screen game), or, on a display with a notch, the full width down to the
  bottom edge starting just below the notch row (top ≤ `NSScreen.safeAreaInsets.top` + 2): on the owner's
  MacBook Air (1470×956, inset 32) a real full-screen window is `(0, 33, 1470, 923)` (measured by the round-3
  reviewer, 2026-10-18). A zoomed window stops at the menu bar and the Dock; the one look-alike, a zoomed window
  on a notched display with the Dock hidden, only makes the card wait. Read from `CGWindowListCopyWindowInfo`
  (bounds and owners need no permission); the rule is `LaunchAtLoginPrompt.fullScreenInFront`, tested with the
  measured window list. (While the screen is locked, loginwindow is frontmost with a full-screen window, so
  the card waits then too.) Then it shows the card.
- **The card** (`Packages/OverlayKit/Sources/OverlayKit/PromptCardController.swift`): a notification-style
  card in the **top-right** corner of the screen under the pointer, 12 pt below the menu bar (bottom-right
  when Settings → Quick Access → Screen corner is top-right, so it never sits on the thumbnails). The app
  icon, **"Open BetterScreenshot at login?"**, "Your capture shortcuts keep working after a restart. You can
  change this any time in Settings.", **No Thanks** (outline) and **Open at Login** (white, primary).
  - Never takes focus: a borderless `.nonactivatingPanel` that can't become key; its buttons take the first
    click. So no keyboard shortcuts on it (there's no focus to receive them) — by design. **Accessibility:**
    VoiceOver announces the title and line when it appears and can reach its two buttons (ordinary
    `NSButton`s, labelled; the window carries the title as its accessibility label), but Return/Escape and
    Full Keyboard Access can't reach a window that is never key. The **keyboard path** is the menu-bar menu:
    while the question is due (5 captures, unanswered, launch at login off) it has **Open at Login…** (above
    Check for Updates…), which asks the same question in a standard `NSAlert` (Return = **Open at Login**,
    Escape = **No Thanks**; then "One more step" with **Open Login Items** / **Done**, or "Couldn't turn it on."
    with **Done**). Choosing it closes the card if it's up. The **Settings → Startup → Launch at login** switch
    answers the question too.
  - **Unanswered, it goes away by itself** after **25 s** (`LaunchAtLoginPrompt.unansweredHideSeconds`; not
    while the pointer is on it), like a macOS banner, so it never sits over a presentation or a shared screen.
    It stays due. **Only a showing the user could have seen counts** (`LaunchAtLoginPrompt.Showing`, followed
    once a second): at least **5 s** (`minimumSecondsSeen`) during which the card's window was visible
    (`occlusionState.contains(.visible)` and `isOnActiveSpace`: not on another Space, not covered, the screen
    not locked or asleep) **and** the user had used the mouse or keyboard since the card appeared
    (`CGEventSource.secondsSinceLastEventType`, any input; no permission needed) — not a desk they walked away
    from. One late tick (the Mac slept with the card up) adds at most 2 s. A **counted** showing
    (`cardHidUnanswered`) is stored with its time (`launchAtLoginPromptLastShownAt`); the card comes back after
    a capture **≥ 24 h later** (`reshowAfterSeconds`, `mayShowAgain`), relaunches included — an automatic
    update relaunches the app, and that mustn't bring it back the same day (until round 3 a relaunch reset the
    spacing) — so a burst of screenshots can't show it 3 times in a few minutes (a clock set back doesn't hold
    it back); after the **3rd** counted one it counts as answered "no"
    (`maxShowings`, `launchAtLoginPromptAsked`). An **uncounted** showing comes back after a capture ≥ 10 min
    later (`reshowAfterUnseenSeconds`, kept in memory for this launch), so someone who never touches the mouse
    while it's up doesn't get it after every screenshot either.
  - It joins every Space. It has no `.fullScreenAuxiliary`, but that does **not** keep it off full-screen
    Spaces: checked 2026-10-18 on macOS 26.7.1 by the round-3 reviewer, a card-like panel from an accessory app
    stays visible and on screen on another app's full-screen Space (`docs/sparkle-updates/REVIEW-round3.md`,
    probe results 2–3). What keeps it off a full-screen app or presentation is the wait above
    (`fullScreenInFront`).
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
    white outline + white text (same ≥ 4.86:1) — the tour tag's button pair; hover and press feedback. The
    outline is a stroked continuous path (a layer border looked slightly rough at 2×). Fonts are text styles:
    title `.body` semibold (13 pt), line `.callout` (12 pt), buttons `.callout` semibold. **Deliberate
    deviation from the design language** (MacStats `docs/design-language/README.md`: small buttons are a
    0.08 / 0.12 / 0.16 fill with no border): that fill is meant for label-coloured text on panels; under white
    text on this surface it lightens what the text sits on, from the measured 4.86:1 to about 4.1:1 (0.08)
    or 3.8:1 (0.12) over a white page — computed from the measured value, below the 4.5:1 floor. The
    outline keeps 4.86:1.
  - VoiceOver announces the title and line when it appears.
- **No Thanks** → card goes, never asked again. **Open at Login** → `SMAppService.mainApp.register()`, then:
  enabled → "BetterScreenshot will open at login." for 1.6 s, then the card goes; `.requiresApproval` →
  "One more step / Allow BetterScreenshot in Login Items to finish." + **Done** / **Open Login Items**
  (`SMAppService.openSystemSettingsLoginItems()`); error → "Couldn't turn it on. / You can try again in
  Settings → Launch at login." + **Done**. Those two also go away by themselves after 25 s (not under the
  pointer; not counted as showings: the question is answered, and Settings shows the same state).
- If the app quits while the card is up unanswered, that showing isn't counted; it is still due and comes back
  after a later capture. The card's window is only created the first time it is shown (users who are never
  asked never get it).
- **Settings switch in sync:** `LaunchAtLogin.setEnabled` posts `LaunchAtLogin.didChangeNotification`; the
  Settings → Startup → Launch at login switch re-reads `SMAppService` on it (and on appear). Any choice made
  with the switch counts as answered (`setEnabled` marks it asked), and closes the card if it's up.
- **Answered at most once ever (at most 3 counted showings). Never asked if launch at login is already on**
  (checked when it becomes due and again right before showing; when found on, it is marked asked, so later
  captures don't call `SMAppService.mainApp.status` — an XPC call to the system — again).
- **Existing users**: if `didRegisterLaunchAtLogin` is set, ≤ 3.1.0 already turned it on for them; they either
  still have it (nothing to do) or turned it off on purpose (respected): never asked, and their uses aren't
  counted.
- Same rules as MacStats (5 uses, once, legacy flag, Settings counts as an answer). Differences, because this
  app has no panel to put a card in: a use is a capture, not a panel open; the card is a corner card shown at
  a calm moment instead of inside MacStats' panel; instead of MacStats' "quick dismissals", an unanswered card
  hides itself after 25 s and, if it could be seen, counts as one of its 3 showings (spaced ≥ 24 h apart);
  and a menu-bar **Open at Login…** item while it is due (the card can't take keyboard focus).

**UserDefaults keys** (domain `com.betterscreenshot.mac`):

| Key | Type | Meaning |
|---|---|---|
| `launchAtLoginPromptUses` | Int | Completed captures counted so far (stops at 5) |
| `launchAtLoginPromptAsked` | Bool | Answered on the card, chosen in Settings, ignored 3 times, or launch at login found on: never ask again |
| `launchAtLoginPromptUnansweredShowings` | Int | Times the card hid itself unanswered after the user could see it (3 → asked) |
| `launchAtLoginPromptLastShownAt` | Double | When the last such showing ended, seconds since 1970 (0 = never); the next needs ≥ 24 h, relaunches included |
| `didRegisterLaunchAtLogin` | Bool | Legacy, **read only**: ≤ 3.1.0 auto-enabled launch at login |

Code: rules, calm-moment test and the whole flow as steps that apply their own side effects, so the
controller only acts on the result (`afterCapture` records the capture → `.nothing` / `.tooSoon` /
`.startWaiting` / `.alreadyEnabled` (marks asked); `waitStep` → `.keepWaiting` / `.giveUp` / `.show` /
`.noLongerDue` / `.alreadyEnabled` (marks asked); `fullScreenInFront` (with each `Screen`'s notch inset);
`offersMenuItem` (the menu item; found enabled → marks asked); `shouldHideUnanswered`; `Showing.tick`
/ `.counts`; `cardHidUnanswered` (records only a counted showing and its time); `mayShowAgain`) in
`Packages/CaptureKit/Sources/CaptureKit/LaunchAtLoginPrompt.swift`,
behind a small storage protocol (`LaunchAtLoginPromptStorage`: `UserDefaults.standard` in the app, an in-memory
store in tests, so a test run writes no plist into `~/Library/Preferences`);
tests `Packages/CaptureKit/Tests/CaptureKitTests/LaunchAtLoginPromptTests.swift` (29: threshold, already
enabled, already asked, legacy flag, counter cap, persistence, Settings choice, every calm-moment condition incl.
the open menu and full screen, the full-screen window rule (two screens, zoomed window, desktop, other app) and
its notched-display case (`fullScreenOnANotchedDisplayStartsBelowTheNotch`: the measured `(0, 33, 1470, 923)`
window and strips, notch row covered, zoomed with the Dock, Dock at the side, a notched second screen), the
after-capture / wait steps with when the status is read and their own `markAsked`, the menu item
(`theMenuOffersTheQuestionOnlyWhileItIsDue`), the 25 s hide, seen vs unseen showings (other Space / locked,
walked away, came back late, a sleep), the 24 h spacing across relaunches
(`aSeenShowingComesBackOnlyADayLaterEvenAfterARelaunch`) and the 10 min one, the 3-showing cap);
card `Packages/OverlayKit/Sources/OverlayKit/PromptCardController.swift`; flow and the menu item's alert
(`askFromMenu`) `App/MenuBar/LaunchAtLoginPromptController.swift`; the menu item
`App/MenuBar/MenuBarController.swift` (`menuNeedsUpdate`); wiring `App/Lifecycle/AppDelegate.swift`;
`App/SystemIntegration/LaunchAtLogin.swift`.

To see the card on a dev build without 5 captures (only where you're happy to change BetterScreenshot's own
settings, i.e. not on the owner's running copy): quit the app, `defaults write com.betterscreenshot.mac
launchAtLoginPromptUses -int 5; defaults delete com.betterscreenshot.mac launchAtLoginPromptAsked; defaults
delete com.betterscreenshot.mac didRegisterLaunchAtLogin; defaults delete com.betterscreenshot.mac
launchAtLoginPromptLastShownAt`, make sure launch at login is off, launch, take one screenshot, then don't type
for a few seconds (move the mouse once while the card is up if you want that showing to count).

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
  password yourself (try `security unlock-keychain ~/Backups/2026-10-18-pre-sparkle/old-betterscreenshot-signing.keychain-db`
  and type `betterscreenshot-local`, then your login password); if it opens, copy it to
  `~/Library/Keychains/betterscreenshot-signing.keychain-db` (after moving the new one aside), put it on the
  search list (`security list-keychains -d user -s …`, see `scripts/setup-signing.sh`) and back it up; an agent
  must not try passwords on it (the auto-mode safety check refuses that as credential exploration); or
  (b) accept a one-time re-grant for 3.2.0: set `RELEASE_CERT` in `scripts/package-release.sh` to
  `08faa1f906d59fae5a9ccb84d00979030fb26b2b`, put the user steps below in the 3.2.0 release notes, and fix the
  CHANGELOG 3.2.0 line accordingly. **Sparkle itself accepts a code-signing change when
  the EdDSA signature is valid — tested 2026-10-18 (`b1eb0ea`, re-run after the round-3 fixes):** `CROSS_CERT=1 scripts/sparkle-e2e-test.sh`
  signs OLD with a different certificate ("JVoice Self-Signed", `1164938a…`) and NEW with the current
  "BetterScreenshot Code Signing" (`08faa1f9…`): the update installs and relaunches (installed copy carries
  `08faa1f9…`, `codesign --verify --deep --strict` OK) and a bad EdDSA signature is still refused (output in
  "How to re-run the end-to-end test"). What that test can't show is the Screen Recording re-prompt itself (the
  test copy never asks for it); that part follows from TCC keying the permission on the certificate.
  **What users must do after a certificate change (option b), for the 3.2.0 release notes.** macOS keys Screen
  Recording on the certificate, so the first version signed with `08faa1f9…` needs it allowed **once** more.
  The old entry usually stays in the list and still looks switched on, but doesn't match the new signature, so
  capture fails. Expected (from the code; not yet checked live, see below): BetterScreenshot's preflight,
  `CGPreflightScreenCaptureAccess`, reports no permission, so the app opens its "allow Screen Recording" setup
  window at launch and on the next capture. Text to paste:

  > **3.2.0 needs Screen Recording allowed once more** (its signing certificate changed). Open **System
  > Settings > Privacy & Security > Screen & System Audio Recording**, select **BetterScreenshot**, click
  > **−** (minus) below the list to remove the old entry (switching it off and on is not enough), then take a
  > screenshot and allow it when macOS asks; BetterScreenshot restarts itself once. In Terminal instead:
  > `tccutil reset ScreenCapture com.betterscreenshot.mac`, then take a screenshot and allow it.

  The same steps are in the repo README ("Screen Recording after an update"), so `install.sh` users find them
  too. **The owner too:** the first time a build signed with `08faa1f9…` runs as `com.betterscreenshot.mac` on
  this Mac (e.g. after installing a `dist/` build or 3.2.0 over the `71ec62cd…` copy in `/Applications`),
  Screen Recording has to be re-allowed the same way, once. Not yet checked live: that the stale entry really
  makes `CGPreflightScreenCaptureAccess()` return false while the list shows it on (it needs the real bundle id
  and a TCC grant, so only the owner can do it: on that first run, the setup window should open by itself).
  If you choose (a) instead, delete the "except once" sentences from the repo README's section.
  **The new keychain is backed up** (2026-10-18, round 1):
  `~/Backups/betterscreenshot-code-signing/new-08faa1f9-betterscreenshot-signing.keychain-db` (+ `README.md`
  with restore steps), so option (b) stays possible even if this Mac's copy is lost.
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
#    For 3.2.0 itself, SKIP this step: this branch already set 3.2.0 / build 12.
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

On a real run (no `ALLOW_*` variable), `package-release.sh` outputs `dist/BetterScreenshot.app.zip` (the asset both `scripts/install.sh` and Sparkle
download), `dist/appcast.xml` (one item: this version, `sparkle:version` = build number, minimum macOS,
Markdown notes, enclosure `https://github.com/david53001/better-screenshot/releases/download/vX.Y.Z/BetterScreenshot.app.zip`
with its EdDSA signature and length) and `dist/release-notes.md`. It publishes nothing itself.
(`dist/` is in `.gitignore`.)

Guards (it refuses; the overrides are for dry runs only, never for a real release). **Any override makes it a
dry run:** the outputs go to `dist/dry-run/` as `BetterScreenshot-DRYRUN.app.zip`, `appcast-DRYRUN.xml` and
`release-notes-DRYRUN.md` (plus the app), it ends with `DRY RUN - not publishable` and prints **no** `gh`
command. Never upload those files: their names aren't what the feed and `install.sh` download, and the dry-run
appcast carries `sparkle:edSignature="DRYRUN-not-signed"` and the enclosure URL `…/DRYRUN-not-a-release.zip`,
so even uploaded it can't install anything (signing itself is still exercised: `sign_update` signs and
verifies the dry-run zip, and that signature is then discarded).

| Refuses when | Override |
|---|---|
| `git status --porcelain` is not empty | `ALLOW_DIRTY=1` |
| `HEAD` isn't `origin/main` (after `git fetch origin main`) | `ALLOW_NOT_MAIN=1` |
| the certificate isn't `RELEASE_CERT`: checked on the keychain's identity **before building** (`security find-certificate -c "BetterScreenshot Code Signing" -Z ~/Library/Keychains/betterscreenshot-signing.keychain-db`, seconds) and again on the built app (its designated requirement) | `ALLOW_NEW_CERT=1` |
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
E2E_UI=1 KEEP=1 scripts/sparkle-e2e-test.sh /some/dir   # Sparkle's real windows (see "UI mode" below)
CROSS_CERT=1 scripts/sparkle-e2e-test.sh       # OLD signed with another certificate (see "Cross-certificate")
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

Since round 2 each run also prints both copies' certificates (`OLD certificate …, NEW certificate …`), and the
"loads Sparkle from:" line retries `vmmap` (it used to race the launch and print an empty path in BAD). Re-run
2026-10-18 after the round-2 changes: GOOD PASS, BAD PASS (same output as above), 51 s.

### Cross-certificate (`CROSS_CERT=1`): an update that changes the signing certificate

For option (b) of B1 (see "Where the keys live"). OLD is signed with `OTHER_IDENTITY` (default
"JVoice Self-Signed", any code-signing identity on the keychain search list; `scripts/sign-app.sh` takes it as
`BETTERSCREENSHOT_OTHER_IDENTITY`, test only) and NEW with the real "BetterScreenshot Code Signing"; then the
same GOOD and BAD runs. Result 2026-10-18:

```
OLD certificate 1164938af56472957620eeaaca96e33572677860, NEW certificate 08faa1f906d59fae5a9ccb84d00979030fb26b2b
...
cross-certificate: OLD 1164938a… ('JVoice Self-Signed') != NEW 08faa1f9…: PASS
installed copy now carries NEW's certificate: PASS
GOOD update installed (build 101): PASS
BAD signature refused (still build 100): PASS
```

### UI mode (`E2E_UI=1`): the path real users take

The default run installs at once (`SUAutomaticallyUpdate` + `immediateInstallationBlock`), so it never shows
Sparkle's windows. `E2E_UI=1` runs one more scenario instead of GOOD/BAD: OLD has no `SUAutomaticallyUpdate`
and runs with `SPARKLE_E2E_UI=1`, which turns on `App/Lifecycle/SparkleE2EUI.swift` (compiled only into the
`-DSPARKLE_E2E_TEST` build: `nm` on the normal build finds no `SparkleE2EUI` symbol) and makes the delegate leave
installation to Sparkle's own window. It waits for the scheduled check's update window, logs Sparkle's
`immediateFocus` choice, whether the window is key / the app active, and the menu title
(`Updates.actionTitle`); does what the menu item does (`Updates.showSparkleWindow`, minus activating the app) and
logs what is pending; then clicks **Install Update** and **Install and Relaunch** in Sparkle's windows and checks
the installed copy is build 101. Every window of the test app is made transparent the moment it appears
(nothing visible on screen, at most a ~50 ms flash). When Sparkle chooses immediate focus the test app becomes
active from launch until its first snapshot (a few seconds); from then on it hands focus straight back to the
app that was in front before (the script passes its bundle id from `lsappinfo` as `SPARKLE_E2E_RETURN_TO`;
`NSApp.deactivate()` alone did not work: still active a second later). The script prints "Don't type for
about 30 s" before launching.
Snapshots (`cacheDisplay`, no Screen Recording permission needed) go to `<work-dir>/ui/`. Since round 3 they
are drawn on the window's own background colour in its appearance (before, dark-mode labels were white on
transparent and looked blank), so the title, the buttons and the checkbox label are readable: the round-3
run's two snapshots are committed in `docs/sparkle-updates/e2e-ui-snapshots/`. The script refuses
`CROSS_CERT=1` together with `E2E_UI=1` (the UI scenario has no certificate checks; run them one after the
other) and refuses `E2E_UI=1` while the screen is locked (loginwindow in front: Sparkle's window can't get
the user's attention there, so two in-focus checks fail for a reason unrelated to the app — seen 2026-10-18,
see STATUS), both with exit 2 before building.

Result 2026-10-18 (round 1; the Mac had been idle for 79 min):

```
SPARKLE-E2E UI scheduled update 90.1, immediate focus 1
SPARKLE-E2E UI will show 90.1: handled by Sparkle 1, user-initiated 0
SPARKLE-E2E UI user attention for 90.1
SPARKLE-E2E UI update window shown: key 1, app active 1, frontmost app com.betterscreenshot.mac.sparkletest
SPARKLE-E2E UI menu title: Check for Updates…
SPARKLE-E2E UI after the menu action: pending none, menu title: Check for Updates…
SPARKLE-E2E UI clicking Install Update
SPARKLE-E2E downloaded 101
SPARKLE-E2E UI clicking Install and Relaunch
SPARKLE-E2E installing 101
update window shown by the scheduled check: PASS
(Sparkle chose immediate focus: launched just now / Mac idle 4791 s)
in focus: Sparkle reports the user's attention: PASS
in focus: the menu doesn't nag (Check for Updates…): PASS
the menu action leaves nothing pending: PASS
Install and Relaunch was offered and clicked: PASS
installed and relaunched as build 101: PASS
```

Re-run 2026-10-18 after round 2 (Mac idle 115 min): the same lines, plus `giving focus back to
com.apple.Terminal` and `focus now: app active 0`, and the new check
`the test app doesn't keep the keyboard (not active a second later): PASS` — 7/7 PASS.

What this showed: right after launch (and when the Mac is idle) Sparkle opens a scheduled update **in front,
with focus**, and reports the user's attention at once, so the "Update Available (X)…" label never appears in
that case. That is Sparkle's documented default (`SPUStandardUserDriverDelegate.h`: "may choose to show the
update in immediate and utmost focus when the app was launched recently or the system has been idle"). The
behind-other-windows branch (`key 0, app active 0`, label "Update Available (90.1)…") is checked by the script
when Sparkle takes it, but it can't be forced from a freshly launched test copy, so **it is still unverified**.

### Manual checklist for the first real update (3.2.0 → 3.2.1)

The default e2e run installs at once and the UI mode runs right after launch; real users usually get the
window later, behind their other windows. The first time a later release
exists, on a Mac running the previous release (owner):

1. Wait for (or force: quit the app, `defaults write com.betterscreenshot.mac SULastCheckTime -date "2000-01-01 00:00:00 +0000"`,
   relaunch) the scheduled check. Right after a launch Sparkle opens it in front (see UI mode above); for the
   case that matters here, leave the app running past the next daily check while you use the Mac: the window
   should open **behind** your windows, without taking focus.
2. If the window opened behind other windows: the menu bar item and the Settings → Updates button both read
   "Update Available (3.2.1)…". (If Sparkle opened it in front — app just launched, or the Mac was idle — the
   label stays "Check for Updates…": the user has seen it.)
3. Click either: Sparkle's window comes to the front. **Install Update** → **Install and Relaunch**.
4. The app relaunches as 3.2.1; captures work **without a new Screen Recording prompt** (only true if both
   releases are signed with the same certificate — see the ⚠ above).

## STATUS / NEXT STEPS

- 2026-10-18: both features built and committed on `feat/sparkle-updates` (not merged, pushed, installed or
  released). Commits: `2d4c8ee` (features), `1366d80` (Settings layout + card centring after render),
  the universal-build fix, docs, then **review round 1 fixes** (`a149104`), **review round 2 fixes**
  (`b1eb0ea`) and **review round 3 fixes** (the commit after it), all below.
- **Review round 1** (independent reviewer, 7.5/10; report `docs/sparkle-updates/REVIEW-round1.md`, untracked,
  with its renders in `docs/sparkle-updates/review-round1/`). What changed:
  - **B1 certificate** (owner decision, not code): still open; the release script still refuses
    `08faa1f9…`. New: the current keychain is backed up to `~/Backups/betterscreenshot-code-signing/`, and the
    ⚠ section above has the exact steps for (a) and (b). No agent tried the old keychain's password.
  - **M1 card never leaves** → fixed: an unanswered card hides after 25 s (not under the pointer), stays due,
    comes back after a later capture, ≤ 3 showings, then counts as "no" (new key
    `launchAtLoginPromptUnansweredShowings`). `.fullScreenAuxiliary` dropped: never over a full-screen app.
    Timeout, cap and hover rule are pure and tested in `LaunchAtLoginPrompt`.
  - **M2 dry run printed a live publish command** → fixed: any `ALLOW_*` = dry run → `dist/dry-run/*-DRYRUN.*`,
    "DRY RUN - not publishable", no `gh` command. The 14:41 dry-run files (`dist/BetterScreenshot.app.zip`,
    `dist/appcast.xml`, `dist/release-notes.md`) were deleted, and so were this round's own dry-run outputs.
  - **M3 tests leaked plists** → fixed: `LaunchAtLoginPrompt` takes a `LaunchAtLoginPromptStorage`
    (`UserDefaults` conforms); tests use an in-memory store. Measured: 110 leaked files before `scripts/test.sh`,
    110 after. The **old leaked files are not deleted** (needs the owner's OK, see NEXT STEPS).
  - **L1** certificate checked on the keychain before building (refused in 1.2 s, "Nothing was built"); the
    post-build check stays.
  - **L2** Sparkle's real UI path: new `E2E_UI=1` mode (section "UI mode"), run and passing. It found that the
    old "never steals focus" claim was wrong right after launch / when the Mac is idle (Sparkle's documented
    default); this README, `Updates.swift` and the manual checklist now say so. Behaviour unchanged: that is
    standard Sparkle UX, and suppressing it would mean the window only ever opens from our menu. **Owner can
    decide otherwise** (implement `standardUserDriverShouldHandleShowingScheduledUpdate` returning `false` when
    `immediateFocus`, and rely on the menu label).
  - **L3** launch at login found already on → marked asked (no more XPC status call per capture).
  - **L4** `menuIsOpen` added to `Moment` / `isCalmMoment` (from `MenuBarController`'s `NSMenuDelegate`).
  - **L5 keyboard / VoiceOver**: partly. The window now carries the title as its accessibility label; the
    buttons were already labelled `NSButton`s. A keyboard path would need the window to become key, i.e. take
    focus, which is the one thing the card must not do, so instead the README's accessibility line names the
    Settings switch as the full alternative.
  - **L6 design language**: fonts are now text styles (`.body` / `.callout`, same sizes), and the outline is a
    stroked continuous path (smooth at 2× in an off-screen render). **Disagreed, kept the outline** instead of
    the 0.08/0.12 filled secondary: under white text that fill drops contrast over a white page from 4.86:1 to
    about 4.1:1 / 3.8:1 (computed from the measured value), below 4.5:1. Reason recorded in
    `PromptCardButton`, `Packages/OverlayKit/CLAUDE.md` and section 2 above; the MacStats design-language doc
    was not edited (another repo).
  - **L7** flow logic moved into pure steps (`afterCapture`, `waitStep`, `shouldHideUnanswered`,
    `recordUnansweredShowing`), tested; the controller only carries them out.
  - **L8** DesignKit test `minimumOpacityKeepsASurfaceAtLeastAtTheDefault`.
  - **L9** the card's window is created on first show and registered with `TourTagRecordingGate` then.
  - **N1** CHANGELOG 3.2.0 permission line is conditional on the certificate; release step 1 says to skip the
    bump for 3.2.0. **N2** one label: the menu item and the Settings button both use `Updates.actionTitle`
    ("Update Available (X)…" / "Check for Updates…"); the Settings line always says "You have BetterScreenshot X.".
- **Review round 2** (another independent reviewer, 8.0/10; report `docs/sparkle-updates/REVIEW-round2.md`,
  untracked, renders in `docs/sparkle-updates/review-round2/`). What changed:
  - **B1 certificate** (owner decision): still open, the release script still refuses `08faa1f9…`. New: option
    (b) is now tested — `CROSS_CERT=1 scripts/sparkle-e2e-test.sh` (OLD signed with another certificate, NEW
    with `08faa1f9…`) installs, and a bad EdDSA signature is still refused. `RELEASE_CERT` was **not** changed:
    choosing (b) costs every user a Screen Recording re-grant, which is the owner's call.
  - **M1 unseen showings counted** → fixed: a showing counts only after ≥ 5 s visible on the active Space
    (`occlusionState` + `isOnActiveSpace`) with mouse/keyboard input since it appeared (`Showing`,
    `cardHidUnanswered`, tested). Also (the optional part) the app waits while anything full-screen is in front
    (`fullScreenInFront`, tested). Checked on the window server with a scratch probe (the card at 1 % opacity,
    click-through, ~2 s): `occlusionState` reports `.visible` within 0.5 s of `show` and not after `hide`, the
    any-input idle time reads without permission, `fullScreenInFront` false with Terminal in front, and showing
    the card doesn't activate the app. (In a process that doesn't run the AppKit event loop `.visible` never
    appears; the app does run it.) Extra guard: an unseen showing delays the next one by 10 min (in memory), so
    a user who never touches the mouse while it's up isn't shown it after every capture.
  - **L1 no spacing** → fixed: after a counted showing the card comes back only after a capture ≥ 24 h later or
    after a relaunch (`launchAtLoginPromptLastShownAt`, `mayShowAgain`, tested with a burst of captures).
  - **L2 result cards never hide** → fixed: "One more step" and "Couldn't turn it on." hide after 25 s too (not
    under the pointer, not counted).
  - **L3 a test re-implemented the controller** → fixed: `afterCapture` and `waitStep` are instance methods that
    record the capture / mark asked themselves; the controller only acts on `.startWaiting` / `.show`. Checked
    by mutation: dropping `markAsked()` from `afterCapture` makes
    `alreadyEnabledMarksItAskedSoLaterCapturesSkipTheStatusCall` fail.
  - **L4 dry run carried a real signature** → fixed: dry-run appcast has `edSignature="DRYRUN-not-signed"` and
    a `DRYRUN-not-a-release.zip` URL (`sign_update --verify` rejects it).
  - **L5 `E2E_UI=1` could take the keyboard** → fixed: warning printed first; after its first snapshot the test
    app hands focus back to the previously frontmost app (checked: `app active 0` a second later, new PASS line).
  - **L6 no keyboard path — not done, on purpose.** An "Open at Login…" menu item while the question is due
    would be a second UI for the same one-time question, shown to everyone between their 5th capture and their
    answer, for a case the Settings → Startup → Launch at login switch already covers fully (reachable from
    the menu with the keyboard, and it answers the question). The card stays mouse/VoiceOver only, as
    documented in section 2.
  - **N1** CHANGELOG: "without taking focus" and "slides away" reworded (and the new rules). **N2** stale
    comments in `SparkleE2EUI.swift` and `PromptCardController.swift` reworded, `Updates.swift:17` wrapped.
    **N3** e2e `vmmap` retries; the BAD run now logs the Sparkle path.
- **Review round 3** (another independent reviewer, 8.3/10; report `docs/sparkle-updates/REVIEW-round3.md`,
  untracked, probes and snapshots in `docs/sparkle-updates/review-round3/`). What changed:
  - **B1 certificate** (owner decision): **decided 2026-10-18 — option (b)**: `RELEASE_CERT` is now `08faa1f9…`
    and the v3.2.0 release notes carry the re-grant steps below. (Before that decision the guard refused
    `08faa1f9…`.) For option (b) the user re-grant steps now exist (L1 below).
  - **M1 the card appeared over full-screen apps on notched MacBooks** → fixed. (1) `fullScreenInFront` takes
    each screen's `safeAreaInsets.top` (`LaunchAtLoginPrompt.Screen`) and also accepts a full-width window that
    ends at the bottom edge and starts within inset + 2 pt of the top (the measured `(0, 33, 1470, 923)`).
    (2) The one look-alike, a zoomed window on a notched display with the Dock hidden, is accepted (the card only
    waits); the reviewer's optional "require the app's notch strip too" was **not** added, because that strip is
    only known from one probe app, and if some app's full-screen mode lacks it the card would be back over
    full-screen apps; a false "full screen" only delays a one-time question. (3) New test
    `fullScreenOnANotchedDisplayStartsBelowTheNotch` (the measured windows, plus the near misses). (4) The four
    "per AppKit, not on full-screen Spaces" claims are corrected (`PromptCardController.swift` header and init
    comment, `Packages/OverlayKit/CLAUDE.md`, section 2 above) and the CHANGELOG / `App/MenuBar/CLAUDE.md` /
    root `CLAUDE.md` lines say what keeps it off. (5) Probe re-run: **partly**. A two-process probe that
    evaluates the shipped rule, exactly as the controller does, is committed
    (`docs/sparkle-updates/probes/fullscreen/run.sh`). Run 2026-10-18 ~18:10, the screen was **locked** (owner
    away 4 h; loginwindow frontmost), so macOS never laid out A's full-screen window below the notch (it stayed
    `0,0 1470x956` during the transition) and the notched rectangle couldn't be reproduced live. What it did
    show: the zoomed window with the Dock shown, `(0, 33, 1470, 831)`, → `false` (no false positive); A's
    full-screen windows → `true`; and while locked the rule is `true` (loginwindow's full-screen window), so the
    card also waits on a locked screen. The notched case rests on the reviewer's measurement, encoded in the
    test. **Re-run `run.sh` on an unlocked screen** (NEXT STEPS).
  - **L1 option (b) had no user steps** → the exact steps (remove with −, allow again; or `tccutil reset
    ScreenCapture com.betterscreenshot.mac`) are in "Where the keys live" as paste-ready release-note text and in
    the repo `README.md` ("Screen Recording after an update"), which also tells users and the owner that the
    first build with the new certificate needs Screen Recording allowed once more. The repo README's "no network
    access" line was also false since Sparkle (daily update check) and is corrected. The "check that the app's
    own permission screen detects the stale entry" part needs the real bundle id and a TCC grant → owner
    (NEXT STEPS).
  - **L2 no keyboard path** → done this time (round 2 declined it). While the question is due, the menu-bar menu
    shows **Open at Login…** (`MenuBarController.menuNeedsUpdate`, decision `LaunchAtLoginPrompt.offersMenuItem`,
    tested): a standard `NSAlert` with Return = Open at Login, Escape = No Thanks, and alert follow-ups for "One
    more step" / "Couldn't turn it on.". Round 2's objection (a second UI for the same question) is weaker than
    the gain: the item is hidden for everyone except between the 5th capture and the answer, never draws
    attention, and gives keyboard and Full Keyboard Access users the same question with the same two answers.
    **Not checked live:** the item and the alert in the running app (needs 5 real captures on a copy with its
    own defaults and hotkeys, and clicking Open at Login would register a real login item).
  - **L3 an update relaunch reset the 24 h spacing** → fixed: `mayShowAgain` always needs ≥ 24 h since the
    stored `launchAtLoginPromptLastShownAt` (the in-memory `shownThisLaunch` is gone from `afterCapture` and the
    controller); a clock set back doesn't block it. Test renamed
    `aSeenShowingComesBackOnlyADayLaterEvenAfterARelaunch` (relaunch a minute later and 23 h 59 min later →
    `.tooSoon`, 24 h → `.startWaiting`).
  - **N1** "tested 2026-10-18 (round 2)" → "(`b1eb0ea`, re-run after the round-3 fixes)". **N2** e2e snapshots
    are drawn on the window background in its appearance: all labels readable (committed in
    `docs/sparkle-updates/e2e-ui-snapshots/`). **N3** `CROSS_CERT=1 E2E_UI=1` is refused (exit 2, before
    building). New guard found while re-running: `E2E_UI=1` is refused while the screen is locked (below).
  - Found while checking warnings (not in the review): the `-DSPARKLE_E2E_TEST` build warned "code after
    'return' will never be executed" twice in `AppDelegate.swift` (the e2e early returns); now `#else` /
    `#if !SPARKLE_E2E_TEST`, same behaviour, no warning.
- Verified 2026-10-18 (after round 3, ~18:05–18:20, on this Mac, macOS 26.7.1, Mac15,12; owner away, screen
  locked; no other build running):
  - `nice scripts/test.sh`: exit 0, 26 s; DesignKit 10/10, CaptureKit **151/151** (29 prompt tests),
    OverlayKit 50/50, EditorKit 155/155, RecordingKit 92/92, HistoryKit 41/41, TourKit 119/119.
    `~/Library/Preferences/LaunchAtLoginPromptTests.*.plist`: 145 before, 145 after (the count went from 110 to
    145 at 17:47 today, before this round: that file name is also used by the MacStats and JVoice worktrees'
    tests, not by this repo's).
  - `scripts/build-app.sh debug`: exit 0; touched every changed Swift file and rebuilt: no compiler warnings
    (log checked with colour codes stripped); `codesign --verify --deep --strict` OK; DR `… certificate leaf =
    H"08faa1f9…"`; `nm` finds `askFromMenu` and no `SparkleE2E` symbol. The `-DSPARKLE_E2E_TEST` build: no
    warnings in changed files (the remaining ones are in `RecordingControlsController.swift`,
    `RecordingCoordinator.swift:427` and RecordingKit, all older than this branch).
  - `CROSS_CERT=1 scripts/sparkle-e2e-test.sh`: exit 0, 50 s: cross-certificate PASS, installed copy carries
    NEW's certificate PASS, GOOD PASS, BAD (`Code=4005`) PASS — 4/4; run twice, the second time after the
    `AppDelegate` change (49 s, 4/4).
  - `CROSS_CERT=1 E2E_UI=1 scripts/sparkle-e2e-test.sh`: `error: CROSS_CERT=1 and E2E_UI=1 can't be combined`,
    exit 2, no work dir made.
  - `E2E_UI=1 KEEP=1 scripts/sparkle-e2e-test.sh` (before the lock guard existed), screen locked: exit 1, **5/7**.
    Sparkle chose immediate focus, but the window opened `key 0, app active 0, frontmost app
    com.apple.loginwindow`; the menu read "Update Available (90.1)…" and stayed so after the menu action until
    Install Update was clicked (then "user attention"). So `in focus: the menu doesn't nag` and `the menu action
    leaves nothing pending` FAILED; the other 5 (window shown, user attention, focus not kept, Install and
    Relaunch clicked, relaunched as 101) PASSED. Reading: on a locked screen Sparkle can't get the user's
    attention, so our label correctly keeps naming the update — not an app bug, but the test's in-focus
    expectations don't hold there, hence the new guard: `E2E_UI=1` now refuses a locked screen (`error: the
    screen is locked …`, exit 2, checked). Re-run once more from a temporary copy of the script without that
    guard, only to get the fixed snapshots: same 5/7, snapshots readable (committed). **A full 7/7 UI run on an
    unlocked screen after round 3 is still to do** (NEXT STEPS); the UI code path changed only in the snapshot
    drawing.
  - After every run: no test process, port 8766 free, no `sparkletest` defaults or caches; the real
    `/Applications/BetterScreenshot.app` (pid 4076) kept running. Scratch dirs deleted.
  - `docs/sparkle-updates/probes/fullscreen/run.sh`: see M1 (5) above.
- Verified 2026-10-18 (after round 2):
  - `scripts/test.sh`: all 7 suites pass (DesignKit 10, CaptureKit 149 incl. 27 prompt tests, OverlayKit 50,
    EditorKit 155, RecordingKit 92, HistoryKit 41, TourKit 119); `~/Library/Preferences` still has the same 110
    `LaunchAtLoginPromptTests.*.plist` before and after.
  - `scripts/build-app.sh debug`: exit 0, no warnings in the touched files (re-touched and rebuilt);
    `codesign --verify --deep --strict` OK; `nm` finds no `SparkleE2EUI` symbol in the normal build.
  - `scripts/sparkle-e2e-test.sh`: GOOD PASS + BAD PASS. `CROSS_CERT=1`: all 4 PASS. `E2E_UI=1`: 7/7 PASS.
    Afterwards no test process, nothing on port 8766, no `sparkletest` defaults or caches; the real
    `/Applications/BetterScreenshot.app` (pid 4076) kept running.
  - `scripts/package-release.sh`: `ALLOW_DIRTY=1 ALLOW_NOT_MAIN=1` → refused in 1.1 s before building;
    all three overrides → universal (`x86_64 arm64`), signature OK, DRYRUN outputs only, unusable signature
    and URL in the appcast, no `gh` command; outputs deleted afterwards.
- Verified 2026-10-18 (after round 1):
  - `scripts/test.sh`: all 7 suites pass (DesignKit 10, CaptureKit 143 incl. 20 prompt tests, OverlayKit 50,
    EditorKit 155, RecordingKit 92, HistoryKit 41, TourKit 119); `~/Library/Preferences` has the same 110
    `LaunchAtLoginPromptTests.*.plist` before and after.
  - `scripts/build-app.sh` (debug): exit 0, no warnings in the touched files; `codesign --verify --deep
    --strict` OK; rpaths `/usr/lib/swift`, `@loader_path`, `@executable_path/../Frameworks`; designated
    requirement `identifier "com.betterscreenshot.mac" and certificate leaf = H"08faa1f9…"` (the new cert, see
    B1); `nm` finds no `SparkleE2EUI` symbol in the normal build.
  - `scripts/sparkle-e2e-test.sh`: GOOD PASS + BAD PASS. `E2E_UI=1`: all 6 checks PASS (output in "UI mode").
    Afterwards no test process, server, port 8766 listener, `sparkletest` defaults or caches; the real
    `/Applications/BetterScreenshot.app` (pid 4076) kept running.
  - `scripts/package-release.sh`: with `ALLOW_DIRTY=1 ALLOW_NOT_MAIN=1` → refused before building (certificate
    `08faa1f9…`); with all three overrides → universal (`x86_64 arm64`), signature OK, outputs only in
    `dist/dry-run/` under DRYRUN names, "DRY RUN - not publishable", 0 `gh release create` lines. Nothing was
    published; those outputs were deleted afterwards.
  - Off-screen renders of the card (scratch probe, not committed; window at alpha 0): ask / approval / done
    states over white and black at 2×: same layout as before, outline smooth, collection behaviour
    `canJoinAllSpaces` only.
- **Not tested** (needs the owner or a real release): the card live in the running app (5 real captures, the
  25 s hide, the 3-showing cap and the menu-open wait on screen — a second app instance would fight the real one
  for hotkeys and the native-shortcut settings); the blur/tint on screen (off-screen renders don't draw the
  blur, so contrast relies on the earlier 4.86:1 measurement); a real Login Items `.requiresApproval` path;
  Sparkle's behind-other-windows branch (it can't be forced from a freshly launched copy) and the real
  3.2.0 → 3.2.1 update (checklist above); the Screen Recording re-prompt a cross-certificate update would cause
  (option b; the Sparkle side is tested) and whether the app's setup window detects the stale entry; the
  notched full-screen rule against a live full-screen app on an unlocked screen (unit-tested on the reviewer's
  measured window list; AppKit *does* show the card on full-screen Spaces, so this rule matters); the
  **Open at Login…** menu item and its alerts in the running app; the x86_64 slice on an Intel Mac.

**NEXT STEPS (in this order):**

1. **Owner: decide the signing certificate** (⚠ section above). Until then no release can be cut without
   costing every user their Screen Recording permission. If you choose (b): set `RELEASE_CERT` in
   `scripts/package-release.sh` to `08faa1f906d59fae5a9ccb84d00979030fb26b2b`, rewrite the CHANGELOG 3.2.0
   permission line, paste the user steps from "Where the keys live" into the release notes, and re-run
   `CROSS_CERT=1 scripts/sparkle-e2e-test.sh` right before releasing (4/4 after round 3). If you choose (a),
   delete the "except once" sentences from `README.md` → "Screen Recording after an update".
2. **At the Mac, screen unlocked (any session, ~2 min, don't type meanwhile):**
   `docs/sparkle-updates/probes/fullscreen/run.sh` — expect `fullScreenInFront false` while A is normal or
   zoomed and `true` (front `probe-a`) while it is full screen; if the full-screen window is not `0,33 1470x923`
   or the result is `false`, the M1 rule needs another look. Then `E2E_UI=1 KEEP=1
   scripts/sparkle-e2e-test.sh /tmp/bs-ui` (expect 7/7; snapshots in `/tmp/bs-ui/ui/`; delete the folder after).
   Owner, by hand: put Safari into full screen on the MacBook's own display, take a screenshot, check no card
   appears until full screen is left and the next capture happens (needs a copy that is due — see "To see the
   card on a dev build" — so only when you're happy to change your own BetterScreenshot settings).
3. Owner: OK deleting the plist files earlier test runs leaked into `~/Library/Preferences` (145
   `LaunchAtLoginPromptTests.*` on 2026-10-18 18:07: 110 from this repo's runs before round 1, 35 more at 17:47
   from the MacStats/JVoice worktrees' tests of the same name; plus 119 from MacStats'
   `LaunchAtLoginPromptSessionTests`). They are throwaway test domains, but
   they are files this session didn't create, so they're left for you. Count them with
   `ls ~/Library/Preferences | grep -cE '^LaunchAtLoginPrompt(Session)?Tests\.'`; once you OK it, delete with
   `rm ~/Library/Preferences/LaunchAtLoginPromptTests.*.plist ~/Library/Preferences/LaunchAtLoginPromptSessionTests.*.plist`
   (cfprefsd, the macOS preferences daemon, may keep cached copies until the next login; that is harmless).
4. Owner: review and merge `feat/sparkle-updates` into `main` (`git switch main && git merge --no-ff
   feat/sparkle-updates`), push `main` (it also carries the unpushed ⌘⇧3 commit `c29f6c3`).
5. Cut 3.2.0 with the steps above (skip the bump); install it on this Mac with the one-liner; then run the
   manual checklist with 3.2.1.
6. Optional: `feat/launch-at-login` (see the note in section 2) — merge it with the tour-step text fixed, or drop it.
7. Optional (owner): keep or change Sparkle's focus-at-launch behaviour (L2 bullet above).
