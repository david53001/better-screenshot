# BetterScreenshot — Windows → macOS Parity Backport

> **Read me first.** This is a **self-contained handoff** for a fresh Claude Code session running on the
> **macOS** side of BetterScreenshot. It assumes **zero prior context**. Everything you need to bring the
> macOS app up to visual + behavioral parity with the Windows port is inline below — you should not need to
> read the Windows source to execute it (paths are cited only if you want to double-check).

---

## 0. Context — what this is and why

**BetterScreenshot** is a free, 100%-local screenshot + screen-recording tool (a CleanShot X clone).
Two implementations live in one git repo:

- **macOS app** — Swift, SwiftUI + AppKit. Source at the repo **root**: `App/` (the menu-bar agent target) and
  `Packages/` (local Swift packages: `CaptureKit`, `OverlayKit`, `EditorKit`, `HistoryKit`). Branch: `main`.
- **Windows port** — .NET 9 + WPF, C#, under `windows/`. Branch: `windows-port`.

Historically the **macOS app was the source of truth** and the Windows port followed it. That has now
**reversed for three areas**: the Windows port has moved ahead with a new settings UI, a redesigned
post-capture card, and a batch of bug/UX fixes. **The owner wants the macOS app to look and behave
identically to the current Windows app** in those areas.

This document has three parts, matching the owner's three asks:

1. **Part 1 — Settings UI: the "JVoice" monochrome revamp.** The Windows settings window was rebuilt as a
   pure-black, single-scroll, three-column masonry of titled cards with macOS-style toggle switches,
   segmented controls, and per-setting info tooltips. macOS still has the old 3-tab SwiftUI `TabView`.
2. **Part 2 — Quick Access card: full-bleed image with overlaid, auto-contrasting buttons.** After a
   capture, the floating card is now the screenshot itself (edge-to-edge, rounded), with action buttons
   floating on top of the image; the glyphs flip black/white to stay legible against whatever is behind
   them. macOS still shows a small letterboxed thumbnail with a separate button strip below it.
3. **Part 3 — Bug fixes & behavior changes to backport.** A categorized list from the Windows ledger, split
   into "port these" vs "verify on macOS" vs "Windows-only, ignore."

**Definition of done / "identical":** a side-by-side screenshot of the macOS Settings window and the macOS
Quick Access card is visually indistinguishable (modulo native window chrome) from the Windows ones — same
black theme, same cards + glowing-dot headers, same mono toggles/segments, same full-bleed auto-contrast
card — and the Part 3 behavior fixes are present. All exact colors and dimensions are given below; match
them to the hex/point value.

