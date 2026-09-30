# Opacity setting + "a touch more transparent" — progress (2026-09-30)

**Branch:** `feat/opacity-setting` (git worktree at `BetterScreenshot/.claude/worktrees/opacity`, based on
`main` = v3.1.0). Committed on the branch; **not merged, not released, no version bump, no CHANGELOG entry**
(the CHANGELOG is written per release, there is no "Unreleased" section — add the entry when this ships).

**Owner request (2026-09-30):** the UI should be a tiny bit more transparent, more like MacStats (the owner's
menu-bar system monitor, the reference look), and each app (MacStats, JVoice, BetterScreenshot) gets a small
setting to change the UI's opacity, with a default to go back to.
**Shared spec:** `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/MacStats/.claude/worktrees/opacity/docs/design-language/opacity-setting.md`
(§1 default look, §2 the setting — identical in all three apps).

## Terms
- **Opacity value:** a `Double` 0…1. 0 = as see-through as each surface can safely go, 0.5 = the designed
  default, 1 = solid.
- **HUD:** a small dark floating panel over other apps (toast, record strip, recording pill, countdown, size
  chip, window-picker chip, keystroke overlay, pin close button, Quick Access badge). All are
  `HUDSurfaceView` in `Packages/DesignKit/Sources/DesignKit/HUDSurface.swift`.
- **Docked panel:** a `HUDSurfaceView` that only ever sits on the editor's / video editor's own dark window
  (editor tool pill, editor inspector, trim card) — `placement: .docked`.
- **Contrast N:1:** WCAG 2.x contrast ratio. Floors from the spec: at the default, primary text ≥ 4.5:1 and
  secondary ≥ 3:1 over the worst realistic background; at 0, primary never below 3:1 over a white page.

## What was built
- **`Packages/DesignKit/Sources/DesignKit/UIOpacity.swift`** (new): `UIOpacity.shared` (`ObservableObject`,
  `value`, `defaultValue = 0.5`), `HUDPlacement` (`.floating` / `.docked`), `HUDFill`, and the pure mappings
  in `OpacityCurve` — piecewise-linear through each surface's (0, 0.5, 1) points, input clamped to 0…1:

  | Surface | 0 (Transparent) | 0.5 (default) | 1 (Opaque) | v3.1.0 |
  |---|---|---|---|---|
  | Floating HUD black tint alpha | **0.22 (clamp)** | 0.42 | 1.0, colour white 0.13 (dark grey) | 0.50 |
  | Docked panel blur alpha / tint | 0.5 / 0 | 0.85 / 0 | 1 / solid dark grey | 1 / 0 |
  | Window: `windowBackgroundColor` layer over `.popover` material | **0.15 (clamp)** | 0.52 | 1.0 (solid) | `.sidebar` / `.underWindowBackground` material, no layer |
  | Settings card `Color.primary` fill | 0.03 | 0.04 | 0.05 | 0.04 |

  Hairlines stay 0.5 pt (cards `Color.primary` 0.08, HUDs white 0.10).
- **`HUDSurfaceView`**: `tint:` parameter replaced by `placement:`; subscribes to `UIOpacity.shared.$value`
  and re-applies live. Docked call sites: `EditorWindowController.buildToolbar`, `EditorInspectorView.init`,
  `TrimWindowController.buildCard`.
