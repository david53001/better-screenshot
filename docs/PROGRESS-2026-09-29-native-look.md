# Native look (MacStats design language) — progress and handoff (2026-09-29)

**Branch:** `feat/native-look` (from `main` at `2affdef`, v3.0.0). Not merged, not pushed, not tagged.
**Spec:** `/Users/davidghermansteinberg/Desktop/Home/Projects/Code/MacStats/docs/design-language/betterscreenshot-native-redesign.md`
(language: `.../MacStats/docs/design-language/README.md`). Owner request 2026-09-29: make every part of
the UI (Settings, the pills, everything) look like the native MacStats UI.

## Done (all six phases of the spec)
1. **`Packages/DesignKit`** (new, no dependencies; OverlayKit, RecordingKit, EditorKit, TourKit and the app
   depend on it; `scripts/test.sh` runs `DesignKitTests`): `Design` tokens, `HUDSurfaceView`,
   `continuousRoundedRect` + `NSBezierPath(continuousRoundedRect:radius:)`, `CALayer.setContinuousCorners`,
   `CardBackground`, `WindowMaterial`.
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

## Review + fixes (2026-09-29)
Independent review `docs/reviews/2026-09-29-native-look-review.md` (screenshots in
`docs/reviews/2026-09-29-native-look/`, left uncommitted as the review convention): **6/10**. Fixed after it:
- **H1 (High):** Liquid Glass adapts to what's behind it — the recording pill turned light over white (2.4:1).
  `HUDSurfaceView` is now the `.hudWindow` blur on every macOS version with a **50 %** tint; the real pill, strip
  and toast measure 6.0–6.8:1 (white) and ≥ 5.0:1 (secondary) over white at 0.5/2/5 s. Glass variants tried and
  rejected: tint in `tintColor`, content in `contentView`, `.clear` style (all ≤ 4.05:1).
- **S1 (High):** Settings content ran under the traffic lights when scrolled → standard title bar (it blurs
  what scrolls under it).
- **H2:** secondary HUD text 60 % → 80 % white. **S2:** popups are an `NSPopUpButton` wrapper that fills the
  card width. **E1/T3:** editor tool pill, inspector and trim card use `tint: 0` (were black slabs).
- Lows: recorder wells tinted with a hairline (S3); no duplicate in-content headline (S4); Clear History
  `role: .destructive` (S5); tool highlight concentric r7 (E2); hairline tool separators (E3); ruler labels
  caption2, "Paused" subheadline (T1/H4 partly); History cells r12 around r6 thumbnails, hover fill, semantic
  placeholder (Y1–Y3); unused DesignKit API removed (K3).
- Left as is: tour-tag fonts/1 pt button border on red (G1/G2), trim window fixed fonts (T2), strip/pill
  fixed fonts other than "Paused" (H4), Quick Access badge font and card hairline (Q1/Q2), editor bottom bar
  without a prominent button (E5), inspector's custom checkbox (E4, it exists because the system unchecked
  box is invisible on the HUD).

## Verified
- `swift build` and `scripts/test.sh` green (DesignKit 3, CaptureKit 120, OverlayKit 50, EditorKit 155,
  RecordingKit 92, HistoryKit 41, TourKit 117).
- Screenshots of Settings (light + dark), toast, countdown, record strip and editor from a throwaway probe
  (windows parked just above the desktop, behind everything; not in the repo).
- Contrast: see "Review + fixes" (real HUDs over white, over time).

## Not verified / follow-ups
- Not rendered on a real macOS 14/15 machine (the blur there measured rgb 129 alone in review C1, so the 50 %
  tint gives more margin than on 26). CI (`macos-15`) wasn't run; no macOS 26-only API is used any more.
- Not clicked through by a human. Suggested pass: Settings in light and dark (every control writes and
  persists), a recording (strip, pill, countdown, keystrokes), the editor and the trim window.
- History, onboarding and the menu were already native: only corner curves changed.
- The Windows port (`windows-port` branch) is not updated; instructions in
  `docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 9.
