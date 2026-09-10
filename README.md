# BetterScreenshot

A free, open-source screenshot and annotation tool for macOS, living in your menu bar. Inspired by CleanShot X — built to be **100% local**: no cloud, no accounts, no telemetry, no network access at all.

## Features

- **Capture** an area (`⌘⇧4`), a window (`⌘⇧8`), or the full screen (`⌘⇧6`) — the native `⌘⇧4` is disabled while the app runs and restored on quit
- **Capture Text (`⌘⇧7`)** — on-device OCR + QR decode straight to the clipboard
- **Record (`⌘⇧5`)** the full screen, a selected area, or a single window to MP4 or GIF — with system audio, microphone, a camera bubble, click highlights, and a keystroke overlay; an optional 3/5/10-second countdown before recording; and pause/resume that leaves no gap in the saved file
- **Quick Access overlay** after capture: drag the thumbnail anywhere, copy, save, or jump into the editor; the last 3 captures stack at the screen corner. Its buttons measure the pixels behind them and pick a glyph tone plus scrim strength that guarantees a WCAG 4.5:1 contrast ratio, so they stay readable over any screenshot
- **Capture History** — every capture and recording is remembered locally (capped at the 100 most recent, with no time limit); browse, copy, annotate, pin, delete, or clear all from the History window, and restore an accidentally closed thumbnail with Restore Recently Closed
- **Pin to screen** — float a capture always-on-top (drag, resize, multi-pin), from the History window's Pin action or the menu bar's **Pin from Clipboard**
- **Annotation editor**: arrow, line, rectangle, ellipse, text, numbered counters, blur & pixelate redaction, crop
  - Undo/redo (`⌘Z` / `⌘⇧Z` / `⌘Y`), drag to select multiple objects, resize handles, bring-to-front / send-to-back
- **One-button setup** — Screen Recording is the only permission the app needs; the welcome window handles the whole flow and restarts the app for you
- Saves PNG or JPG to a folder you choose; copy lands on the clipboard

**Requires macOS 14 (Sonoma) or later.**

## Windows

A native **Windows port** (.NET 9 + WPF, C#) lives under [`windows/`](windows/) on the `windows-port` branch. It keeps the same **100%-local** philosophy — a tray agent (no main window) with area/window/full-screen capture, the annotation editor, screen recording (via ffmpeg), on-device OCR + QR, pin-to-screen, and capture history. See **[`windows/README-win.md`](windows/README-win.md)** for prerequisites, build/run, and how it differs from the macOS app.

## Install

Works on **any Mac running macOS 14 (Sonoma) or newer — Apple Silicon and Intel** (the release is a universal binary).

**Quickest — one line in Terminal:**

```sh
curl -fsSL https://raw.githubusercontent.com/david53001/BetterScreenshot/main/scripts/install.sh | bash
```

That downloads the latest release, puts `BetterScreenshot.app` in `/Applications`, clears the quarantine flag, and launches it. (Read it first if you like: [`scripts/install.sh`](scripts/install.sh).)

**Manually:**

1. Download `BetterScreenshot.app.zip` from the [latest release](../../releases/latest)
2. Unzip and drag `BetterScreenshot.app` into `/Applications`
3. Open it. macOS will refuse the first time — the app is self-signed, not notarized (this project doesn't use a paid Apple Developer account). To let it through, either:
   - Terminal: `xattr -dr com.apple.quarantine /Applications/BetterScreenshot.app`, then open it normally, or
   - Try to open it once, then go to **System Settings → Privacy & Security**, scroll down to the message about BetterScreenshot, and click **Open Anyway**. (On macOS 15 and newer this is the only click-through path — right-click → Open no longer works for unnotarized apps.)
4. Click **Enable Screen Recording** in the welcome window, flip the switch in System Settings, and the app restarts itself. Done — look for the camera icon in your menu bar.

> Your first save may also trigger a standard macOS prompt to allow access to the destination folder — click Allow once.

## Update

The app has no built-in updater (it never touches the network). To move to the newest release, run the same one-liner again:

```sh
curl -fsSL https://raw.githubusercontent.com/david53001/BetterScreenshot/main/scripts/install.sh | bash
```

It quits the running copy, replaces `/Applications/BetterScreenshot.app` with the [latest release](../../releases/latest), and relaunches it. Nothing else is touched, so everything carries over:

- **Settings and keyboard shortcuts** — stored in `~/Library/Preferences/com.betterscreenshot.mac.plist`
- **Capture history** — stored in `~/Library/Application Support/BetterScreenshot/History/`
- **Your screenshots and recordings** — in whatever folder you chose in Settings
- **Screen Recording permission** — macOS ties it to the app's bundle id and signing certificate, and every release is signed with the same one, so it stays granted and the app does not ask again

If you installed manually, repeat the manual steps instead; dragging the new app over the old one preserves the same things.

To see what changed between versions, read the [release notes](../../releases) or [`CHANGELOG.md`](CHANGELOG.md). To check which version you have, select `BetterScreenshot.app` in `/Applications` and press `⌘I` (Get Info).

## Build from source

Only the Xcode Command Line Tools are needed (no full Xcode):

```sh
xcode-select --install     # if you don't have the CLT yet
git clone https://github.com/david53001/BetterScreenshot.git
cd BetterScreenshot
./scripts/build-app.sh     # → dist/BetterScreenshot.app
```

Optional: run `./scripts/setup-signing.sh` once before building to create a stable local signing identity, so macOS permissions persist across rebuilds (otherwise the build is ad-hoc signed).

Run the tests:

```sh
./scripts/test.sh    # all five suites: CaptureKit, OverlayKit, EditorKit, RecordingKit, HistoryKit
```

The design docs and implementation plans the app was built from live in [`docs/`](docs/); release history is in [`CHANGELOG.md`](CHANGELOG.md).

## Privacy

Everything happens on your Mac. BetterScreenshot makes no network connections of any kind — no uploads, no share links, no accounts, no analytics.

## License

[MIT](LICENSE)
