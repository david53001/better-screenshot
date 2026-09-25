import Foundation

/// What the History window says when it has nothing to show: how to take a first
/// capture (with the user's own Capture Area shortcut), or that History is off.
public enum HistoryEmptyState {
    public struct Message: Equatable {
        public let title: String
        public let detail: String
    }

    /// `captureShortcut` is the live Capture Area binding ("⇧⌘4"), nil when unbound.
    public static func message(historyEnabled: Bool, captureShortcut: String?) -> Message {
        guard historyEnabled else {
            return Message(title: "History Is Off",
                           detail: "Turn on Remember capture history in Settings to keep your captures here.")
        }
        if let captureShortcut, !captureShortcut.isEmpty {
            return Message(title: "No Captures Yet",
                           detail: "Press \(captureShortcut) to take your first screenshot. It will appear here.")
        }
        return Message(title: "No Captures Yet",
                       detail: "Choose Capture Area in the menu bar to take your first screenshot. It will appear here.")
    }
}
