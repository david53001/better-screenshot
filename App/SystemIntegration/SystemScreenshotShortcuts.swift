import Foundation

/// Disables/restores native macOS screenshot shortcuts so they don't fire alongside
/// BetterScreenshot's own hotkeys. Edits the user-level `com.apple.symbolichotkeys`
/// domain (symbolic-hotkey ids 28, 30, 184) and reloads via the private `activateSettings`
/// helper so the change applies without a logout.
enum SystemScreenshotShortcuts {
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let topKey = "AppleSymbolicHotKeys" as CFString
    /// Native shortcuts we shadow: id 28 = "Save picture of screen as a file" (⌘⇧3),
    /// id 30 = "Save picture of selected area as a file" (⌘⇧4), id 184 = "Screenshot
    /// and recording options" (⌘⇧5).
    /// parameters = [ASCII code, virtual key code, modifier mask].
    private static let shadowed: [(id: String, parameters: [Int])] = [
        ("28",  [51, 20, 1_179_648]),  // '3', keycode 20, ⌘⇧
        ("30",  [52, 21, 1_179_648]),  // '4', keycode 21, ⌘⇧
        ("184", [53, 23, 1_179_648]),  // '5', keycode 23, ⌘⇧
    ]

    /// Disable the native shortcuts by writing standard bindings with `enabled = 0`.
    static func disableNativeShortcuts() {
        var hotKeys = currentHotKeys()
        for entry in shadowed {
            hotKeys[entry.id] = [
                "enabled": 0,
                "value": ["parameters": entry.parameters, "type": "standard"],
            ]
        }
        write(hotKeys)
        reload()
    }

    /// Restore by removing our entries, reverting to macOS defaults (enabled).
    /// Safe across crashes: a run killed before this simply re-disables next launch.
    static func restoreNativeShortcuts() {
        var hotKeys = currentHotKeys()
        let present = shadowed.filter { hotKeys[$0.id] != nil }
        guard !present.isEmpty else { return }
        for entry in present { hotKeys.removeValue(forKey: entry.id) }
        write(hotKeys)
        reload()
    }

    // MARK: - Preferences I/O

    private static func currentHotKeys() -> [String: Any] {
        let value = CFPreferencesCopyValue(topKey, domain,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return (value as? [String: Any]) ?? [:]
    }

    private static func write(_ hotKeys: [String: Any]) {
        CFPreferencesSetValue(topKey, hotKeys as CFDictionary, domain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    /// Reload symbolic hotkeys without a logout via the private SystemAdministration helper.
    private static func reload() {
        let helper = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        guard FileManager.default.isExecutableFile(atPath: helper) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helper)
        process.arguments = ["-u"]
        try? process.run()
        process.waitUntilExit()
    }
}