**macOS invariants you must not break** (from the repo's `CLAUDE.md` files):
- Annotations live in **base-image pixel space, top-left origin**; the editor renderer draws into a
  **flipped `NSGraphicsContext`** so text is right-side-up. Don't change the flip.
- The app is a **non-sandboxed menu-bar agent** (`LSUIElement`), min target **macOS 14 (Sonoma)**,
  **no cloud / no network** — ever.
- Settings persist via `App/Settings/SettingsStore.swift` (`UserDefaults`); capture/recording config lives in
  `Packages/CaptureKit/Sources/CaptureKit/CaptureSettings.swift`. macOS is **already instant-apply** (every
  setter persists immediately — keep that).

**How to work (owner's standing rules):** work on a branch (not `main`); commit in logical chunks; don't push
or open PRs. Verify with real builds/tests before claiming done: build the app, run `scripts/test.sh` (the
TestKit suites), and manually check the UI against the specs here. Where something is ambiguous, pick the
sensible option, **log the assumption**, and keep going.

**Suggested order:** Part 3 "verify" fixes are cheap and independent — knock them out first or last as you
like. The headline work is Part 1 (Settings) and Part 2 (Quick Access card); they're independent of each
other, so either order works. Part 1 and Part 2 both add an **auto-dismiss slider** — build the shared
`OverlayDismissScale` logic once (Part 2 §2.6) and reuse it in the Settings UI (Part 1).

---

# Part 1 — Settings UI: the JVoice monochrome revamp

> **Superseded on macOS (2026-09-29, branch `feat/native-look`):** the owner replaced this pure-black
> "JVoice" Settings look with the native MacStats design language — translucent material, system
> light/dark, system accent, tinted hairline cards without dots, native controls. What Part 1 describes
> below is the *previous* look. Current look and the Windows instructions: `docs/MAC-TO-WINDOWS-PARITY-v3.md`
> Part 9.

## 1.1 The target, in one paragraph

The Windows settings window is a single WPF `Window` skinned entirely from a central theme file. It is a
**pure-black (#000000), monochrome, single-scroll, three-column masonry of titled "cards."** Each card is a
rounded near-black panel (#0E0E0E) headed by a **small glowing white dot + an uppercased gray label**. White
is the **only** accent color. Toggles are **macOS-style switches** that invert to a **white track + black
knob** when on. Multi-choice settings are **segmented controls** (joined pill segments, the selected one
filled white-at-16%). Every setting label has a small circular **ⓘ** button that reveals a title +
plain-language explanation + an "e.g." example on hover. Changes **apply instantly** (no OK/Cancel).

The look is deliberately copied from a sibling app the owner likes ("JVoice"): black surfaces, glowing-dot
card headers, white-as-sole-accent, mono switches.

## 1.2 Current macOS state (the gap)

`App/Settings/SettingsView.swift` is a native SwiftUI **`TabView` with 3 tabs** (General / Shortcuts /
Recording), `.frame(width: 480)`, using stock SwiftUI controls (native green `Toggle`s, pop-up `Picker`s,
grouped `Form`s) that follow the OS light/dark appearance. Hosted by `App/Settings/SettingsWindowController.swift`
in a plain `NSWindow`. It is **already instant-apply** (each `bind(...)` setter calls `store.persist()`).

So the **behavior** mostly matches already; the **entire presentation** must change: kill the tabs, force a
fixed black theme, and rebuild every control as a custom monochrome component inside a card masonry.

## 1.3 Full palette (copy these hex values exactly)

| Role | Hex / ARGB | Where used |
|---|---|---|
| Window background | **#000000** | the settings window (pure black) |
| Chrome / recessed input fill | **#0A0A0A** | segmented-control track, text fields, shortcut chips |
| Card / popup / tooltip | **#0E0E0E** | every `DarkSection` card, combo popups, tooltips |
| Control resting fill | **#1A1A1A** | resting combo/button fill |
| Control hover | **#242424** | |
| Control pressed | **#2E2E2E** | |
| Border / hairline | **#2A2A2A** | 1px card borders, dividers, **switch OFF track** |
| Primary text | **#F5F5F7** | body text |
| Field labels / row titles / segment text | **#D9D9D9** | (the "W85" gray) |
| Card header label, combo chevron | **#8E8E93** | (secondary gray) |
| Sub-labels, footer, subtitle | **#6E6E73** | (subtle gray) |
| Faintest text | **#595959** | |
| **Accent = WHITE** | **#FFFFFF** | the single accent (switch ON track, slider fill, glowing dot, checked segment text) |
| Accent hover / pressed | **#E6E6E6** / **#CFCFCF** | dim-white states; #CFCFCF is also the switch OFF knob |

**Grayscale text ladder:** #FFFFFF → #D9D9D9 → #8E8E93 → #6E6E73 → #595959.

**Literal alphas worth copying:** segment hover `#12FFFFFF`; **segment checked fill `#29FFFFFF`** (white ≈16%);
combo-item highlight `#29FFFFFF`; pill-button fill/hover/pressed `#1FFFFFFF` / `#2BFFFFFF` / `#3AFFFFFF`, pill
border `#3DFFFFFF`; switch OFF knob `#CFCFCF`; InfoTip idle/hover/ring/glyph `#1FFFFFFF` / `#40FFFFFF` /
`#40FFFFFF` / `#E6FFFFFF`; primary "accent button" text `#0A0A0A` on white.

> **Assumption logged:** the macOS settings window should **force this fixed dark theme and ignore the OS
> light/dark setting** (the Windows app is always this black theme). If the owner prefers macOS to follow
> system appearance, that's a deliberate later change — but "identical to Windows" means always-black.

## 1.4 Typography

- **Family:** system UI font (Windows uses Segoe UI; on macOS use the system font / SF Pro). Monospace for the
  shortcut chips only (Windows: Cascadia Mono/Consolas; macOS: SF Mono / Menlo).
- **Sizes / weights:** header title **18 Bold** (white) · card header label **10 Bold, UPPERCASED** (#8E8E93) ·
  field label **11.5 SemiBold** (#D9D9D9) · row title **12.5 Medium** (#D9D9D9) · row sub-label **10.5** (#6E6E73) ·
  subtitle **11.5** (#6E6E73) · footer **11** (#6E6E73) · segment text **12** · shortcut action title **12.5** ·
  shortcut chip **12** mono · slider value **12 SemiBold** · pill button **12 SemiBold** · InfoTip tooltip title
  **12.5 SemiBold** / body **11.5** / example **11 Italic**.

## 1.5 Window + overall layout

| Property | Value |
|---|---|
| Width | **960**, fixed (macOS: not resizable width; keep `[.titled, .closable, .miniaturizable]`, no `.resizable`) |
| Height | **size-to-content**, clamped to ~**98% of the screen work-area height** (so the close button stays reachable; only then does the inner scroll engage) |
| Background | **#000000** |
| Title bar | dark (Windows darkens the caption; on macOS use a dark titlebar / `titlebarAppearsTransparent` + dark material as appropriate) |
| Start location | centered |

Structure (top to bottom), inside an **18px outer margin**:

1. **Header block** — Title **"BetterScreenshot"** (18 Bold, white) + a wrapping subtitle (11.5, #6E6E73):
   *"Capture & recording preferences — hover the ⓘ next to any setting for a plain-language explanation and
   example."*
2. **Three-column card masonry** — three equal columns, **≈297px each**, separated by two **16px gutters**
   (960 − 36 outer − 32 gutters ÷ 3 ≈ 297). Cards stack vertically within a column with **12px vertical gaps**.
   - **Column A:** *Capture* · *Quick Access Overlay* · *Pin to Screen*
   - **Column B:** *History* · *Startup* · *Save Location*
   - **Column C:** *Recording* (one tall card)
3. **Keyboard Shortcuts** — one **full-width** card spanning all three columns.
4. **Footer note** — *"Changes apply immediately."* (11, #6E6E73).

## 1.6 The reusable components (build these as custom SwiftUI/AppKit views)

None of these exist on macOS today — macOS uses stock controls. Build each to this spec.

### DarkSection (the card)
- Rounded rectangle, **corner radius 10**, fill **#0E0E0E**, **1px #2A2A2A** border.
- **Header row** (inset ~14,10): a **5×5 white dot with a soft glow** (white circle + outer blur/shadow, radius
  ~7, white @ 60% opacity) + **8px gap** + the **UPPERCASED** title (**10 Bold**, #8E8E93).
- A **1px #2A2A2A hairline** divider under the header, full width.
- Content inset **14,12,14,14**.

### MonoSwitch (replaces native green Toggle) — *this is a signature element*
- Track **38×22, corner radius 11**.
- **OFF:** track **#2A2A2A**, knob = **18×18 circle #CFCFCF**, left-aligned (2px inset).
- **ON:** track **#FFFFFF (white)**, knob = **#000000 (black)**, right-aligned (2px inset). *(The white-track /
  black-knob inversion is the point — a native SwiftUI `Toggle` can't do it; build a custom `ToggleStyle`.)*
- Disabled → 40% opacity. Cursor: pointing hand.

### Segmented control (replaces the pop-up Pickers)
- A joined row of segments; each segment has a **#2A2A2A** 1px border and content inset ~8,5, text **12 #D9D9D9**.
- **Resting fill #0A0A0A** (the recess). **Hover #12FFFFFF.**
- **Selected: fill #29FFFFFF (white ≈16%), text → white #FFFFFF.**
- **Corners rounded only on the ends:** left segment rounds its left corners (radius 6), right segment its
  right corners, middle segments square. A single segment ("solo") rounds all four.

### PillButton (small in-card action: "Browse…", "Change")
- Text **12 SemiBold #F5F5F7**, inset ~12,6, **corner radius 7**, 1px border.
- Fill **#1FFFFFFF**, border **#3DFFFFFF**; hover fill **#2BFFFFFF**; pressed **#3AFFFFFF**; disabled 40%.

### AccentButton (crisp primary — used elsewhere, e.g. editor "Copy")
- **White fill #FFFFFF, black text #0A0A0A**, no border, corner radius 6, inset ~12,5, size 13.
- Hover **#E6E6E6**; pressed **#CFCFCF**.

### InfoTip (the ⓘ affordance — new on macOS)
- A **16px circle** (radius 8), idle fill **#1FFFFFFF**, hover **#40FFFFFF**, 1px **#40FFFFFF** ring. Uses the
  **normal arrow cursor** (deliberately not a help/`?` cursor).
- Glyph: a small **italic-bold serif "i"**, ink height ~9px, centered by its ink bounds, fill **#E6FFFFFF**.
  *(Windows draws it as a vector path, not text, to avoid subpixel color-fringing — on macOS just render an
  SF Symbol like `info` or an attributed serif "i"; the anti-fringing concern is a Windows ClearType issue
  that doesn't apply to macOS.)*
- **Tooltip on hover:** a #0E0E0E card (1px #2A2A2A border, radius 6, inset 8,5), max width ~300, containing a
  **Title** (12.5 SemiBold, #F5F5F7), an **Explanation** (11.5, #D9D9D9), and an optional **"e.g. …" Example**
  (11 Italic, #6E6E73). Show delay ~120ms.
- The tooltip copy for each setting + each shortcut can be lifted verbatim from the Windows source
  (`windows/src/BetterScreenshot.App/Settings/SettingsWindow.xaml` inline, and the `ShortcutHelp` table in
  `SettingsWindow.xaml.cs`). If you can't read that tree, write concise equivalents — one sentence + one
  concrete example each.

### Monochrome slider (auto-dismiss control — see Part 2 §2.6 for the value mapping)
- Base track: 4px tall, radius 2, **#1AFFFFFF**. Filled (left-of-thumb) portion: 4px, **white #FFFFFF**.
- Thumb: **16×16 white circle**; hover #E6E6E6, dragging #CFCFCF.

### Mono scrollbar
- Thin (~10px), transparent track, **no arrow buttons**, thumb = **#33FFFFFF** rounded (radius 4). (On macOS,
  the overlay scroller in a dark scroll view is close enough; style if needed.)

### ComboBox / TextField (for Pin radius + Save path)
- Combo: height ~30, fill **#1A1A1A**, 1px **#2A2A2A** border, radius 6, chevron **#8E8E93**; popup **#0E0E0E**,
  highlighted item **#29FFFFFF**.
- Text field: fill **#0A0A0A**, 1px **#2A2A2A** border, radius 6, inset 8,4; **focus border → white**.

## 1.7 The cards — exact contents

Field-label rows put a **field label above** a segmented control. Boolean rows put a **row title (+ optional
sub-label) on the left** and a **MonoSwitch on the right**. Every label is followed by an **InfoTip ⓘ**.

**Card 1 — CAPTURE**
- Field label **"After a capture"** → 4-segment: **Overlay | Copy | Save | Both**.
- Field label **"Image format"** → 2-segment (left-aligned, ~160 wide): **PNG | JPG**.
- Row **"Play a sound on capture"** → MonoSwitch. **⚠ macOS has no such setting today** — see §1.9.

**Card 2 — QUICK ACCESS OVERLAY**
- Field label **"Screen corner"** → 4-segment showing **↖ ↗ ↙ ↘** glyphs (15pt): TL / TR / BL / BR.
- Field label **"Auto-dismiss after"** → the **monochrome slider** + a right-aligned value label (min-width
  ~46, 12 SemiBold). Reads **"2s" … "30s"**, and the far end reads **"Never"**. Mapping = `OverlayDismissScale`
  (Part 2 §2.6). **macOS: the underlying `overlayAutoDismissSeconds` setting already exists but is unwired —
  see Part 2 §2.6 / D6.**

**Card 3 — PIN TO SCREEN**
- Row **"Corner radius"** → styled ComboBox with items **0 / 4 / 8 / 12 / 16 / 20**. *(macOS currently uses a
  0…20 slider for this — either keep the slider styled monochrome, or switch to the combo to match Windows
  exactly. Assumption: match Windows → combo. Log if you keep the slider.)*
- Row **"Drop shadow"** → MonoSwitch.

**Card 4 — HISTORY**
- Row **"Remember capture history"** (+ sub-label *"Keep a local index of recent captures"*) → MonoSwitch.
- Field label **"Keep at most"** → 3-segment: **10 | 50 | 100**. **⚠ macOS currently offers 10 / 50 / 200** —
  change the third option to **100** to match (see Part 3, fix #5).

**Card 5 — STARTUP**
- Row **"Launch at login"** (+ sub-label *"Start BetterScreenshot when you sign in"*) → MonoSwitch.

**Card 6 — SAVE LOCATION**
- Sub-label *"Where saved captures & recordings are written"*.
- A row: the current path in a text field + a **PillButton "Browse…"** (opens `NSOpenPanel`, folders only).

**Card 7 — RECORDING**
- Field label **"Format"** → 2-segment: **MP4 | GIF**.
- Field label **"Frame rate"** → 2-segment: **30 fps | 60 fps**.
- Hairline divider (1px #2A2A2A).
- Rows (MonoSwitch each): **"Record system audio"**, **"Record microphone"**, **"Show camera bubble"**.
- Field label **"Camera size"** → 2-segment: **Small | Medium**.
- Rows (MonoSwitch each): **"Highlight mouse clicks"**, **"Show keystrokes"** *(keep the macOS Accessibility-
  permission gate + caption — the toggle stays off until permission is granted)*.
- Field label **"Countdown before recording"** → 4-segment: **Off | 3s | 5s | 10s**.

**Card 8 — KEYBOARD SHORTCUTS** (full-width)
- Sub-label: *"Click Change, then press the new key combination (Esc cancels). Hover the ⓘ on any row to see
  what that shortcut does."*
- Rows built in code, **two per row** (a left column and a right column with a center gutter). Each row:
  **action title (12.5) + ⓘ**, then a **mono chip** (a #0A0A0A pill, 1px #2A2A2A border, radius 6, min-width
  ~118, mono 12 text) showing the combo (or "(unbound)"), then a **"Change"** PillButton and a **"Clear"**
  button.
- Actions: **Capture Area, Capture Window, Capture Fullscreen, Capture Text, Pin from Clipboard, Record, Open
  History, Restore Recently Closed, Pause/Resume Recording**. *(macOS already has a `ShortcutRecorderField`
  and the suspend/resume-during-record wiring — reuse that logic; just restyle the row to this card look and
  swap the single field for the chip + Change/Clear pair.)*

## 1.8 Behavior (mostly already correct on macOS — keep it)
- **Instant-apply, no OK/Cancel.** macOS already persists on every change. Keep a `_loading`-style guard so
  populating the controls at open doesn't write back.
- **Live hotkey rebind:** "Change" suspends the global hotkeys, captures the next combo (Esc cancels),
  rejects conflicts with an alert, persists, updates the chip, and re-registers live. macOS already does the
  suspend/resume dance via `actions.recordingChanged` — reuse it.
- **Destructive actions stay guarded by a confirm dialog** (History "Clear History…" already has a
  `confirmationDialog` on macOS — keep it). No red buttons; destructive is monochrome + guarded.

## 1.9 macOS settings keys — present vs missing

- **Already present** in `CaptureSettings` (`Packages/CaptureKit/Sources/CaptureKit/CaptureSettings.swift`) +
  `RecordingConfig`: `afterCapture`, `format`, `overlayCorner`, **`overlayAutoDismissSeconds` (default 6)**,
  `pinShadow`, `pinCornerRadius`, `historyEnabled`, `historyCap`, all recording fields, `saveDirectory`,
  `bindings`, launch-at-login. → The **auto-dismiss slider needs no new persistence** (key exists, just unwired).
- **Missing / to reconcile:**
  - **"Play a sound on capture"** — **no such key on macOS.** To render this card row you must add a new
    `SettingsStore`/`CaptureSettings` boolean **and** actually play a sound on capture, OR omit the row.
    **Assumption logged:** add the setting + play the system screenshot/`Tink`-style sound, defaulting **on**
    to match the Windows default — but if you'd rather not add a feature just for UI parity, omitting this one
    row is acceptable; note it.
  - **History cap 200 → 100** (fix #5).
  - **InfoTip help copy** — new; port from Windows or write concise equivalents.

## 1.10 Files to touch on macOS (Part 1)
- `App/Settings/SettingsView.swift` — replace the whole `TabView` with the card masonry + custom components.
- `App/Settings/SettingsWindowController.swift` — window width (960), size-to-content + height clamp, dark
  titlebar, non-resizable.
- `App/Settings/SettingsStore.swift` + `Packages/CaptureKit/Sources/CaptureKit/CaptureSettings.swift` — add
  capture-sound key (if adopted); realign `historyCap` option to 100; ensure `overlayAutoDismissSeconds` is
  surfaced.
- New files for the custom components (e.g. `App/Settings/Components/…` or a small design-system file):
  `DarkSection`, `MonoSwitch` (`ToggleStyle`), `SegmentedControl`, `PillButton`, `InfoTip`, the mono slider,
  and a palette/theme constants file holding all the hex values above.

---

# Part 2 — Quick Access card: full-bleed image + overlaid auto-contrast buttons

## 2.1 The target, in one paragraph

After a capture, a small floating card appears in a screen corner. In the redesign, **the captured image
fills the entire rounded block edge-to-edge — the card *is* the screenshot.** The action buttons **float over
the bottom of the image** on a subtle tone-matched gradient scrim, and the button glyphs (plus their
hover/press states) **automatically flip black or white** depending on how bright the image is behind the
toolbar. Cards can differ in height (they follow each capture's aspect ratio), so the stack repositions
using each card's actual size. An **auto-dismiss timer** (a "2s…Never" slider in Settings) closes the card
after a delay, pausing while you hover.

## 2.2 Current macOS state (the gap)

`Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift` is the **old letterboxed** design:
- Fixed **220×168** panel for every capture regardless of aspect.
- The image is a **small letterboxed thumbnail** at inset `(10, 46, 200×112)`, `scaleProportionallyUpOrDown`
  (fit, not fill), on a **solid `windowBackgroundColor` card** (recordings tinted blue), corner radius 12.
- A **separate button strip** of `.rounded`-bezel `NSButton`s (width 36) sits *below* the thumbnail at y≈8.
- **No auto-contrast** (system-colored buttons), **no scrim**, **no auto-dismiss** (a comment notes the old
  auto-dismiss `NSTrackingArea` crashed with `doesNotRecognize mouseEntered:` and was removed).
- Drag-to-export already works (the `DraggableImageView` carries the drag; temp PNG self-deletes for
  screenshots, real file for recordings; drag-end dismisses `.actionTaken`).
- Stacking (`QuickAccessStackController.swift`) is **fixed-step / uniform-size**: it asks an injected
  `originForIndex` closure, and `CaptureCoordinator.presentOverlay` supplies
  `OverlayPositioner.stackedOrigin(overlaySize: CGSize(220,168), …)` which offsets each index by a constant
  `height + spacing(12)` — it assumes all cards are the same height.

So `QuickAccessKind`, `DismissReason`, the actions callback set, drag-to-export, `maxCount=3`, `margin=24`,
`spacing=12`, and corner configurability **already match**. The delta is: full-bleed sizing, overlaid
auto-contrast buttons, the scrim, variable-height stacking, and wiring the auto-dismiss slider.

## 2.3 Card sizing (full-bleed, aspect-derived) — exact numbers

> **Note:** the Windows *design doc* cites width 236 / clamp [132,280], but the **actual Windows code uses the
> values below** — use these.

| Constant | Value | Meaning |
|---|---|---|
| Content width | **210 pt** | fixed image/card width |
| Min content height | **150 pt** | clamp floor |
| Max content height | **280 pt** | clamp ceiling |
| Corner radius | **14 pt** | rounded clip radius (must also be the hairline radius) |

Sizing math:
```
aspect        = imagePixelWidth / imagePixelHeight        (fallback 16/9 if height <= 0)
contentHeight = clamp(210 / aspect, 150, 280)
```
- **Width is fixed at 210**; height follows the image aspect, clamped to [150, 280]. Common case: the block
  matches the image aspect exactly → the whole capture is visible with no letterbox. Extreme panoramas /
  portraits clamp, and the image **center-crops (fill, not fit)** to stay full-bleed.
- The image must be **fill, not fit**. AppKit `NSImageView` has no direct "UniformToFill" — host the image in
  a `CALayer` with `contentsGravity = .resizeAspectFill` + `masksToBounds = true`, or draw it aspect-fill in a
  custom view. (Windows uses `Stretch=UniformToFill` + high-quality scaling.)

**Rounded corners that also clip the overlays** — the key trick: a rounded card whose *background* is rounded
does **not** automatically clip its children (buttons/scrim would poke past the corners). So the container
that holds image + scrim + buttons must itself be **clipped to the rounded rect** (radius 14): on macOS, set
`container.layer.cornerRadius = 14; container.layer.masksToBounds = true` on the layer that contains all of
them. Keep the panel's native shadow (or add a custom one) so it hugs the rounded silhouette. Optionally add
a 1px hairline top border **#26FFFFFF** (white ≈15%).

## 2.4 Button row

- Centered horizontally, anchored to the **bottom**, **9 pt up** from the bottom edge.
- Buttons and order **by kind**:
  - **Screenshot (5):** Copy → Edit → Pin → Save → Close
  - **Recording (4):** Copy → Open(play) → Reveal(folder) → Close
- **Which buttons dismiss the card:** Copy does **not** (card stays); Edit / Pin / Save / Open / Reveal
  dismiss with `.actionTaken`; Close dismisses with `.closed`.
- macOS keeps its SF Symbols, rendered as **template images tinted with the contrast glyph color** (§2.5):
  `doc.on.doc` (Copy), `pencil.tip.crop.circle` (Edit), `pin` (Pin), `square.and.arrow.down` (Save),
  `play.fill` (Open), `folder` (Reveal), `xmark` (Close).
- Button box **32×30 pt**, glyph **17×17 pt**, **4 pt gap** between buttons, hover/pressed "pill" **radius 7**.
- Chromeless: transparent background; on hover fill the pill with the palette **hover** color, on press the
  **pressed** color, else clear. (Custom layer-backed `NSButton` subclass, or a small view with mouse
  tracking.)
- There is **no dedicated drag button** — drag-to-export is a gesture on the whole card surface (§2.7).

## 2.5 Auto-contrast algorithm — reimplement exactly

Split into a **pure** part (unit-test it) and a **color-construction** part.

**Sampling (`SampleBottomLuminance`):**
1. `w, h = image pixel size`. If either ≤ 0 → return luminance **0.0**.
2. **Crop the bottom 30% strip** (where the toolbar sits): `stripH = max(1, Int(h * 0.30))`, rect
   `(x: 0, y: bottom, width: w, height: stripH)` in image-pixel space. *(Watch macOS image-coordinate
   conventions — sample the pixels that are visually at the **bottom** of the displayed image.)*
3. **Downscale so the longest side ≤ 48px:** `scale = min(1.0, 48.0 / max(stripW, stripH))`; if `scale < 1`,
   scale the strip down (draw into a small `CGContext` / use `vImage`).
4. **Read pixels** into a byte buffer (track channel order — BGRA or RGBA).
5. Return **average Rec.709 relative luminance**.
6. Any failure → **return 0.0** (falls back to the dark-background palette = light glyphs).

**Luminance + threshold (pure):**
```
for each pixel (channels normalized to 0..1, alpha ignored):
    lum += 0.2126*R + 0.7152*G + 0.0722*B
average = lum / pixelCount          // 0 if the buffer is empty

LightThreshold = 0.58
isLightBackground = (average > 0.58)
```
`true` = strip is **light** → use **dark** controls. `false` = **dark** strip → **light** controls.
**One tone for the whole row** (not per-button) — a single boolean drives glyph, hover, pressed, and scrim
together (per-button contrast would look like a bug).

**The boolean → every color (exact ARGB):**

| | Light bg → DARK controls | Dark bg → LIGHT controls |
|---|---|---|
| Glyph | **#FF18181A** (near-black) | **#FFF4F4F6** (near-white) |
| Hover pill | **#24000000** (black ≈14%) | **#2BFFFFFF** (white ≈17%) |
| Pressed pill | **#3D000000** (black ≈24%) | **#45FFFFFF** (white ≈27%) |
| Scrim | **white** gradient | **black** gradient |

## 2.6 The scrim (tone-matched bottom gradient)

Guarantees legibility where the bottom edge is *mixed* (glyph-only contrast fails at mid-grey averages). The
scrim **shares the image's tone** — faint white over a light image, faint black over a dark one — so it never
looks like a heavy dark bar over a bright screenshot.

- A **bottom-anchored gradient**, over the image, **under** the buttons, ignoring hit-testing.
- **Height = `min(64, contentHeight * 0.42)` pt** (covers roughly the bottom 40%, capped at 64).
- Vertical gradient, tone = white or black per the boolean, **alpha stops** (transparent at the top of the
  scrim → max at the card's bottom edge): `0.0 → alpha 0x00`, `0.5 → alpha 0x2E (≈18%)`, `1.0 → alpha 0x8C
  (≈55%)`. *(In Cocoa's bottom-left space, the ~55% end is the visual bottom.)*
- If the owner ever wants "glyphs only, no scrim," it's a one-line change — but ship with the scrim.

## 2.7 Drag-to-export (already works on macOS — keep, just move the gesture)

- Drag the card to Finder to export the PNG. On macOS this already works via the `DraggableImageView`'s drag
  (`fileURLProvider` → `TempImageWriter.writePNG(...)`, `deletesFileAfterDrag` for screenshots, real file for
  recordings, `onDragEnded → dismiss(.actionTaken)`).
- Since the image is now full-bleed and buttons overlay it, make sure the **drag gesture lives on the card
  surface behind the buttons** (a >4pt move threshold before starting the drag), and the buttons still receive
  their clicks. Windows uses a dedicated transparent `DragSurface` behind the button row for exactly this.
- **Temp-file cleanup:** the drag temp PNG must not leak. See Part 3 fix #4 — schedule deletion ~5 min after
  the card is dismissed (screenshots only; recordings drag the real saved file and must not be deleted).

## 2.8 Variable-height stacking (rework the controller + call sites)

The current macOS stacker assumes a **uniform** `overlaySize (220×168)` via `OverlayPositioner.stackedOrigin`.
With per-image heights that breaks. Mirror the Windows approach:

- Have the controller position cards **cumulatively from the corner using each card's actual height**:
  ```
  isRight  = corner in {topRight, bottomRight}
  isBottom = corner in {bottomLeft, bottomRight}
  cursor   = isBottom ? visibleFrame.maxY-ish corner edge : top edge, inset by margin(24)
  for each card, newest first (nearest the corner):
      x = isRight ? right - card.width - 24 : left + 24
      place the card, then advance cursor by (card.height + spacing(12)) toward center
  ```
  Bottom corners stack **upward**, top corners **downward**; newest nearest the corner. Because the cursor
  advances by each card's **own** height, differing heights pack tightly. Use `screen.visibleFrame` (Cocoa
  bottom-left; excludes Dock + menu bar).
- Keep `maxCount = 3`, `margin = 24`, `spacing = 12`, oldest-evicted-first, and corner configurability.
- **Two ways to implement** (either is fine): (a) move positioning into `QuickAccessStackController` so it
  reads each controller's actual frame/height (preferred — mirrors Windows `Restack`), or (b) keep the
  injected-closure architecture but add a **variable-height** `OverlayPositioner.stackedOrigin(heights:index:)`
  and leave the fixed-step one intact for anything else that uses it.
- Update **`CaptureCoordinator.presentOverlay`** and the **`RecordingCoordinator`** call site (its overlay
  presentation, ~lines 387–397) so they no longer hard-code `CGSize(220, 168)`.

## 2.9 Auto-dismiss slider (wire the already-persisted field)

The model field exists (`CaptureSettings.overlayAutoDismissSeconds`, default **6**) but **nothing uses it on
macOS**. To match Windows:

1. **Port `OverlayDismissScale`** (pure, unit-tested) into `Packages/CaptureKit`:
   `MinSeconds=2`, `MaxSeconds=30`, `NeverSeconds=0`, `NeverPosition = 31`.
   - `secondsToPosition(seconds)` / `positionToSeconds(position)` round-trip; slider positions **2..30** map to
     that many seconds, position **≥31 = "Never"** (persists as **0**).
   - `label(seconds)` = **"Never"** for ≤0, else **"{n}s"**.
2. **Add the slider to Settings** (Part 1, Card 2 "Quick Access Overlay"): a 2..31 monochrome slider through
   `OverlayDismissScale`, with the live "Never"/"{n}s" readout.
3. **Wire it into the overlay:** pass `overlayAutoDismissSeconds` from `CaptureCoordinator` /
   `RecordingCoordinator` → `QuickAccessStackController.present(...)` → `QuickAccessOverlayController`.
   - In the controller: if seconds ≤ 0 → **persistent** (no timer). Else a one-shot `Timer` (interval =
     seconds) → `dismiss(reason: .closed)`.
   - **Hover pause:** stop the timer on mouse-enter, **restart the full countdown** on mouse-exit.
     ⚠ The old macOS auto-dismiss crashed because the `NSTrackingArea` owner didn't respond to `mouseEntered:`.
     `QuickAccessOverlayController` is now an `NSObject`, so add the tracking area with `owner: self` (and
     implement `mouseEntered:`/`mouseExited:`), **or** use a small view subclass that overrides them. Test this
     path carefully.
   - Auto-dismiss maps to **`.closed`**, so the card stays restorable via "Restore Recently Closed."

## 2.10 Key numbers (single reference)
Width **210**, height clamp **[150, 280]**, corner radius **14**, hairline **#26FFFFFF**; button **32×30**,
glyph **17×17**, gap **4**, pill radius **7**, row bottom margin **9**; scrim height **min(64, h·0.42)**, alpha
stops **0 / 0x2E(18%) / 0x8C(55%)**; sample **bottom 30%**, downscale **≤48px**, luminance
**0.2126R+0.7152G+0.0722B**, threshold **> 0.58**; light-bg glyph **#18181A** + hover **#24000000** + pressed
**#3D000000** + white scrim; dark-bg glyph **#F4F4F6** + hover **#2BFFFFFF** + pressed **#45FFFFFF** + black
scrim; stacking max **3**, margin **24**, spacing **12**; auto-dismiss **2..30s + Never(0)**, default **6**.

## 2.11 Files to touch on macOS (Part 2)
- `Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift` — full-bleed image, overlaid
  buttons, scrim, rounded-clip, auto-contrast, auto-dismiss timer + hover-pause.
- `Packages/OverlayKit/Sources/OverlayKit/QuickAccessStackController.swift` — variable-height cumulative
  stacking.
- `Packages/CaptureKit/Sources/CaptureKit/OverlayPositioner.swift` — (option b) add a variable-height
  positioner; leave the fixed-step one + its tests intact.
- **New:** `Packages/OverlayKit/…/QuickAccessContrast.swift` (pure luminance + palette) with tests; and
  `Packages/CaptureKit/…/OverlayDismissScale.swift` (pure) with tests.
- `App/Capture/CaptureCoordinator.swift` + `App/Recording/RecordingCoordinator.swift` — stop hard-coding the
  overlay size; pass `overlayAutoDismissSeconds`; keep the temp-PNG drag file (add the 5-min cleanup, fix #4).

---

# Part 3 — Bug fixes & behavior changes to backport

Mined from the Windows ledger (`windows/docs/PROGRESS.md` + investigation docs). Each item notes whether the
same defect plausibly exists on macOS. I've **verified a few directly against the macOS source** — noted inline.

## 3.A Port these (shared UX/behavior improvements)

**1. Editor text annotation: optional auto-contrast background chip + WYSIWYG live editing.**
Windows added an optional rounded "label" chip behind text annotations whose color auto-contrasts (dark chip
behind light text, light behind dark), off by default, sticky; and made the inline editing box chrome-less so
what you type matches the flattened output. **Verified on macOS:** `Packages/EditorKit/…/AnnotationStyle.swift`
has only `strokeColor / fillColor / lineWidth / fontSize` — **no text-background field**, and
`TextAnnotation.swift` has no chip. To port: add a new **optional** `textBackground` to `AnnotationStyle`
(Codable — make it decode as `nil` for existing persisted styles so old data still loads), render it in
`DocumentRenderer`, add an inspector toggle in the editor, and persist the choice in the sticky
`editorDefaultStyle`. *(This adds a persisted style field the macOS model currently lacks.)*

**2. Quick Access auto-dismiss slider + hover-pause.** Covered by Part 2 §2.9. On Windows the persisted
setting was a *dead* setting until wired; **macOS is in exactly that state now** (`overlayAutoDismissSeconds`
exists, default 6, but nothing consumes it). Wire it + add the slider.

**3. Quick Access card redesign (full-bleed + auto-contrast + variable-height stack).** This is Part 2 in full.

**4. Drag-to-export temp PNG auto-deletes (was leaking in temp).** Windows' drag temp `quickaccess.png` was
never deleted and piled up in `%TEMP%`; now deleted ~5 min after the card is dismissed (the separate History
copy is preserved). **macOS also writes a temp PNG for drag-out** (`TempImageWriter.writePNG` via
`fileURLForDrag`) — it already `deletesFileAfterDrag` for screenshots, but if a card is dismissed **without** a
drag, that temp file may linger. Add the same "delete ~5 min after dismiss" safety net; **never** delete for
recordings (they drag the real saved file).

**5. History cap options → 10 / 50 / 100 (was 10 / 50 / 200).** Owner preference is a **100** max (default
stays 50). Change the third option on macOS from 200 to 100 in the Settings segmented control and in
`CaptureSettings.historyCap` validation. (Also required for Part 1 Card 4 to match visually.)

**6. Per-setting info tooltips (ⓘ).** The InfoTip affordance (Part 1 §1.6) — a UX feature worth mirroring, not
just chrome. Port the help copy for each setting + shortcut.

**7. Capture Text failure feedback.** Windows shows a "Capture Text failed" HUD on OCR exception instead of
silently swallowing it. **Verify** macOS surfaces OCR/text-recognition failures to the user rather than
failing silently; if not, add a small HUD/notice on the failure path.

## 3.B Verify on macOS (likely-shared robustness fixes — confirm before/while porting)

**8. Editor: annotations draggable outside the image → clamp to image bounds.** Windows clamped the editor
pointer to `[0,imgW]×[0,imgH]` and clamps a moved annotation's bounding box inside the image, so shapes/text/
counters can't be dragged off-canvas and clipped on flatten. **Verified on macOS:** `EditorCanvasView.swift`
computes rects with `min`/`max` but shows **no clamp of the drag point to the image bounds** — so the macOS
editor plausibly has the same off-canvas bug. Add a bounds clamp to the pointer and to Select-tool moves.

**9. Editor: per-frame full-resolution re-raster while annotating (stutter).** Windows was calling its
flatten-to-image renderer **every mouse-move**, allocating a full-res bitmap per frame (GC thrash → stutter);
fixed to draw a lightweight vector preview during the drag and flatten only on mouse-up. **Verify on macOS:**
the macOS editor is a custom `NSView` that normally draws annotations as vectors in `draw(_:)` and only uses
`DocumentRenderer` for export — so it probably **doesn't** have this anti-pattern. But confirm the live
drawing/move path does **not** invoke `DocumentRenderer.render` per mouse event; if it does, switch to a
vector preview during the drag.

**10. Capture over-reads past the real framebuffer on stretched/scaled resolutions → black bar.** On Windows,
capturing a display sized from `GetMonitorInfo` (logical size) over-read the real framebuffer under a
stretched/custom scanout and GDI padded the excess with a black bar; fixed by clamping every capture to the
**actual framebuffer size** (and region capture to the live virtual-screen extent). **Verify on macOS:** this
is largely a GDI `BitBlt` artifact; ScreenCaptureKit returns the actual pixel buffer, so macOS is *likely*
immune. But **the owner runs a stretched-resolution gaming rig** (this is flagged in project memory), so
confirm the macOS capture→crop path derives dimensions from the **actual captured pixel buffer**, not the
reported logical monitor size — especially under stretched/scaled/Retina modes. `CaptureGeometry.swift` only
scales rects; check `CaptureService.swift`.

**11. Area selection can run past the monitor edge → clamp the selection rect to bounds.** Windows clamped the
selection rect to the monitor extent (unclamped captured-mouse points let a drag select off-screen).
**Verified on macOS:** `SelectionOverlayController.swift:98` builds the rect with `min(...)` and **no clamp**.
On macOS the full-screen overlay panel usually confines the pointer, so risk is lower than on Windows — but
confirm a fast drag past the edge can't select/capture beyond the screen; add a clamp if it can.

**12. Editor text-commit re-entrancy crash.** Windows crashed when adding text then clicking back onto the
image, because a shared text-field reference was committed by the wrong field's blur handler
(re-entrancy → null deref). Root cause was WPF focus-event specific, but the **shape** of the bug
(commit-on-blur referencing a shared/stale text field) can bite AppKit too. **Verify** the macOS text tool's
commit-on-blur/commit-on-new-click references the *specific* field that resigned, not a shared mutable field.

## 3.C Windows-only — context only, do NOT port

These are WPF/Win32/DPI/ffmpeg/dev-tool specifics with no macOS analog, or "Windows catching up to what macOS
already does." Listed so you know they're intentionally skipped:

- JVoice monochrome re-skin, 960/3-column layout, "settings don't save"/instant-apply fix, human-readable
  VK-key names, `(vk 190)` display fix — **these ARE the Part 1 target**, but the *specific* WPF snapshot/
  revert + VK-code bugs don't exist on macOS.
- InfoTip cursor (`Cursors.Help` → arrow) and crisp vector-"i" vs ClearType fringing — **ClearType/WPF glyph
  rendering**; macOS text isn't subpixel-fringed the same way (still render the ⓘ as a symbol/vector, but the
  *bug* is Windows-only).
- Selection overlay on all monitors / re-entry guard / punch-out hit-testing, Capture-Text region overlay,
  drag-out dismisses the card, black-on-white in-canvas text box — **Windows catching up to macOS**, which
  already does these. (Still worth a 30-second confirm that macOS really does.)
- Editor "gray dead-zones" FitToImage, Quick Access buttons bleeding on hover, the `--ui-preview`/`dist/`
  deploy gotchas, the record-elapsed doc-typo note — **WPF layout / Windows dev-tooling**; no macOS analog.
- `ClickHighlighter` accent kept blue — it's baked into the recorded video, not chrome.

---

# Verification checklist (run before claiming done)

1. **Build:** the macOS app builds clean (`scripts/build-app.sh` assembles `dist/BetterScreenshot.app`, CLT-only).
2. **Tests:** `scripts/test.sh` — all TestKit suites green, including new tests for `OverlayDismissScale` and
   `QuickAccessContrast` (white → light/dark glyphs, threshold boundary, empty buffer, stride padding).
3. **Settings, by eye:** open Settings — pure-black window, three-column card masonry, glowing-dot card
   headers, white/black mono switches, segmented controls (selected = white-16% + white text), ⓘ tooltips,
   auto-dismiss slider reading "Never"/"{n}s", instant-apply (change a value, reopen — it stuck), live hotkey
   rebind still works, "Clear History…" still confirms. **No white-on-white, no native green toggles, no
   system-blue accents.**
4. **Quick Access card, by eye:** take a screenshot of a **bright** window → **dark** glyphs; a **dark** window
   → **light** glyphs; the image is full-bleed + rounded (no letterbox, no separate strip); buttons overlay the
   bottom on a faint tone-matched scrim; stack three captures of different aspect ratios → they pack tightly by
   actual height; auto-dismiss fires after the set delay and **pauses on hover**; drag the card to Finder →
   exports the PNG and dismisses; the temp file doesn't linger.
5. **Part 3 fixes:** re-check each ported/verified item behaves as described.

# Assumptions & open questions for the owner (logged)

- **Force fixed dark theme on macOS Settings** (ignore system light/dark) to match Windows' always-black look.
- **"Play a sound on capture"** doesn't exist on macOS — either add the setting + a capture sound (default on),
  or omit that one card row. Recommend adding it for true parity.
- **History cap** third option changed **200 → 100** to match the owner's stated preference.
- **Pin corner radius** control: Windows uses a 0/4/8/12/16/20 combo; macOS currently a 0…20 slider. Recommend
  switching macOS to the combo to match exactly (or keep the slider styled monochrome — cosmetic).
- **Quick Access card dimensions** use the **actual Windows code** values (width 210, clamp [150,280]), not the
  stale design-doc values (236 / [132,280]).
- All Part 3.B items are "verify" — if macOS turns out already-correct, note it and move on; don't force a fix
  where there's no bug.
