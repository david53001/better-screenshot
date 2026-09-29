# Native look (MacStats design language) — progress and handoff (2026-09-29)

**Branch:** `feat/native-look` (from `main` at `2affdef`, v3.0.0). Not merged, not pushed, not tagged.
**Spec:** `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/MacStats/docs/design-language/betterscreenshot-native-redesign.md`
(language: `.../MacStats/docs/design-language/README.md`). Owner request 2026-09-29: make every part of
the UI (Settings, the pills, everything) look like the native MacStats UI.

## Done (all six phases of the spec)
1. **`Packages/DesignKit`** (new, no dependencies; OverlayKit, RecordingKit, EditorKit, TourKit and the app
   depend on it; `scripts/test.sh` runs `DesignKitTests`): `Design` tokens, `HUDSurfaceView`,
   `continuousRoundedRect` + `NSBezierPath(continuousRoundedRect:radius:)`, `CALayer.setContinuousCorners`,
   `CardBackground`, `CardButtonStyle`, `SubtleButtonStyle`, `WindowMaterial`/`WindowMaterialView`.
2. **Settings** (`App/Settings/`): system appearance, `.sidebar` material under a transparent title bar,
   `SettingsCard`, native switches/segmented/sliders/menus/bordered buttons, SF `info.circle` tips,
   `NSAlert` for Clear History. `SettingsTheme`, `DarkSection`, `MonoSwitch`, `PillButtons`, `MonoControls`
   deleted. Same cards, order, instant-apply bindings and tour anchors.
3. **One HUD recipe:** `HUDStyle` (OverlayKit) and `RecordingHUDStyle` (RecordingKit) deleted; every floating
   surface uses `HUDSurfaceView` — toast, size chip, window-picker title chip (now a view, not drawn), Quick
   Access badge, pin close button, record strip, recording pill + hint, countdown, keystroke overlay.
4. **Editor & trim:** stay dark; backdrops are `.underWindowBackground` material instead of flat grey; tool
   pill, inspector and trim card are `HUDSurfaceView`; inspector type uses text styles + semantic colours.
5. **Quick Access:** continuous corners only (scrim/sample/button contrast logic untouched).
6. **Tours, History:** continuous corners (tour red kept).

## Verified
- `swift build` and `scripts/test.sh` green (DesignKit 3, CaptureKit 120, OverlayKit 50, EditorKit 155,
  RecordingKit 92, HistoryKit 41, TourKit 117).
- Screenshots of Settings (light + dark), toast, countdown, record strip and editor from a throwaway probe
  (windows parked just above the desktop, behind everything; not in the repo).
- Contrast (macOS 26, HUD over an opaque white page): glass alone white text 4.52:1, glass + 40 % tint 8.62:1
  → the tint stays.

## Not verified / follow-ups
- The macOS 14/15 fallback path (blur + tint) wasn't seen on a real 14/15 machine; it is the pre-existing
  recipe plus continuous corners and a 0.5 pt hairline. CI (`macos-15`) wasn't run; glass code is behind
  `#if compiler(>=6.2)` + `if #available(macOS 26, *)`.
- Not clicked through by a human. Suggested pass: Settings in light and dark (every control writes and
  persists), a recording (strip, pill, countdown, keystrokes), the editor and the trim window.
- History, onboarding and the menu were already native: only corner curves changed.
- The Windows port (`windows-port` branch) is not updated; instructions in
  `docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 9.
