import Foundation

/// The Welcome window's "You're all set!" shortcut list, built from the user's live
/// bindings (so a rebinding shows up) and formatted like the menu (⇧⌘4).
public enum HotkeyCheatSheet {
    public struct Row: Equatable {
        public let keys: String
        public let description: String
    }

    /// Menu order, with a plain-language description of each.
    public static let entries: [(action: HotkeyAction, description: String)] = [
        (.captureArea, "Capture an area"),
        (.captureWindow, "Capture a window"),
        (.captureFullscreen, "Capture the full screen"),
        (.captureText, "Copy text from the screen"),
        (.record, "Record the screen"),
    ]

    /// One row per bound entry; unbound actions are left out.
    public static func rows(for bindings: HotkeyBindings) -> [Row] {
        entries.compactMap { entry in
            keys(for: entry.action, in: bindings).map { Row(keys: $0, description: entry.description) }
        }
    }

    /// One action's current combo as shown here and in the menu ("⇧⌘4"); nil when unbound. Also fills
    /// the guided tours' `{shortcut:<action>}` placeholders, so tours show the same keys.
    public static func keys(for action: HotkeyAction, in bindings: HotkeyBindings) -> String? {
        bindings.combo(for: action)?.displayString
    }
}
