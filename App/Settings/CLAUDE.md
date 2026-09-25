# App/Settings — settings store & UI

- `SettingsStore.swift` — `UserDefaults`-backed app settings: hotkey bindings, recording config,
  failed-action tracking, and the **editor sticky default style** (`editorStyle`, persisted under the
  `UserDefaults` key `editorDefaultStyle`). The editor's last-used stroke/text color + size round-trip
  through here and are injected into `EditorKit`'s window controller as `defaultStyle`. The editor's
  **Recent colours** (last 6, newest first) follow the same pattern: `editorRecentColors`, JSON under
  `editorRecentColors`, injected as `recentColors:` and saved from `onRecentColorsChanged`.
- `SettingsView.swift` — SwiftUI settings UI: a three-column card masonry + a full-width Keyboard
  Shortcuts card. Columns: Capture · Quick Access Overlay · Pin to Screen | Recording · Startup |
  In the video · History · Save location — chosen so the columns end at about the same height (check
  with a screenshot after adding a row). The Recording card's `sourceMenus` (Microphone / System audio /
  Camera dropdowns) mirror the record strip's columns and persist the same `RecordingConfig` fields; the
  In the video card's "Mouse cursor" (Shown | Hidden, same words as the strip) is
  `RecordingConfig.showsCursor`.
- `SettingsHelp.swift` — the ⓘ texts (title · explanation · example) for every setting. Shortcut
  examples use Apple's modifier order (⇧⌘4), like `HotkeyCombo.displayString`.
- `Components/InfoTip.swift` — the ⓘ popover. Its card needs a fixed text width plus
  `.fixedSize(horizontal: false, vertical: true)` on each `Text`, or the popover cuts every line to one row.
- `Components/MonoControls.swift` — `MonoComboField` must use `.menuStyle(.button)` + `.buttonStyle(.plain)`
  + `.menuIndicator(.hidden)`; `.borderlessButton` renders it as bare text with a second chevron.
- `SettingsWindowController.swift` — hosts the SwiftUI settings view in an AppKit window.

Verify: change a setting in the built app, confirm it persists across relaunch; for the editor default,
confirm a new annotation picks up the last-used color/size.
