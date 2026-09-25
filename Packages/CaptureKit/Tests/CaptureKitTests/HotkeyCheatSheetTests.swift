import TestKit
import Foundation
@testable import CaptureKit

let hotkeyCheatSheetTests: [TestCase] = [
    TestCase("defaultsListFiveShortcutsInMenuOrderAndAppleModifierOrder") { t in
        let rows = HotkeyCheatSheet.rows(for: .defaults)
        t.equal(rows.map(\.keys), ["⇧⌘4", "⇧⌘8", "⇧⌘6", "⇧⌘7", "⇧⌘5"])
        t.equal(rows.map(\.description), ["Capture an area", "Capture a window",
                                          "Capture the full screen", "Copy text from the screen",
                                          "Record the screen"])
    },
    TestCase("aRebindingShowsTheLiveCombo") { t in
        var b = HotkeyBindings.defaults
        b.set(HotkeyCombo(keyCode: 0, modifiers: HotkeyCombo.optionMask | HotkeyCombo.commandMask),
              for: .captureArea)   // ⌥⌘A
        t.equal(HotkeyCheatSheet.rows(for: b).first, .init(keys: "⌥⌘A", description: "Capture an area"))
    },
    TestCase("unboundActionsAreLeftOut") { t in
        var b = HotkeyBindings.defaults
        b.clear(.captureWindow)
        b.clear(.record)
        t.equal(HotkeyCheatSheet.rows(for: b).map(\.description),
                ["Capture an area", "Capture the full screen", "Copy text from the screen"])
    },
    TestCase("keysForOneActionFollowTheLiveBinding") { t in
        var b = HotkeyBindings.defaults
        t.equal(HotkeyCheatSheet.keys(for: .captureArea, in: b), "⇧⌘4")
        t.isNil(HotkeyCheatSheet.keys(for: .openHistory, in: b))
        b.set(HotkeyCombo(keyCode: 0, modifiers: HotkeyCombo.optionMask | HotkeyCombo.commandMask),
              for: .captureArea)
        t.equal(HotkeyCheatSheet.keys(for: .captureArea, in: b), "⌥⌘A")
    },
]
