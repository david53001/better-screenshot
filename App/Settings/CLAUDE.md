# App/Settings — settings store & UI

- `SettingsStore.swift` — `UserDefaults`-backed app settings: hotkey bindings, recording config,
  failed-action tracking, and the **editor sticky default style** (`editorStyle`, persisted under the
  `UserDefaults` key `editorDefaultStyle`). The editor's last-used stroke/text color + size round-trip
  through here and are injected into `EditorKit`'s window controller as `defaultStyle`. The editor's
  **Recent colours** (last 6, newest first) follow the same pattern: `editorRecentColors`, JSON under
  `editorRecentColors`, injected as `recentColors:` and saved from `onRecentColorsChanged`.
- `SettingsView.swift` — SwiftUI settings UI (tabbed: shortcuts, recording, etc.).
- `SettingsWindowController.swift` — hosts the SwiftUI settings view in an AppKit window.

Verify: change a setting in the built app, confirm it persists across relaunch; for the editor default,
confirm a new annotation picks up the last-used color/size.
