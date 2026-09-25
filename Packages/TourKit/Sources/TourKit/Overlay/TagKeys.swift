import AppKit

/// What a key press does while a tag is up (spec §14.3): Return / keypad Enter = Next on Explain
/// steps, Esc = Skip tour. Everything else — any modifier, a held-down repeat, typing in a text
/// view, a Try step's Return — passes through to the app untouched. Pure and unit-tested.
enum TagKeys {
    enum Action: Equatable { case next, skipTour }

    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53

    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isRepeat: Bool,
                       isExplainStep: Bool, isEditingText: Bool) -> Action? {
        if isRepeat || isEditingText { return nil }
        if !modifiers.intersection([.command, .option, .control, .shift]).isEmpty { return nil }
        switch keyCode {
        case returnKey, keypadEnter: return isExplainStep ? .next : nil
        case escape: return .skipTour
        default: return nil
        }
    }
}
