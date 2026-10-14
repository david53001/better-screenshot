import Foundation

/// The user's action → hotkey map. Pure model; persisted as a string dictionary
/// (action rawValue → "keyCode,modifiers" or "unbound") following CaptureSettings
/// conventions. A missing key means "never customized → use the default".
public struct HotkeyBindings: Equatable {
    private var map: [HotkeyAction: HotkeyCombo]
    /// Actions the user explicitly unbound (persisted as "unbound" so the choice
    /// survives upgrades; a key missing entirely means "use the default").
    private var cleared: Set<HotkeyAction>

    public init(_ map: [HotkeyAction: HotkeyCombo] = [:]) {
        self.map = map
        self.cleared = []
    }

    public static let defaults: HotkeyBindings = {
        var m: [HotkeyAction: HotkeyCombo] = [:]
        for action in HotkeyAction.allCases { m[action] = action.defaultCombo }
        return HotkeyBindings(m)
    }()

    public func combo(for action: HotkeyAction) -> HotkeyCombo? { map[action] }

    public mutating func set(_ combo: HotkeyCombo, for action: HotkeyAction) {
        map[action] = combo
        cleared.remove(action)
    }

    public mutating func clear(_ action: HotkeyAction) {
        map[action] = nil
        cleared.insert(action)
    }

    /// The *other* action already bound to `combo`, if any.
    public func conflictingAction(for combo: HotkeyCombo,
                                  excluding action: HotkeyAction) -> HotkeyAction? {
        map.first { $0.key != action && $0.value == combo }?.key
    }

    /// One-time upgrade (2026-10-14): full screen moved to ⌘⇧3 (was ⌘⇧6), and the app now takes
    /// ⌘⇧3 from macOS. Saved bindings store every combo, so older installs would keep their old
    /// key and ⌘⇧3 would do nothing. Moves full screen to ⌘⇧3 unless it was unbound or another
    /// action already has ⌘⇧3. Returns whether it changed.
    @discardableResult
    public mutating func moveFullscreenToCommandShift3() -> Bool {
        let new = HotkeyCombo(keyCode: 20, modifiers: HotkeyCombo.commandMask | HotkeyCombo.shiftMask)
        guard let current = map[.captureFullscreen], current != new,
              conflictingAction(for: new, excluding: .captureFullscreen) == nil else { return false }
        set(new, for: .captureFullscreen)
        return true
    }

    /// All bound pairs in stable HotkeyAction.allCases order.
    public var bound: [(action: HotkeyAction, combo: HotkeyCombo)] {
        HotkeyAction.allCases.compactMap { a in map[a].map { (a, $0) } }
    }

    // MARK: - Persistence

    public var dictionary: [String: String] {
        var d: [String: String] = [:]
        for (action, combo) in map {
            d[action.rawValue] = "\(combo.keyCode),\(combo.modifiers)"
        }
        for action in cleared { d[action.rawValue] = "unbound" }
        return d
    }

    public init(dictionary: [String: String]) {
        var m: [HotkeyAction: HotkeyCombo] = [:]
        var c: Set<HotkeyAction> = []
        for (key, value) in dictionary {
            guard let action = HotkeyAction(rawValue: key) else { continue }
            if value == "unbound" { c.insert(action); continue }
            let parts = value.split(separator: ",")
            guard parts.count == 2,
                  let kc = UInt32(parts[0]), let mods = UInt32(parts[1]) else { continue }
            m[action] = HotkeyCombo(keyCode: kc, modifiers: mods)
        }
        // Actions absent from the stored dict were never customized → defaults.
        // (This is how pre-record-era bindings pick up ⌘⇧5 on upgrade.)
        // NOTE: v1.4 stored clears as absent keys, indistinguishable from "never
        // set" — those bindings get a one-time restore to defaults on first launch
        // after upgrading. Accepted tradeoff for this personal tool.
        for action in HotkeyAction.allCases where m[action] == nil && !c.contains(action) {
            m[action] = action.defaultCombo
        }
        self.map = m
        self.cleared = c
    }
}
