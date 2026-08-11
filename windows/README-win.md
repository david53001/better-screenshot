# BetterScreenshot for Windows

A **free, 100%-local** screenshot + screen-recording tool for Windows — a native port of the macOS
**BetterScreenshot** app (itself a clone of CleanShot X). It lives in the **system tray** (no main window),
captures and annotates screenshots, records the screen to MP4/GIF, does on-device OCR, and keeps a local
capture history. **No cloud, no accounts, no uploads, ever.**

> This is the Windows port (`.NET 9 + WPF`, C#). The macOS original (Swift, under `App/` and `Packages/` at the
> repo root) is the behavioral source of truth. Everything for the port lives under `windows/`.

## What you get

- **Capture** — area (`Ctrl+Shift+4`), full screen (`Ctrl+Shift+6`), a specific window (`Ctrl+Shift+8`), and
  **Capture Text / OCR + QR** (`Ctrl+Shift+7`, copies recognized text to the clipboard).
- **Freeze while selecting** (on by default) — the screen is grabbed the instant you press the shortcut and shown
  as a still while you pick an area or a window, and the capture comes out of that still. Without it, whatever you
  were using loses focus the moment the overlay appears, and apps that react to that — a full-screen game pausing
  to its menu, a video player showing its controls — change what you were trying to capture. Toggle it in
  **Settings → Capture**.
- **Quick Access overlay** — a floating post-capture card (copy / edit / pin / save / close), stacking up to 3,
  drag-to-export.
- **Annotation editor** — arrow, line, rectangle (outline/filled), ellipse, text, counter, blur, pixelate, crop,
  select/move; color + size inspector; undo/redo; sticky last-used style; Copy / Save / Stack / Done. The window
  sizes itself to your capture's aspect ratio, so the image fills the canvas instead of floating in gray margins.
- **Pin to screen** — keep an always-on-top floating image (drag, zoom, multi-pin); pin from the clipboard.
- **Screen recording** (`Ctrl+Shift+5`) — a record strip picks **Full Screen / Window / Area** and **MP4 or GIF**,
  with **system-audio / microphone / camera** toggles. While recording: an optional **countdown**, **click
  highlights**, a **keystroke overlay**, and a circular **camera bubble** (webcam). **Gapless pause/resume**, a live
  tray timer, and a Quick Access card + history entry on finish.
- **Capture history** — a persistent, browsable thumbnail grid (copy / annotate / pin / reveal / delete / clear-all);
  "Restore Recently Closed" brings back the last dismissed card. Auto-prunes by age + count.
- **Settings** — a single scrolling **wall of titled cards** (Capture — including the freeze toggle, Quick Access Overlay, Pin to Screen,
  History, Startup, Save Location, Temporary Files, Recording, Keyboard Shortcuts) with macOS-style toggle switches
  and segmented controls. Changes apply **instantly** and global hotkeys rebind live.
- **Temp copy retention** — copying or dragging a capture writes a throwaway PNG to `%TEMP%\BetterScreenshot-…` so
  other apps can take it as a *file*. **Settings → Temporary Files** has a slider for how long that copy is kept —
  **5 to 30 minutes** (default 5) — so a capture you copied is still pasteable as a file later. Your screenshots are
  never affected: History keeps its own separate copy.

