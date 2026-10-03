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

Needs Windows 10 version 2004 or newer (64-bit). Paste this into PowerShell:

```powershell
irm https://raw.githubusercontent.com/david53001/better-screenshot/main/scripts/install.ps1 | iex
```

The same command installs and updates. It puts the latest release in your user folder (no admin needed), sets up ffmpeg for screen recording if your PC doesn't have it, and keeps your settings and history. You can read the script first: [`scripts/install.ps1`](scripts/install.ps1).

Or download [`BetterScreenshot-win-x64.zip`](https://github.com/david53001/better-screenshot/releases/download/windows-v1.0.0/BetterScreenshot-win-x64.zip), unzip it and run `BetterScreenshot.App.exe`. Screen recording then also needs [ffmpeg](https://ffmpeg.org/download.html) on your PATH.

## Uninstall

On macOS, paste this into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/david53001/better-screenshot/main/scripts/uninstall.sh | bash
```

On Windows, paste this into PowerShell:

```powershell
irm https://raw.githubusercontent.com/david53001/better-screenshot/main/scripts/uninstall.ps1 | iex
```

Each quits BetterScreenshot and removes the app, its settings, capture history and caches; on macOS also its Screen Recording permission, on Windows also its shortcuts, launch at login and the ffmpeg it set up. Screenshots and recordings you saved are kept. You can read the scripts first: [`scripts/uninstall.sh`](scripts/uninstall.sh), [`scripts/uninstall.ps1`](scripts/uninstall.ps1).

## Unverified developer

The app is not signed with a paid developer certificate. The install commands handle this for you. If you downloaded it by hand:

- **macOS** blocks the first launch: open **System Settings > Privacy & Security** and click **Open Anyway**.
- **Windows** may show "Windows protected your PC": click **More info > Run anyway**.

## Requirements

- macOS 14 (Sonoma) or newer, Apple Silicon or Intel.
- Windows 10 version 2004 (build 19041) or newer. Screen recording on Windows uses [ffmpeg](https://ffmpeg.org/download.html), which the install command sets up for you.

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

## Build from source (Windows)

Needs [Git](https://git-scm.com/downloads/win) and the [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0). The Windows app lives on the `windows-port` branch:

```powershell
git clone -b windows-port https://github.com/david53001/better-screenshot.git
cd better-screenshot
pwsh windows/scripts/publish-app.ps1   # builds windows/dist/BetterScreenshot and adds a Desktop shortcut
```

More detail: [Windows guide](https://github.com/david53001/better-screenshot/blob/windows-port/windows/README-win.md).

## License

PolyForm Strict 1.0.0: you may view and use it, but not redistribute, modify or sell it. See [LICENSE](LICENSE).
