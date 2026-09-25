// Steps: spec §14.3 table, adapted to the real UI (lane 7S). Windows-port copy: parity doc §7.4.
extension TourCatalog {
    /// Started by "Show Me Around" on the Welcome window's last page (`TourCoordinator.answerQuestion`),
    /// hand-over or replay; hosted by the Welcome window. Step 1's anchor is the menu-bar status item's
    /// button, which lives in the status bar's own window (`TourCoordinator.extraAnchorWindows`).
    static let welcome = Tour(id: .welcome, surface: .welcome, trigger: .startedByApp, steps: [
        TourStep(anchor: "menuBar.icon", kind: .explain, title: "Your menu bar icon",
                 body: "BetterScreenshot lives up here. Click it for every capture, recording, History and Settings."),
        TourStep(anchor: "welcome.shortcuts", kind: .explain, title: "Capture shortcuts",
                 body: "They work from any app: {shortcut:captureArea} for an area, {shortcut:captureWindow} for a window, {shortcut:captureFullscreen} for the screen."),
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
                 body: "Drag the card into any app — a chat, an email, a folder — to drop the image there."),
        TourStep(anchor: "quickAccess.actions", kind: .explain, title: "Copy, Edit, Save",
                 body: "Copy puts it on the clipboard, Save in your Screenshots folder. Edit opens the editor."),
        TourStep(anchor: "quickAccess.edit", kind: .tryIt(advanceOn: .action("quickAccess.edit")), title: "Mark it up",
                 body: "Click Edit to draw arrows, add text or blur things out."),
    ], handsOverTo: .editor)
}
