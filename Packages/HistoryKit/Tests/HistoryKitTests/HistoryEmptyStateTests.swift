import TestKit
import Foundation
@testable import HistoryKit

let historyEmptyStateTests: [TestCase] = [
    TestCase("namesTheLiveCaptureShortcut") { t in
        let m = HistoryEmptyState.message(historyEnabled: true, captureShortcut: "⌥⌘A")
        t.equal(m.title, "No Captures Yet")
        t.equal(m.detail, "Press ⌥⌘A to take your first screenshot. It will appear here.")
    },
    TestCase("pointsAtTheMenuWhenCaptureAreaIsUnbound") { t in
        let m = HistoryEmptyState.message(historyEnabled: true, captureShortcut: nil)
        t.isTrue(m.detail.contains("Capture Area in the menu bar"), m.detail)
    },
    TestCase("saysHistoryIsOffInsteadOfPromisingCapturesWillAppear") { t in
        let m = HistoryEmptyState.message(historyEnabled: false, captureShortcut: "⇧⌘4")
        t.equal(m.title, "History Is Off")
        t.isTrue(m.detail.contains("Remember capture history"), m.detail)
    },
]