- **`WindowMaterial`**: one recipe for every window (`make()` / `install(_:in:)`, the material parameter is
  gone) — `WindowBackdropView` (`.popover`, behind-window, follows the window's active state) with a
  `SolidFillView` (window-background colour at the mapped alpha, re-resolved on light/dark change, never takes
  clicks) as its bottom-most subview. Used by Settings, the editor, the video editor, and now **History**
  (`App/History/HistoryWindowController.swift` hosts `HistoryView` in an `NSHostingView` on the material, like
  Settings; it was an opaque window before).
- **`CardBackground`**: fill follows the setting unless a `fill` is passed.
- **Setting:** `CaptureSettings.uiOpacity` (CaptureKit; dictionary key `uiOpacity` inside the `captureSettings`
  UserDefaults dictionary; default 0.5; parsing clamps to 0…1 and ignores junk/NaN). `AppDelegate` pushes it
  into `UIOpacity.shared` (Combine sink on `settings.$settings`, first thing at launch).
- **Settings UI:** an **APPEARANCE** card at the bottom of column C (`SettingsView.appearanceCard`): "Opacity"
  label + ⓘ (`SettingsHelp.opacity`), a small bordered **Default** button (disabled at 0.5), a native
  continuous `Slider` with `.caption` `.secondary` "Transparent" / "Opaque" end labels, and the help line
  "How much of what's behind the app shows through its windows and panels." Instant-apply through the
  existing `bind(\.uiOpacity)` (writes the store and persists). Tour anchors unchanged (`settings.cards` still
  wraps the three columns).
- **Tests:** `DesignKitTests` 3 → 8 (curve shape + clamping, floating clamp/solid/monotonic, docked, windows +
  cards ≤ 0.05, live apply to a HUD and a window backdrop); `CaptureKitTests` +1 (`uiOpacity` default,
  round-trip, clamp, junk).

## Measurements (macOS 26.6.2, 14″ MacBook, Swift 6.2.3)
Method as in `docs/reviews/2026-09-29-native-look-review.md`: a throwaway probe (not in the repo) parks the
real windows just above the desktop over its own full-screen backdrop, captures them with
`CGWindowListCreateImage`, and takes the median grey of the surface; contrast is WCAG 2.x of the text colour
composited over that grey. Probe windows are never key, so the probe forced the window material's state to
`.active`.

**HUD tint sweep over an opaque white page** (bare `HUDSurfaceView`, same at 0.5 / 2 / 5 s): tint 0 → rgb 177
(white text 2.13:1) · 0.20 → 3.02:1 · 0.25 → 3.33:1 · 0.30 → 3.74:1 (80 %-white secondary 3.00:1) · 0.35 →
4.16:1 · 0.40 → 4.66:1 (3.64:1) · 0.45 → 5.24:1 · 0.50 → 5.94:1 (4.49:1).

**Real surfaces over white** (toast, record strip and recording pill measure identically; pill also at 0.5 s
and 2 s):

| Opacity | HUD bg | HUD primary (white) | HUD secondary (80 % white) | Editor inspector primary / secondary (55 %) |
|---|---|---|---|---|
| 0 | rgb 144.5 | **3.17:1** | 2.61:1 | 5.01 / 2.70 |
| 0.5 | rgb 113.2 | **4.86:1** | **3.78:1** | 8.47 / 3.86 |
| 1 | rgb 44 | 13.96:1 | 9.49:1 | 13.96 / 5.34 |

**Settings card background** (label 85 %, secondary label 55 % white in dark; 85 % / 50 % black in light;
dark mode measured over a white page, light mode over a black page — the worst page for each):

| | dark over white: primary / secondary | light over black: primary / secondary |
|---|---|---|
| v3.1.0 (`.sidebar`) | 4.50 / 2.87 | 10.19 / 3.56 |
| 0 | 3.25 / 2.26 | 7.62 / 3.22 |
| 0.5 | **4.90 / 3.06** | 10.41 / 3.59 |
| 1 | 9.35 / 4.93 | 14.23 / 3.92 |

See-through share (grey over white − grey over black, ÷ 255) of the Settings window: v3.1.0 dark 0.18 /
light 0.08 → default dark 0.20 / light 0.13 (and darker over dark content: rgb 49 vs 58, closer to MacStats'
neutral panel). Material survey (dark / light see-through): `.sidebar` 0.20 / 0.08, `.menu` 0.31 / 0.19,
`.popover` 0.40 / 0.30, `.hudWindow` 0.59 / 0.42.

Screenshots (not in the repo): `/private/tmp/claude-501/-Users-davidghermansteinberg/75e0c0dc-9b20-4d54-8e2a-8e24a75c43e0/scratchpad/betterscreenshot/`
— `settings-{light,dark}-{0.0,0.5,1.0}.png` (busy page) and `…-worstpage.png`,
`hud-{toast,strip,pill}-{0.0,0.5,1.0}-{white,busy}.png`, `editor-{0.0,0.5,1.0}-{white,busy}.png`,
`contrast.txt`; the probe source is in `probe/` there (`ZZOpacityProbe.swift` goes in `App/Lifecycle/`, plus
the one-line hook in `main-hook.diff`; run `BS_OPACITY_PROBE=<dir> .build/debug/BetterScreenshot`, add
`BS_SWEEP=1` for the Settings overlay sweep).

## Verified
- `swift build` and `scripts/test.sh` green: DesignKit 8, CaptureKit 121, OverlayKit 50, EditorKit 155,
  RecordingKit 92, HistoryKit 41, TourKit 117.
- Live apply: the `surfacesApplyTheSettingLive` test, and the probe changing `UIOpacity.shared.value` on
  open windows.

## Not verified / follow-ups
- Not clicked through in the built app by a human: drag the slider with Settings open and a recording
  running, check persistence across relaunch, check Default.
- Not rendered on macOS 14/15 (the blur may differ there; the review noted a lighter blur on 14/15).
- Not checked with Accessibility → Reduce transparency on (the materials go solid by themselves; our layers
  only add on top, so it should stay solid).
- History window: not screenshotted (it reads the owner's real history); code-only. It now uses
  `NSHostingView` instead of `NSHostingController` — check it still opens at its remembered size.
- Trim window: same recipe as the editor, not screenshotted.
- Quick Access card and tour tags don't use these surfaces and are unchanged (Quick Access's scrim logic must
  not be touched). Its recording badge is a floating `HUDSurfaceView` and follows the setting.
- Windows port (`windows-port` branch) not updated: add the same slider + mapping to
  `docs/MAC-TO-WINDOWS-PARITY-v3.md` when this ships.
