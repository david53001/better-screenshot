// Steps: spec §14.3 table, adapted to the record strip and live pill as built (v3 Parts 4–5), then
// trimmed after the 2026-09-26 review (R2, P1). Anchors are set in App/Recording/RecordStripController.swift
// and RecordingControlsController.swift; events are posted there and in RecordingCoordinator.
// Windows-port copy: parity doc §7.6.
extension TourCatalog {
    /// The first time the record strip opens: every choice on it (the owner: "walks you through all the
    /// choices you can make"), six steps — Format + FPS share one, each audio menu's choices sit in its Try
    /// step, and Camera / Mouse cursor are named in the hint-line step — then "start recording", which hands
    /// over to the pill tour. The audio steps are skipped in GIF mode (their menus are greyed out and lose
    /// their anchors).
    static let firstRecording = Tour(id: .firstRecording, surface: .recordStrip, trigger: .surfaceShown(.recordStrip), steps: [
        TourStep(anchor: "strip.targets", kind: .explain, title: "What to record",
                 body: "Full Screen records this screen, Area a part you drag, Window just one window."),
        TourStep(anchor: "strip.output", kind: .explain, title: "Format and frame rate",
                 body: "MP4 has sound; GIF is a silent loop. 60 FPS is smoother, 30 makes smaller files."),
        // Mic is Off by default and its level meter needs the permission first, so the meter is promised
        // only "once it's on" (review R1). Left of the strip: from above, the leader crossed its top row.
        TourStep(anchor: "strip.microphoneColumn", kind: .tryIt(advanceOn: .menuOpened("strip.microphone")),
                 title: "Pick a microphone",
                 body: "Click Microphone, then pick a mic or Off. Once it’s on, a meter shows it hears you.",
                 placement: .left),
        TourStep(anchor: "strip.systemAudio", kind: .tryIt(advanceOn: .menuOpened("strip.systemAudio")),
                 title: "Record your Mac’s sound",
                 body: "Click System audio to choose: Off, all apps, or all but BetterScreenshot."),
        TourStep(anchor: "strip.hint", kind: .explain, title: "Camera, cursor and hints",
                 body: "Point at any control — Camera, Mouse cursor — and this line explains it.",
                 placement: .left),
        TourStep(anchor: "strip.targets", kind: .tryIt(advanceOn: .choiceMade("strip.targets")),
                 title: "Start recording",
                 body: "Click Full Screen, Area or Window to start. The recording controls come next."),
    ], handsOverTo: .recordingPill)

    /// The first time the live pill appears. It runs over the user's first real recording, so it's short
    /// (review P1): time, the mic (an Explain step — a Try step completed on mute and left the mic muted,
    /// P2), Restart/Discard, Pause, Stop — left to right along the pill. Skipped when their control isn't
    /// shown: the mic step without a mic track, everything but the timer · Pause · Stop when collapsed.
    static let recordingPill = Tour(id: .recordingPill, surface: .recordingPill, trigger: .surfaceShown(.recordingPill), steps: [
        TourStep(anchor: "pill.timer", kind: .explain, title: "Recording time",
                 body: "How long you’ve been recording. Drag the pill anywhere you like."),
        TourStep(anchor: "pill.mic", kind: .explain, title: "Mute the mic",
                 body: "Click Mic to mute it, and again to unmute. The video stays in sync."),
        TourStep(anchor: "pill.restart", kind: .explain, title: "Restart or discard",
                 body: "Restart starts over; Discard, next to it, deletes it. Both need a second click."),
        TourStep(anchor: "pill.pause", kind: .explain, title: "Pause",
                 body: "Pauses the recording. Press it again to carry on."),
        TourStep(anchor: "pill.stop", kind: .tryIt(advanceOn: .action("recording.stopped")), title: "Stop when done",
                 body: "Press Stop when you’re finished. Your video then opens in a card."),
    ])
}
