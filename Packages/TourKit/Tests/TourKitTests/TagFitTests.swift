import AppKit
import TestKit
@testable import TourKit

/// Height of `body` in the tag bubble's body label (same font, label type and widest inner width),
/// with at most `maxLines` lines (0 = unlimited).
@MainActor private func tagBodyHeight(_ body: String, maxLines: Int) -> CGFloat {
    let label = NSTextField(wrappingLabelWithString: body)
    label.font = TagStyle.bodyFont
    label.maximumNumberOfLines = maxLines
    label.lineBreakMode = .byWordWrapping
    let inner = TagStyle.tagMaxWidth - 2 * TagStyle.tagPaddingX
    label.preferredMaxLayoutWidth = inner
    return ceil(label.sizeThatFits(NSSize(width: inner, height: 1000)).height)
}

/// Combos a `{shortcut:…}` placeholder is measured with: the default look, and the longest a user can
/// bind (every modifier + F12), and what an unbound shortcut shows. The editor and recording fit tests
/// (EditorKit, RecordingKit) use the same.
let tagFitKeys = ["⇧⌘4", "⌃⌥⇧⌘4", "⌃⌥⇧⌘F12", TourText.unboundShortcut]

/// The tours lane 7S wrote (Welcome, Quick Access, Settings, History). The word limit alone doesn't
/// guarantee a body fits the tag's two lines (lane 7E had an 18-word body cut off with "…").
private let shellTours: [TourID] = [.welcome, .quickAccess, .settings, .history]

let tagFitTests: [TestCase] = [
    TestCase("welcomeQuickAccessSettingsAndHistoryBodiesFitTheTagsTwoLines") { t in
        MainActor.assumeIsolated {
            for id in shellTours {
                for step in TourCatalog.tour(id).steps {
                    // Placeholders as the default bindings show them, and longer combos up to every
                    // modifier on a three-character key (review W3).
                    for keys in tagFitKeys {
                        let body = TourText.resolvingShortcuts(in: step.body) { _ in keys }
                        let full = tagBodyHeight(body, maxLines: 0)
                        let shown = tagBodyHeight(body, maxLines: TagStyle.bodyMaxLines)
                        t.isTrue(full <= shown, "\(id)/\(step.title) [\(keys)]: body needs \(full) pt, the tag shows \(shown)")
                    }
                }
            }
        }
    },
    TestCase("theFitCheckBites") { t in
        MainActor.assumeIsolated {
            let long = Array(repeating: "Something", count: 20).joined(separator: " ")
            t.isTrue(tagBodyHeight(long, maxLines: 0) > tagBodyHeight(long, maxLines: TagStyle.bodyMaxLines))
        }
    },
]
