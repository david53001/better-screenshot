// Steps: spec §14.3 table, adapted to the real UI (lane 7S). Windows-port copy: parity doc §7.8.
extension TourCatalog {
    /// The first Settings window (SwiftUI; anchors via `.tourAnchor`). `settings.cards` fills most of the
    /// window, so the layout puts its tag beside the window, or inside the cards' top-right corner.
    static let settings = Tour(id: .settings, surface: .settings, trigger: .surfaceShown(.settings), steps: [
        TourStep(anchor: "settings.cards", kind: .explain, title: "Your settings",
                 body: "Related settings share a card. Changes apply right away."),
        // `settings.tip` outlines the "After a capture" label with its ⓘ, so the tag can't hide which
        // setting the tiny ⓘ belongs to (review S2).
        TourStep(anchor: "settings.tip", kind: .explain, title: "Tips on every row",
                 body: "Hover any ⓘ for a plain explanation of that setting and an example."),
        TourStep(anchor: "settings.shortcuts", kind: .explain, title: "Keyboard shortcuts",
                 body: "Click any shortcut, then press new keys to change it. Esc cancels."),
    ])

    /// The first History window (SwiftUI; anchors via `.tourAnchor`). `history.item` is the first
    /// capture in the grid and `history.actions` the action bar — both absent while History is empty, so
    /// only the first step shows then.
    static let history = Tour(id: .history, surface: .history, trigger: .surfaceShown(.history), steps: [
        TourStep(anchor: "history.grid", kind: .explain, title: "Your capture history",
                 body: "Every screenshot and recording you take is kept here, newest first."),
        TourStep(anchor: "history.item", kind: .tryIt(advanceOn: .action("history.selected")), title: "Select a capture",
                 body: "Click any capture to select it. Double-click opens it instead."),
        TourStep(anchor: "history.item", kind: .explain, title: "Several at once",
                 body: "⌘-click or ⇧-click to add more, then drag them into any app together."),
        TourStep(anchor: "history.actions", kind: .explain, title: "Actions",
                 body: "Copy, annotate, pin, edit a video, show in Finder or delete. Right-click works too."),
    ])
}
