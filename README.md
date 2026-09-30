# BetterScreenshot

A free screenshot, recording and annotation tool for macOS and Windows. Everything stays on your computer: no cloud, no accounts, no network access.

## Install and update

### macOS

Paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/david53001/better-screenshot/main/scripts/install.sh | bash
```

The same command installs and updates. It puts the latest release in `/Applications` and keeps your settings, history and Screen Recording permission.

Or download `BetterScreenshot.app.zip` from the [latest release](https://github.com/david53001/better-screenshot/releases/latest), unzip it and drag the app into `/Applications`.

### Windows

There is no download for Windows yet; you build it once on your PC. Install [Git](https://git-scm.com/downloads/win), the [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0) and [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows), then run in PowerShell:

```powershell
git clone -b windows-port https://github.com/david53001/better-screenshot.git
cd better-screenshot
pwsh windows/scripts/publish-app.ps1
```

This builds the app and puts a BetterScreenshot shortcut on your Desktop.

To update: quit BetterScreenshot (right-click the tray icon, then Quit), run `git pull` in the same folder, and run the last command again. Your settings and history are kept. More detail: [Windows guide](https://github.com/david53001/better-screenshot/blob/windows-port/windows/README-win.md).

## Unverified developer (macOS)

The app is not notarized (checked and approved) by Apple. The Terminal command handles this for you. If you downloaded it by hand, macOS blocks the first launch: open **System Settings > Privacy & Security** and click **Open Anyway**.

## Requirements

- macOS 14 (Sonoma) or newer, Apple Silicon or Intel.
- Windows 10 version 2004 (build 19041) or newer. Screen recording on Windows also needs [ffmpeg](https://ffmpeg.org/download.html) on your PATH.

## Features

- Capture an area, a window or the full screen.
- Capture Text: copy text or a QR code from anywhere on screen.
- Record the screen to MP4 or GIF, with audio, microphone and camera.
- Annotation editor: arrows, shapes, text, numbers, highlight, blur and crop.
- Quick Access card after each capture: copy, save or edit.
- Pin a capture on top of other windows.
- History of your recent captures.

## Build from source (macOS)

Needs the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/david53001/better-screenshot.git
cd better-screenshot
./scripts/build-app.sh    # creates dist/BetterScreenshot.app
./scripts/test.sh         # runs the tests
```

## License

PolyForm Strict 1.0.0: you may view and use it, but not redistribute, modify or sell it. See [LICENSE](LICENSE).
