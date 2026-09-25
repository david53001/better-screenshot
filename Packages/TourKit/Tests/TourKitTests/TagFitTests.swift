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

/// The tours lane 7S wrote (Welcome, Quick Access, Settings, History). The word limit alone doesn't
/// guarantee a body fits the tag's two lines (lane 7E had an 18-word body cut off with "…").
private let shellTours: [TourID] = [.welcome, .quickAccess, .settings, .history]

let tagFitTests: [TestCase] = [
    TestCase("welcomeQuickAccessSettingsAndHistoryBodiesFitTheTagsTwoLines") { t in
        MainActor.assumeIsolated {
            for id in shellTours {
                for step in TourCatalog.tour(id).steps {
                    // Placeholders as the default bindings show them; a longer combo ("⌃⌥⇧⌘4") too.
                    for keys in ["⇧⌘4", "⌃⌥⇧⌘4"] {
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
