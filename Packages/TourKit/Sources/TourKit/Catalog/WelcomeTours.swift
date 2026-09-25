// Steps: spec §14.3 table, adapted to the real UI (lane 7S; trimmed after the 2026-09-26 review).
// Windows-port copy: parity doc §7.4.
extension TourCatalog {
    /// Started by "Show Me Around" on the Welcome window's last page (`TourCoordinator.answerQuestion`),
    /// hand-over or replay; hosted by the Welcome window. Step 1's anchor is the menu-bar status item's
    /// button, which lives in the status bar's own window (`TourCoordinator.extraAnchorWindows`).
    static let welcome = Tour(id: .welcome, surface: .welcome, trigger: .startedByApp, steps: [
        TourStep(anchor: "menuBar.icon", kind: .explain, title: "Your menu bar icon",
                 body: "Everything lives here: captures, recordings, History and Settings."),
        // `welcome.shortcuts` outlines only the three capture rows this body names. A non-breaking space
        // (U+00A0) glues each combo to its word, so a line never ends on a bare combo; this wording fits
        // the tag's two lines even with three ⌃⌥⇧⌘F12-long combos (TagFitTests).
        TourStep(anchor: "welcome.shortcuts", kind: .explain, title: "Capture shortcuts",
                 body: "{shortcut:captureArea}\u{00A0}area, {shortcut:captureWindow}\u{00A0}window, "
                     + "{shortcut:captureFullscreen}\u{00A0}full\u{00A0}screen — in any app."),
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
        // Save writes to the macOS screenshot location (`SettingsStore.systemScreenshotLocation`), not
        // Settings' Save location.
        TourStep(anchor: "quickAccess.actions", kind: .explain, title: "Copy, Edit, Save",
                 body: "Copy it, Edit it, or Save it where macOS keeps screenshots, usually the Desktop."),
        // Left of the card like steps 1–3: "automatic" put it above (the button row is a wide bar), with
        // the leader across the screenshot.
        TourStep(anchor: "quickAccess.edit", kind: .tryIt(advanceOn: .action("quickAccess.edit")), title: "Mark it up",
                 body: "Click Edit to draw arrows, add text or blur things out.", placement: .left),
    ], handsOverTo: .editor)
}
