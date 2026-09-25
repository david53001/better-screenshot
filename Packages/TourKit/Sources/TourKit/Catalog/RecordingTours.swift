// Steps: spec §14.3 table, adapted to the record strip and live pill as built (v3 Parts 4–5).
// Anchors are set in App/Recording/RecordStripController.swift and RecordingControlsController.swift;
// events are posted there and in RecordingCoordinator. Windows-port copy: parity doc §7.6.
extension TourCatalog {
    /// The first time the record strip opens: every choice on it, then "start recording", which hands over
    /// to the pill tour. The audio steps are skipped in GIF mode (their menus are greyed out and lose
    /// their anchors).
    static let firstRecording = Tour(id: .firstRecording, surface: .recordStrip, trigger: .surfaceShown(.recordStrip), steps: [
        TourStep(anchor: "strip.targets", kind: .explain, title: "What to record",
                 body: "Full Screen records this screen, Area a part you drag, Window just one window."),
        TourStep(anchor: "strip.format", kind: .explain, title: "MP4 or GIF",
                 body: "MP4 is a video with sound. GIF is a silent, looping animation."),
        TourStep(anchor: "strip.fps", kind: .explain, title: "Frame rate",
                 body: "60 frames per second looks smoother; 30 makes smaller files."),
        TourStep(anchor: "strip.microphone", kind: .tryIt(advanceOn: .menuOpened("strip.microphone")),
                 title: "Open the Microphone menu",
                 body: "Click Microphone to see every input you can record from."),
        TourStep(anchor: "strip.microphoneColumn", kind: .explain, title: "Microphone choices",
                 body: "Pick a mic, or Off to skip it. The level meter above shows it can hear you."),
        TourStep(anchor: "strip.systemAudio", kind: .tryIt(advanceOn: .menuOpened("strip.systemAudio")),
                 title: "Open System audio",
                 body: "Click System audio to choose which sounds from your Mac are recorded."),
        TourStep(anchor: "strip.systemAudio", kind: .explain, title: "Sound choices",
                 body: "Off records none, All apps records everything; “except BetterScreenshot” skips this app’s own sounds."),
        TourStep(anchor: "strip.camera", kind: .explain, title: "Camera bubble",
                 body: "Adds your webcam in a round bubble. Camera Size in this menu sets Small or Medium."),
        TourStep(anchor: "strip.cursor", kind: .explain, title: "Mouse cursor",
                 body: "Choose whether your pointer shows in the video."),
        TourStep(anchor: "strip.hint", kind: .explain, title: "Hints",
                 body: "Point at any control and this line explains it."),
        TourStep(anchor: "strip.targets", kind: .tryIt(advanceOn: .choiceMade("strip.targets")),
                 title: "Start recording",
                 body: "Click Full Screen, Area or Window to start. The recording controls come next."),
    ], handsOverTo: .recordingPill)

    /// The first time the live pill appears (the recording is starting). Steps on controls the pill doesn't
    /// show are skipped: Switch on full-screen recordings, everything but timer · Pause · Stop · chevron
    /// when collapsed, and "Mute the mic" when there's no mic track.
    static let recordingPill = Tour(id: .recordingPill, surface: .recordingPill, trigger: .surfaceShown(.recordingPill), steps: [
        TourStep(anchor: "pill.timer", kind: .explain, title: "Recording time",
                 body: "How long you’ve been recording. Drag the pill anywhere you like."),
        TourStep(anchor: "pill.mic", kind: .tryIt(advanceOn: .action("pill.micMuted")), title: "Mute the mic",
                 body: "Click Mic to mute it — click again to unmute. The video stays in sync."),
        TourStep(anchor: "pill.systemAudio", kind: .explain, title: "System audio",
                 body: "Mutes the sound your Mac plays. It’s greyed out when that wasn’t recorded."),
        TourStep(anchor: "pill.camera", kind: .explain, title: "Camera bubble",
                 body: "Shows or hides your camera bubble while you record."),
        TourStep(anchor: "pill.switch", kind: .explain, title: "Record something else",
                 body: "Move the recording to another window or area without stopping."),
        TourStep(anchor: "pill.restart", kind: .explain, title: "Restart",
                 body: "Deletes what’s recorded so far and starts again. Click twice to confirm."),
        TourStep(anchor: "pill.discard", kind: .explain, title: "Discard",
                 body: "Stops and deletes this recording. Click twice to confirm."),
        TourStep(anchor: "pill.pause", kind: .explain, title: "Pause",
                 body: "Pauses the recording. Press it again to carry on."),
        TourStep(anchor: "pill.collapse", kind: .explain, title: "Fewer controls",
                 body: "Shows fewer or more controls. Collapsed, the pill keeps the timer, Pause and Stop."),
        TourStep(anchor: "pill.stop", kind: .tryIt(advanceOn: .action("recording.stopped")), title: "Stop when done",
                 body: "Press Stop when you’re finished. Your video then opens in a card."),
    ])
}
