// Steps: spec §14.3 table, adapted to the real UI (lane 7S). Windows-port copy: parity doc §7.4.
extension TourCatalog {
    /// Started by "Show Me Around" on the Welcome window's last page (`TourCoordinator.answerQuestion`),
    /// hand-over or replay; hosted by the Welcome window. Step 1's anchor is the menu-bar status item's
    /// button, which lives in the status bar's own window (`TourCoordinator.extraAnchorWindows`).
    static let welcome = Tour(id: .welcome, surface: .welcome, trigger: .startedByApp, steps: [
        TourStep(anchor: "menuBar.icon", kind: .explain, title: "Your menu bar icon",
                 body: "Everything lives here: captures, recordings, History and Settings."),
        TourStep(anchor: "welcome.shortcuts", kind: .explain, title: "Capture shortcuts",
                 body: "These work in any app: {shortcut:captureArea} area, {shortcut:captureWindow} window, {shortcut:captureFullscreen} full screen."),
        TourStep(anchor: "welcome.captureArea", kind: .tryIt(advanceOn: .captureTaken), title: "Take a screenshot",
                 body: "Press {shortcut:captureArea} now and drag across anything on screen."),
    ], handsOverTo: .quickAccess)

    /// The first screenshot's Quick Access card (`QuickAccessStackController` reports screenshot cards
    /// only). The card stays up while this tour points at it (no auto-dismiss, a drop doesn't close it).
    static let quickAccess = Tour(id: .quickAccess, surface: .quickAccess, trigger: .surfaceShown(.quickAccess), steps: [
        TourStep(anchor: "quickAccess.card", kind: .explain, title: "Your screenshot",
                 body: "Each capture waits here as a card until you use it or close it."),
        TourStep(anchor: "quickAccess.card", kind: .tryIt(advanceOn: .action("quickAccess.dragged")),
                 title: "Drag it anywhere",
                 body: "Drag the card into any app — a chat, an email, a folder."),
        TourStep(anchor: "quickAccess.actions", kind: .explain, title: "Copy, Edit, Save",
                 body: "Copy to the clipboard, Edit, or Save to your Screenshots folder."),
        TourStep(anchor: "quickAccess.edit", kind: .tryIt(advanceOn: .action("quickAccess.edit")), title: "Mark it up",
                 body: "Click Edit to draw arrows, add text or blur things out."),
    ], handsOverTo: .editor)
}
