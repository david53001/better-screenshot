# Changelog

All notable changes to BetterScreenshot. Versions are git tags; releases are published on [GitHub](../../releases).

## v3.0.0 — 2026-09-26 · Editor & recording overhaul, video editor, guided tours

Design: `docs/superpowers/specs/2026-09-24-betterscreenshot-editor-recording-v3-design.md`; Windows
port notes: `docs/MAC-TO-WINDOWS-PARITY-v3.md`.

### Editor
- **Options live in a right-side panel** with labelled sections (Styles, Colour, Stroke, Font,
  Background, Effects, Opacity, Arrange) that follow the tool or selection; hide/show with ⌥⌘I. A hint
  line under the canvas explains the current tool in one sentence.
- **Style changes apply to the selected objects** (any kind), one undo step each, and still become the
  default for new objects. Every object has an **Opacity** slider; the Colour section keeps your last
  6 custom colours and has a **Pick from Screen** eyedropper.
- **Zoom:** pinch, ⌘-scroll, ⌘+ / ⌘−, ⌘0 (fit), ⌘1 (100%), up to 800%, with a "Fit · 57%" menu in
  the bottom bar. **Single-key tools:** V A L R F O T N H B P S X C, Esc = Select.
- **Text:** drag a corner of a selected text to scale the whole thing (font, box and outline
  together); side handles still set the box width. **Background** is None / Solid / Auto with any
  colour, Padding and Corners — and you see it while typing. **B I U S**, an **outline** with colour
  and width, a soft **shadow**, and one-click **styles**: Label, Callout, Note, Code, Title, Subtle.
  Older saved styles keep their look (the old "contrasting box" becomes Auto).