The interface is an all-**monochrome black-and-white** dark theme (matching the sibling **JVoice** app's look):
pure-black surfaces, near-black cards each headed by a glowing dot + label, and **white as the sole accent**.
All UI glyphs and the app icon are **hand-authored vector art** — never screenshots or cropped images.

## Prerequisites

- **Windows 10 build 19041 (2004) or newer** (the app targets `net9.0-windows10.0.19041.0` for WinRT OCR + capture).
- **.NET 9 SDK** — to build/run from source.
- **ffmpeg** — required for **recording only**. Put `ffmpeg.exe` on your `PATH`, or drop it at
  `windows/tools/ffmpeg.exe` (or next to the built app). If ffmpeg is missing, everything except recording still
  works (recording shows a "ffmpeg not found" notice).
- A **webcam** is only needed for the camera-bubble overlay; without one it silently degrades.

## Build, test, run

From the repo root (`C:\...\BetterScreenshot`):

```powershell
# Build (expect: 0 warnings, 0 errors)
dotnet build windows/BetterScreenshot.sln -c Release

# Test (xUnit; ~241 tests — pure logic + hardware-gated integration)
dotnet test windows/tests/BetterScreenshot.Tests -c Release

# Run — launches to the system tray (a windowless agent; look for the camera icon)
windows/src/BetterScreenshot.App/bin/Release/net9.0-windows10.0.19041.0/BetterScreenshot.App.exe
# ...or:  dotnet run --project windows/src/BetterScreenshot.App
```

Left-click (or right-click) the tray icon for the full menu; the first run shows a one-time welcome + hotkey
cheat-sheet.

### Get a standalone, double-clickable app

To produce a **self-contained** build (bundles the .NET runtime — runs on any Win10 19041+ box with no .NET
install) plus a Desktop shortcut, run:

```powershell
pwsh windows/scripts/publish-app.ps1
```

This publishes `windows/dist/BetterScreenshot/BetterScreenshot.App.exe` (~195 MB folder) and drops a
**BetterScreenshot** shortcut on your Desktop — double-click it to launch. The app is a single-instance tray
agent: launching it again just focuses the one already running. (The `dist/` folder is git-ignored; regenerate it
any time with the script.)

> **Updating the standalone app after code changes.** `dist/` is a **manual publish snapshot** — a plain
> `dotnet build` (or a commit) does **not** update it, and the running tray agent keeps using the old exe until
> you republish **and relaunch**. So after any change you want to see at runtime: **quit the running instance**
> (right-click the tray icon → Quit, or `Stop-Process -Name BetterScreenshot.App`), rerun
> `pwsh windows/scripts/publish-app.ps1`, then launch it again. If a fix seems "not applied", check the `dist/`
> exe's timestamp against your latest change before assuming a regression.

## Default hotkeys

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+4` | Capture area |
| `Ctrl+Shift+5` | Record screen (toggles the record strip / stops) |
| `Ctrl+Shift+6` | Capture full screen |
| `Ctrl+Shift+7` | Capture text (OCR / QR) → clipboard |
| `Ctrl+Shift+8` | Capture window |

Rebind any of them in **Settings → Shortcuts**. (Pause/Resume Recording has no default hotkey — use the tray menu,
or bind one in Settings.)

## Where things are saved

- Screenshots → `Pictures\Screenshots` · Recordings → `Videos\` (both configurable in Settings).
- Settings + history → `%APPDATA%\BetterScreenshot\` (`settings.json`, `History\`).

## Differences from the macOS app

- **Recording engine is ffmpeg** (not AVFoundation/ScreenCaptureKit): video via `gdigrab`, H.264/MP4; system audio +
  mic as separate AAC tracks via `dshow`; GIF via a palette filtergraph. **Gapless pause/resume** is implemented as
  *segment-per-active-span + concat* (paused time is never captured) rather than PTS-retiming.
- **System-audio capture** needs a loopback-capable input (e.g. "Stereo Mix" or a virtual cable). If none is present,
  recording gracefully falls back to video-only.
- **macOS permission flows are dropped** — Windows global hotkeys (`RegisterHotKey`) and low-level input hooks
  (`WH_MOUSE_LL`/`WH_KEYBOARD_LL`) need no special permission; the camera uses Windows Privacy settings.
- Coordinates are **top-left origin** throughout (the mac app flipped between Cocoa bottom-left and image top-left).
- No taskbar window — it's a tray agent (the mac `LSUIElement` menu-bar equivalent).

## 100% local guarantee

There is **no networking anywhere** in the product code — no `HttpClient`/`WebClient`/`Socket`/`WebRequest`, no
update checks, no telemetry, no share links. Captures, recordings, history, and settings never leave your machine.

## Architecture (short)

Layered .NET solution (`windows/BetterScreenshot.sln`):

- Pure-logic libraries (`net9.0`, unit-tested 1:1 from the mac `TestKit` suites): `Core`, `Capture`, `Editor`,
  `History`, `Recording`.
- `Platform` (`net9.0-windows…`) — Win32/WinRT/ffmpeg: screen enumeration + DPI, GDI capture, window picking,
  clipboard/encode, `Windows.Media.Ocr` + ZXing QR, global hotkeys + input hooks, ffmpeg runner, dshow enumeration.
- `App` (WPF WinExe tray agent) — tray/menu, overlays, editor, history window, and the capture/recording
  coordinators.

Design + plan + per-module fidelity specs live under `windows/docs/` (`SPEC.md`, `PLAN.md`, `port-reference/`); the
running ledger is `PROGRESS.md`. The UI is documented in **`docs/UI-JVOICE-REVAMP.md`** (the current monochrome
theme; the earlier `UI-REVAMP-SPEC.md`/`UI-REVAMP-PLAN.md` describe the superseded blue-accent theme).