- **Blur / pixelate strength** is adjustable live (blur radius 2–40 px, pixel size 4–48 px) for new
  and selected redactions; a **Blur / Pixelate / Black-out** switch converts a selected redaction in
  place (Black-out, key X, is a solid black box that can't be reversed). Pixelate now shows a proper
  mosaic and strong blurs no longer streak at the edges.
- **Highlighter** tool (H): a translucent marker that keeps text readable, with its own remembered
  colour, width and opacity; hold ⇧ for a straight line.
- **Spotlight** tool (S): dims everything outside one or more rectangles (⌥ for ellipses), with an
  adjustable dim amount.

### Recording
- **Record strip redesigned:** labelled Full Screen / Area / Window buttons and **Microphone, System
  audio, Camera and Cursor** menus replace the unlabelled icons, with a hint line explaining whatever
  you hover. Pick which **microphone** and **camera** to use (built-in, AirPods, USB, iPhone); a live
  **level meter** shows the mic working before you start. System audio can be All apps or All apps
  except BetterScreenshot; the mouse pointer can be hidden. Settings → Recording uses the same menus.
- **Expanded recording pill:** mute the **microphone** or **system sound** mid-recording (the video keeps
  a silent, in-sync track), show/hide the camera bubble, **Switch window… / Switch area…** without
  stopping (other shapes are letterboxed), **Restart** and **Discard** (confirm with a second click —
  no dialog steals focus), Pause, Stop. A chevron collapses it; position and state are remembered.
- **Video editor** (the card's **Edit video** button, or History → **Edit Video…**): split at the
  playhead (S / ⌘B), delete segments (⌫), drag segment edges, undo/redo, zoomable filmstrip timeline,
  Space / ← → / I / O; per-segment **speed** (1×, 1.5×, 2×, 4×) and **mute**; **Export as GIF**.
  Cuts are frame-exact: a plain start/end trim stays instant and lossless, anything else is re-encoded
  with a progress bar (~14 s per minute of 1080p60 on an M3). Recordings now carry a keyframe every
  0.5 s so lossless trims land closer to the chosen frame.

### Fixed
- A moved or resized blur/pixelate box now redacts what's under it — it used to keep showing the
  original area's blur, or stretch it.
- Closing the trim/edit window with Cancel no longer loses the recording's Quick Access card — it comes
  back (showing the edited video after Replace Original; after Save as Copy both cards show).
- After pausing while the screen wasn't changing, the video could run ~1 s ahead of the audio.
- Window recordings had no system audio from apps that play sound in helper processes (browsers,
  Electron apps) — window recordings now take system audio from the whole display's audio.
- Dropdown fields in Settings (e.g. the Pin corner-radius menu) drew as bare text with two chevrons.
- The annotation editor opened in the bottom-left corner of the screen. Every window (Annotate, Edit
  Video, History, Settings, Welcome) now opens exactly centred on the screen you're using, and Annotate,
  Edit Video and History reopen the way you last closed them — same size, covering the whole screen, or
  in full screen.

### Guided tours (Part 7) — new users only, and only if they say yes
Design: spec §14 + §14.9 (`docs/superpowers/specs/2026-09-24-betterscreenshot-editor-recording-v3-design.md`);
Windows-port notes: `docs/MAC-TO-WINDOWS-PARITY-v3.md` Part 7; snapshots in `docs/reviews/2026-09-25-tours/`.
- **Existing users are never prompted.** On the first launch of this version the app decides once whether
  you're new — any saved setting, anything in `~/Library/Application Support/BetterScreenshot/`, or Screen
  Recording already granted means *existing* — and stores it (`tourAudience`). Existing users never see the
  question or an automatic tour, not after later updates either.
- **New users are asked once**, on the Welcome window's last page: "Want a quick tour?" — **Show Me Around**
  turns on first-use tours; **No Thanks** (or closing the window) keeps them off for good.
- **Interactive tours on the real UI:** a red outline around the real control and a red tag with a leader
  line (Return = Next, Esc = Skip tour); clicks go straight through to the app, and "Try" steps finish when
  you actually do the thing. Tours: Welcome → Quick Access card → Editor (plus Text, Blur/Pixelate,
  Highlighter, Spotlight the first time you use them) · First recording (every choice on the record strip)
  → recording pill · Video editor · Settings · History.
- **ⓘ button** on the editor, video editor, Settings, History windows and the record strip: Replay Tour and
  that window's Keyboard Shortcuts. Menu bar → **Help & Tours** (take/replay any tour, Reset All Tours);
  Settings → Startup → **Tours & tips** (turn first-use tours on or off).
- Tour tags never appear in your screenshots or screen recordings (including Capture Window on a window
  showing a tag, and tags that appear mid-recording).
- While a tour explains the Quick Access card it stays up (no auto-dismiss). Settings: Startup and Pin to
  Screen swapped columns to keep them even.
- **Polished after an independent review** (`docs/reviews/2026-09-26-tours-review.md`, 6/10 before;
  after-shots in `docs/reviews/2026-09-26-tours-fixes/`):
  - Shorter tours: the first screenshot's chain is 12 tags instead of 16, First recording 6 steps instead
    of 11, and the tour over your first recording 5 instead of 10 — it no longer asks you to mute the mic.
  - Easier to read: a deeper red (#C62D22) and brighter secondary text, so every label passes WCAG AA;
    "Skip Step" / "Skip Tour", and no "Skip Tour" next to "Done".
  - "n of m" counts only the steps you'll actually see (no more 1 → 3 jumps).
  - Tags for big areas (the editor canvas, the video preview, the Settings cards) sit inside the area's
    corner instead of over the side panel or timeline; side tags slide off nearby controls and text;
    hovering a recording-pill button no longer makes its tag jump; leader lines avoid other controls.
  - A step never waits for something you skipped ("Resize your text" needs a text, "Delete a part" a split).
  - Tags outline exactly what they describe (the three capture shortcuts; Copy, Edit and Save; a Settings
    label with its ⓘ); corrected text (the mic meter, where Save puts screenshots, History's actions); a
    cleared shortcut reads "(not set)"; typographic apostrophes.
  - Esc and Return reach the Settings shortcut recorder while it's recording; the Welcome window closes when
    its tour ends; Reset All Tours says how to turn tours back on.

### UI polish — fixes from the independent UI review
Review: `docs/reviews/2026-09-25-ui-review.md` (5/10 before these fixes); after-screenshots in
`docs/reviews/2026-09-25-ui-fixes/`.
- **Annotation editor:** Undo, Redo and the panel toggle are visible in the title bar again (they had
  zero width), and the editor stays dark in Light mode. Screenshots open at their real size — Fit never
  enlarges past 100% — in a window sized to match. The inspector is tidier: Front/Back/Delete sit in a
  footer that's always reachable, the Text panel is about 20% shorter, colour wells are labelled,
  sliders line up, and Front/Back have distinct arrow icons. Turning on a text Outline picks a colour
  that contrasts with the text; handles no longer cover the letters; a dashed frame shows while typing;
  the default red is the Red swatch; the bottom bar is slimmer.
- **Video editor:** a real time ruler above the filmstrip (round times in the edit's own clock, never
  overlapping), and zoomed-in filmstrips no longer repeat frames. A missing or unreadable file shows a
  clear centred error with Show in Finder. Export progress has its own slot so nothing moves; the footer
  checkbox is now "Mute whole video"; Replace Original stays disabled until there's an edit to save.
- **Record strip:** a darker, readable HUD over any window; the mic level meter sits beside the
  Microphone label (no empty gap); equal columns; the chosen Format/FPS is clearly highlighted; the
  hovered control's label lights up with its hint; in GIF mode the hint explains why audio is off.
- **Recording pill:** keeps its width when asking "Restart?"/"Discard?"; shows "Paused"; hovering any
  control explains it instantly; says "System audio"; camera off no longer looks muted; muted chips stay
  visible over red content. **Countdown:** the number is centred, with "Click to start now".
- **Quick Access card:** shows each capture once, edge to edge (it was drawing the image twice, hiding
  the contrast tint), so its buttons stay readable on busy images; recording cards show "0:42 · MP4".
- **Settings:** every ⓘ explanation shows in full; the layout is balanced with a new "In the video"
  card; "Mouse cursor: Shown/Hidden" and "Show recording controls in the video" use the record strip's
  words; "Capture Full Screen" everywhere.
- **History:** action buttons never truncate; items show their size or length; recordings get a play
  badge; the empty window explains how to take a first screenshot; Clear All moved into a ⋯ menu.
- **Welcome:** the shortcut list is an aligned grid of *your* shortcuts (including Capture Text) in ⇧⌘
  order, and the window no longer changes size between steps.
- **Overlays:** toasts, the area-selection size label and the pin's close button share one dark style
  and stay readable over light content; long window-picker titles are cut to fit; every menu-bar menu
  item has an icon.

## v3.0.0, first half (built 2026-09-24) · Text boxes & fonts, stop button, recording trim

Shipped in the same v3.0.0 release as the section above.

### Added
- **Trim recordings.** A ✂ button on a finished MP4 recording's Quick Access card (and **Trim…** in
  the History window) opens a trim window with QuickTime-style yellow handles (AVKit's native trim
  mode). **Save as Copy** writes `<name> (trimmed).mp4` next to the original and shows it as a new
  card; **Replace Original** swaps the file in place atomically and returns to the player showing
  the trimmed result (**Adjust Trim** trims again). **Mute audio** drops the audio tracks. Exports
  are passthrough (no re-encode), so they're fast and lossless. GIF recordings can't be trimmed.
- **Floating recording controls.** While recording (from the countdown on), a draggable pill shows
  the timer, **Pause/Resume**, and **Stop**. Settings → Recording → **Show stop button in recording**
  (off by default) decides whether the pill appears in the video; off, it is excluded from the
  capture. Window recordings never include it.
- **Text tool: fonts and text boxes.** A second inspector row for the Text tool: font menu (System,
  Rounded, Serif, Mono, then every installed font), size (12–96), bold, italic, and alignment.
  Drag with the Text tool to make a fixed-width text box; drag its side handles to change the width.
  Click existing text with the Text tool (or double-click it with Select) to edit it in place.
  Changing the style while text is selected (Text tool) restyles it. The font settings persist as
  the editor's sticky default, like colour and size.

### Fixed
- **Typing past one line in the Text tool hid the line above.** The inline editor was a fixed
  200×28 field that scrolled earlier lines out of view once text wrapped. It now grows with the
  text (right to the canvas edge, then down), and the committed text wraps exactly as shown.
  Return commits, ⇧Return / ⌥Return insert a newline, Esc or clicking away commits.
- Text still being typed was left out when you pressed Copy / Save / Stack; it is now committed first.

## v2.11.0 — 2026-09-10 · Capture Text keeps paragraphs together

### Improved
- **Capture Text (⌘⇧7) now reflows wrapped lines into paragraphs.** Vision returns one result per
  *visual* line, and the app used to join them with newlines — so a bullet that wrapped over five
  lines on a slide pasted as five lines. `TextReflow` (CaptureKit, pure + unit-tested) rebuilds the
  paragraphs from the line boxes: a line continues the one above it only when it sits in the same
  column, the spacing matches the block's rhythm (no blank-line gap, pitch jump, or font-size
  change), it doesn't start with a list marker (`•`, `-`, `1.`, `a)`), and the previous line
  actually wrapped — its width plus the next line's first word would overflow the column edge. That
  last test is what keeps code screenshots line-per-line: a short line had room for the next word,
  so it ended on purpose. Also: lines are sorted top-to-bottom (Vision's order isn't guaranteed),
  side-by-side columns stay separate, fragments Vision splits off one row are glued back, hyphenated
  breaks join (`portfo-` + `lio`), and look-alike bullet glyphs (`·`, `●`, `◦`) normalize to `•`.
  Known limit: the longest line of a code block still merges with its follower, since nothing in the
  column proves it stopped short.

### Docs
- README gains an **Update** section: re-run the install one-liner (it quits, replaces, and relaunches
  the app; settings and permissions carry over).

## v2.10.0 — 2026-09-08 · Faster Capture Text, runs on Intel Macs too

### Changed
- **The release build is now a universal binary** (Apple Silicon + Intel) — earlier releases were
  arm64-only and would not launch on Intel Macs. `scripts/build-app.sh release universal` builds each
  slice with its own target triple and joins them with `lipo` (SwiftPM's own multi-arch mode needs
  Xcode's xcbuild, which the Command Line Tools lack); `scripts/package-release.sh` wraps that and
  zips the bundle with `ditto` so the code signature survives.
- **One-line install.** `scripts/install.sh` (README → Install) downloads the latest release, installs
  it to `/Applications`, strips the quarantine flag, and launches it. The README's manual steps now
  cover the macOS 15+ Gatekeeper flow, where **Open Anyway** in System Settings is the only
  click-through for an unnotarized app.

### Improved
- **Capture Text is faster and cleaner.** Vision's text model unloads after ~20s idle and reloading
  it cost 0.5–1s on every "first" capture — most of the delay the owner was seeing. The model is now
  warmed the moment the Capture Text selection overlay appears, so it loads while you drag; on an
  M3 a real request right after the warm-up runs at ~370ms instead of 540–1160ms cold. Language
  detection was replaced by the user's own system languages filtered to what Vision supports (this
  machine resolves to English + Romanian; the fallback is English), which stops CJK punctuation
  leaking into Latin-script results ("Open.。"). Captures below 2× pixel density (non-retina or
  stretched displays) are upscaled before recognition — measured at 1× Vision fragmented single
  lines into pieces and ran ~60% slower.

## v2.9.0 — 2026-08-27 · Readable overlay buttons on any screenshot

### Fixed
- **The Quick Access buttons stay readable over multi-colored screenshots.** The post-capture card
  chose white or near-black glyphs from the *mean* brightness of the image's bottom strip — a
  statistic that says nothing useful about a strip containing both. A lock-screen capture (near-black
  starfield behind a large white headline sitting exactly at button height) averaged out "dark", drew
  white glyphs, and placed them straight on top of the white headline. The card now measures the
  darkest and brightest pixels actually behind the button row and solves for the scrim strength that
  guarantees a WCAG 4.5:1 contrast ratio against **both**, choosing whichever glyph tone needs the
  gentler scrim. Screenshots that are already dark behind the row keep the light, barely-there scrim
  they had before. Three further faults in the same code path went with it: the scrim faded to ~27%
  opacity exactly where the glyphs sit (it now holds its computed strength flat across the row), the
  sampler read the image's own bottom strip instead of the pixels the aspect-fill crop actually shows
  there, and luminance was computed on gamma-encoded bytes rather than linear light.

### Changed
- **The Quick Access card's Pin button is gone.** Pin to Screen is unchanged everywhere else — the
  menu bar's **Pin from Clipboard** and the History window's **Pin** action both still work.

## v2.8.1 — 2026-08-06 · Menu-bar icon restored (new bundle identifier)

### Fixed
- **The menu-bar icon is back.** On macOS 26 the icon had vanished entirely: ControlCenter — which
  hosts every third-party menu-bar item on macOS 26 and enforces the System Settings → Menu Bar
  "Allow in the Menu Bar" list — held a stuck, undeletable blocked-host record keyed to the app's
  bundle id, and silently blocked the item on every launch. No supported control clears it (the
  Settings toggle for the app was dead, "Reset Control Centre…" doesn't touch it). The app's bundle
  identifier changed `com.betterscreenshot.app` → `com.betterscreenshot.mac` to escape the record;
  settings were migrated to the new preferences domain automatically. **One-time cost:** macOS ties
  the Screen Recording permission to the bundle id, so it must be granted once more via the app's
  onboarding prompt. Full forensics: `docs/INVESTIGATION-2026-08-06-menubar-icon-not-placed.md`.

## v2.8.0 — 2026-08-06 · Focus hand-back + History drag & multi-select

### Added
- **Focus returns to your app after a capture.** Taking a screenshot (⌘⇧4 area, fullscreen, window)
  or running Capture Text (⌘⇧7) now hands keyboard focus back to whatever app was frontmost when you
  started — including when you cancel the selection with Escape. Previously BetterScreenshot kept
  focus and you had to click your window again before typing. If you start the capture from one of
  BetterScreenshot's own windows (History, the editor), there's nothing to hand back to, so focus is
  simply left alone. Screen recording does not restore focus — only screenshots do.
- **Drag captures out of History.** Drag any thumbnail in the History window straight into Finder, a
  chat, or a terminal. The dragged file is the one on disk — the app's stored copy for screenshots,
  your saved file for recordings — never a temporary copy that the cache sweep deletes.
- **Multi-select in History.** ⇧-click selects a contiguous range, ⌘-click toggles individual items.
  Copy, Delete and Show in Finder act on the whole selection, and dragging a multi-selection drags
  every file at once. Annotate and Pin remain single-selection. Deleting more than one item now asks
  for confirmation first; deleting a single item is still immediate, as before.

## v2.7.0 — 2026-08-01 · Temp-file retention (replaces v2.6.0's history retention)

v2.6.0 put the retention timer on the wrong thing. It expired entries in the capture
**History**, when what needed a timer was the **temporary files** the app leaves in the
system temp folder. This release moves the timer where it belongs and puts History back
the way it was.

### Added
- **"Keep cached files for" (Settings → Capture).** When you drag a capture out of the
  Quick Access card, or copy one so that a file path lands on the clipboard, the app writes
  a temporary PNG into a `BetterScreenshot-<UUID>` folder inside the system temp directory
  (`$TMPDIR`, e.g. `/var/folders/8h/…/T/BetterScreenshot-4C7446B4-…/Screenshot 2026-08-01
  at 18.25.57.png`). This setting controls how long that file survives. The stops are
  **10s · 30s · 5m · 10m · 30m · 1h · ∞**, with ∞ meaning the files are left for macOS to
  clear on its own. Default is **5m**, which matches what earlier versions did.

### Fixed
- **Temp folders no longer leak on quit.** Cleanup used to be a per-file timer scheduled
  inside the running app, so quitting before it fired orphaned that folder permanently —
  they accumulated indefinitely. Cleanup is now a sweep that also runs at launch, so folders
  left behind by earlier runs (including by older versions) are cleared.

### Removed
- **The "Keep in cache for" History setting added in v2.6.0 is gone.** Capture History no
  longer expires by time at all: it holds the newest captures up to the "Keep at most" limit
  (10 / 50 / 100) and nothing is removed for being old. This also drops the fixed 30-day
  history prune that predated v2.6.0.

## v2.6.1 — 2026-08-01 · ∞ instead of "Never"

### Changed
- **Both retention sliders now show ∞ where they used to read "Never".** This affects
  Settings → Quick Access Overlay → "Auto-dismiss after" and Settings → History →
  "Keep in cache for". The meaning is unchanged — ∞ is the last stop on each slider and
  means the card stays until you dismiss it / the capture is kept until the "Keep at most"
  count limit pushes it out. The stored value for that stop is still `0`, so no setting is
  reset by this update. The Windows port's auto-dismiss slider shows ∞ to match.

## v2.6.0 — 2026-08-01 · Cache Retention

### Added
- **Choose how long a screenshot stays cached.** A new "Keep in cache for" slider
  (Settings → History) controls how long a capture is kept in the app's local cache at
  `~/Library/Application Support/BetterScreenshot/History/` before its cached copy and
  thumbnail are deleted. The stops are **10s · 30s · 5m · 10m · 30m · 1h · Never**, where
  Never means the capture is kept until the "Keep at most" count limit pushes it out.
  Default is **30m**.

  Only the app's own cached copy is deleted — a file you saved with the Save button, or an
  image you already copied to the clipboard, is never touched, and a recording's saved video
  file is never deleted (recordings are stored by reference).

  Because the shortest setting is 10 seconds, the app now sweeps the cache every 5 seconds
  rather than only pruning at launch, so a capture disappears on time even if you take no
  further screenshots.

### Changed
- **The fixed 30-day history prune is gone**, replaced by the setting above. Any capture
  older than your chosen window is removed the first time the new version runs — with the
  default of 30 minutes, an existing cache is largely cleared on first launch.

## v2.5.0 — 2026-08-01 · Hold Duration + Windows-Parity Backport

Adds a much longer hold duration for the post-capture card, and brings the macOS app up
to visual + behavioral parity with the Windows port in three areas (settings UI, the
post-capture card, and a batch of editor/capture fixes). Parity design in
`docs/WINDOWS-TO-MAC-PARITY.md`; implementation plans in
`docs/superpowers/plans/2026-07-04-parity-part{1,2,3}-*.md`.

### Changed
- **Settings redesigned (monochrome "JVoice" theme).** The Settings window is rebuilt as
  a pure-black, 960-pt-wide, single-scroll **three-column masonry of titled cards**
  (Capture · Quick Access Overlay · Pin to Screen · History · Startup · Save Location ·
  Recording, plus a full-width Keyboard Shortcuts card), replacing the previous three-tab
  layout. New custom controls: macOS-style toggle switches (white track / black knob when
  on), joined segmented controls, and a per-setting **ⓘ info button** whose hover tooltip
  gives a plain-language explanation and an example. The window is always dark (independent
  of the system light/dark appearance). Every change still applies instantly.
- **Quick Access card redesigned (full-bleed).** After a capture, the floating card is now
  the screenshot itself — edge-to-edge and rounded — with the action buttons floating over
  the bottom of the image on a subtle tone-matched gradient. The button glyphs automatically
  flip black/white to stay legible against whatever is behind them. Cards now follow each
  capture's aspect ratio, and the stack packs them by their actual heights.
- **History cap options are now 10 / 50 / 100** (was 10 / 50 / 200); a stored value of 200
  is migrated to 100.

### Added
- **Choose how long a capture is held on screen.** A new "Auto-dismiss after" slider
  (Settings → Quick Access Overlay) closes the post-capture Quick Access card after a
  chosen delay. The slider stops at **30 s · 1 m · 2 m · 5 m · 10 m · 15 m · 30 m ·
  Never**, and the countdown pauses while the pointer is over the card. Default is
  **Never** (the card stays until you dismiss it). A delay saved by an older build
  (for example the previous 6-second default) is moved to the nearest stop the first
  time the settings are loaded.
- **Play a sound on capture.** New Settings → Capture toggle (on by default) that plays a
  short system sound when you take a screenshot.
- **Optional text-background chip in the editor.** A new inspector toggle draws a rounded,
  auto-contrasting background behind a text annotation (dark chip behind light text, light
  behind dark). Off by default; remembered with your other sticky editor defaults.

### Fixed
- **Annotations can no longer be dragged off the image** in the editor — a moved
  shape / text / counter is kept inside the image bounds so it isn't clipped on export.
- **Area selection is clamped to the screen**, so a fast drag past the edge can't select or
  capture beyond the display.

## v2.4.0 — 2026-06-25 · Recording Controls + Editor Defaults

### Added
- **Countdown before recording.** Optional 3 / 5 / 10-second on-screen
  countdown before a recording starts (Settings → Recording). Click the
  countdown to start immediately; ⌘⇧5 cancels.
- **Record Window.** A new "Record Window…" button on the record strip: hover
  to highlight any window, then click to record just that window.
- **Pause / Resume.** Pause a running recording and resume with no gap in the
  saved file. Available from the menu bar and as a bindable shortcut
  (Settings → Shortcuts → "Pause/Resume Recording"); the menu-bar timer
  freezes and shows "Paused" while paused.
- **Sticky annotation defaults.** The annotation editor now remembers the
  stroke/text **color** and **size** (S/M/L) you last used and reopens with
  them, instead of always starting on red / medium. Your choice persists across
  captures and app restarts (stored locally in `UserDefaults`). The active tool
  still defaults to Arrow.
- **"Stack" button in the editor (replaces "Pin").** The editor's bottom action
  bar now has a **Stack** button that drops the finished, annotated screenshot
  into the bottom-right Quick Access stack alongside your other captures — with
  the usual Copy / Edit / Pin / Save / drag actions — records it to History, then
  closes the editor. Pin-to-Screen is unchanged and still available from the
  Quick Access thumbnail's own Pin button.

## v2.3.2 — 2026-06-11 · History Clear All

### Added
- **Clear All in the History window.** The history browser now has a
  **Clear All…** button (next to the item count) that wipes every remembered
  capture after a confirmation. Bulk-clearing was previously only reachable from
  Settings → General → History. As before, saved recording files on disk are
  not deleted.

## v2.3.1 — 2026-06-08 · UI fixes

### Fixed
- **Selection dimensions label no longer clips off-screen.** When you drag an
  area selection near the top of a display, the `W × H` label now tucks just
  inside the selection's top edge instead of drawing past the screen edge where
  it was cut off.
- **Quick Access overlay buttons are evenly spaced.** The post-capture button
  row now sizes to its buttons and centers under the thumbnail, so the 4-button
  (recording) and 5-button (screenshot) variants are both balanced — the old
  fixed-width row left the 5-button screenshot variant cramped.

## v2.3.0 — 2026-06-05 · Capture history

- **Capture History.** Every screenshot (including copy-only captures that used
  to vanish with the clipboard) and every finished recording is remembered
  locally — browse them in the new **History…** window from the menu bar:
  thumbnail grid, copy / annotate / pin / show-in-Finder / delete per item,
  double-click to edit (screenshots) or play (recordings).
- **Restore Recently Closed.** Accidentally ✕-closed (or stack-evicted) Quick
  Access thumbnails can be brought back from the menu bar; deliberate actions
  (save, annotate, pin, drag-out) don't count as accidental.
- **Settings → General → History:** keep-history toggle, 10/50/200 item cap,
  and Clear History. Retention also prunes entries older than 30 days. All
  local — history lives in `~/Library/Application Support/BetterScreenshot/History/`.
- Both new commands are bindable hotkeys (unbound by default) in
  Settings → Shortcuts.

## v2.2.0 — 2026-06-05 · Reliability + infra

### Fixed
- **Screenshot save failures are now visible.** A HUD toast appears when a save fails
  (e.g. disk full, permission denied); if the configured save folder is missing the app
  creates it automatically — previously a moved or deleted folder lost the capture silently.
- **Capture / Capture Text failures surface a HUD** instead of failing silently.
- **Recordings: save folder is auto-created** on start. Denied microphone permission now
  records without a mic track and shows a HUD explaining this — previously it wrote a
  silent empty audio track.
- **Fixed a race between recording stop and in-flight frames** that could crash the
  AVAssetWriter.
- **App relaunch (onboarding)** no longer breaks when the install path contains
  quotes or other shell-special characters.

### Improved
- **Editor performance.** Dragging and annotating large screenshots is much faster;
  the canvas no longer re-flattens the full-resolution image on every mouse move.
- **Editor: counter badge** now centers on the click point rather than offset from it.
- **Editor keyboard focus.** Delete and `[` / `]` keys work immediately without
  clicking the canvas first; focus returns to the canvas automatically after typing text.
- **VoiceOver labels** added to all image-only buttons: Quick Access overlay, record
  strip toggles, editor toolbar, and pin close button.
- **Quick Access overlay + HUD** now appear over full-screen apps. Copy shows feedback
  from every surface. Overlay buttons are equal-width on both card types.

### Infrastructure
- **Tests:** blur/pixelate redaction is now verified to actually obscure content;
  suite total 87 tests across all packages.
- **CI:** GitHub Actions workflow + `scripts/test.sh` run all four suites on every
  push and pull request.
- **Docs:** build instructions corrected (SwiftPM, not XcodeGen).

## v2.1-recording-feedback — 2026-06-05

- **Recording thumbnail.** Finished recordings now show the same bottom-corner
  Quick Access thumbnail screenshots get — blue-tinted so it reads as a recording —
  with Copy file / Open / Show in Finder buttons and drag-out of the saved file.
  Recording and screenshot overlays share one stack, so they never overlap.
- **Record strip toggle feedback.** The mic, system-audio, and camera buttons now
  turn accent-blue while enabled (like the MP4/GIF selector), so you can see at a
  glance what the recording will include.

## v2.0-recording — 2026-06-04

- **Screen recording (P2).** ⌘⇧5 is a smart toggle: press to open the record strip
  (full screen or drag an area; MP4/GIF, mic, system audio, camera toggles), press
  again to stop. Menu bar shows a red stop button with an elapsed timer.
- **MP4 + GIF output** — H.264 at 30/60 fps; GIF recordings convert automatically
  (10 fps, ≤960 px) and fall back to MP4 if conversion fails.
- **Audio** — system audio (ScreenCaptureKit) and microphone (separate track).
- **Camera bubble** — circular live webcam overlay, drag to move, two sizes.
- **Click highlights** (no extra permission) and **keystroke display**
  (Accessibility-gated, off by default).
- New Settings → Recording tab; "Start/Stop Recording" is rebindable in Shortcuts.
- Native macOS ⌘⇧5 (screenshot toolbar) is shadowed while the app runs, like ⌘⇧4.

## v1.4-shortcuts — 2026-06-04

- **Fixed: the Settings window now opens.** macOS 14 silently broke the private
  selector the menu item relied on; the app now owns its settings window directly.
- **Customizable shortcuts.** New Settings → Shortcuts tab: click a shortcut well,
  type a new combo, it applies immediately and persists. Conflicts inside the app
  and combos owned by other apps/macOS are refused with an explanation.
- **New defaults:** Capture Window moved ⌘⇧5 → **⌘⇧8**; **⌘⇧5 is now reserved for
  Start/Stop Recording** (next release). Pin from Clipboard can be given a shortcut
  (unbound by default). Menu-bar items now display their current shortcuts.

## v1.3 — 2026-06-04 · OCR, Pin to Screen, Quick Access stack

The P3 release ([spec](docs/superpowers/specs/2026-06-04-betterscreenshot-p3-ocr-pin-design.md) · [plan](docs/superpowers/plans/2026-06-04-betterscreenshot-p3-ocr-pin.md)).

### Added
- **Capture Text (⌘⇧7)** — drag a region and the recognized text lands on the clipboard, entirely on-device (Vision OCR, automatic language detection). If the region contains a **QR code**, its payload is copied instead (QR wins over text). A toast confirms: "Text copied — N characters" / "QR code copied" / "No text found". Also available from the menu bar.
- **Pin to Screen** — float any capture as an always-on-top panel that follows you across Spaces and never steals focus. Drag to move; resize from the bottom-right corner or by scrolling (aspect-locked, 0.25×–3×); double-click to copy; hover for the ✕ close button; right-click for Copy / Save / Close. Entry points: the Quick Access overlay's new pin button, a **Pin** button in the annotation editor (the editor stays open), and menu bar → **Pin from Clipboard**.
- **Quick Access stack** — new captures no longer replace the post-capture thumbnail: up to **3** overlays stack at the configured corner, newest at the corner slot. A 4th capture evicts the oldest; dismissing any overlay slides the rest together.
- **Pin appearance settings** — corner radius (0–20 pt) and shadow toggle for newly created pins.
- **Launch at login** — registered once by default via `SMAppService`; toggle in Settings (stays in sync with System Settings → Login Items).
- New OverlayKit test suite (TestKit); recognition logic is covered by real headless Vision OCR/QR end-to-end tests. 66 automated tests across the three packages.

### Fixed
- Pressing a second capture hotkey (e.g. ⌘⇧7 while a ⌘⇧4 selection is open) now cancels the open selection instead of stacking orphaned overlays.
- Pin double-click registers on mouse-up, so a 1-pixel drift between clicks no longer micro-drags the pin.
- The "Copied" toast for a pin re-resolves its screen at click time, surviving display disconnects.

## v1.2 — 2026-06-04 · Public release polish

- One-button first-run setup for the Screen Recording permission (welcome window drives the whole grant flow and relaunches the app).
- Editor chrome redesign: floating tool pill, adaptive inspector, quiet bottom action bar, title-bar undo/redo; arrow rendering fix; undo/redo keys; marquee multi-select.
- Native macOS ⌘⇧4 is disabled while the app runs (restored on quit) so captures don't double-fire.
- README, MIT license, and repo hygiene for the public GitHub release.

## v1.1 — 2026-06-03 · Stability

- Fixed a crash when the cursor entered the Quick Access overlay; the overlay is now persistent (no auto-dismiss).
- Overlay download button saves to the macOS screenshot folder (`com.apple.screencapture` location); drag-out uses a self-deleting temp file.
- Stable self-signed identity (`scripts/setup-signing.sh`) so the Screen Recording grant persists across rebuilds.
- Guarded the selection overlay against double completion; sized the Quick Access thumbnail correctly.

## v1.0 — 2026-06-03 · Initial release

- **v0.1 capture core**: menu-bar app, global hotkeys (⌘⇧4/5/6), area/window/fullscreen capture via ScreenCaptureKit, save (PNG/JPG) / copy, settings.
- **v0.2 Quick Access overlay**: post-capture floating thumbnail with copy / save / annotate / drag-out.
- **v1.0 annotation editor**: arrows, lines, shapes, text, numbered counters, blur/pixelate redaction, crop, inline text editing, resize handles, object reordering, flatten-to-image export — all TDD'd against a golden-image renderer.
