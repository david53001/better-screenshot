// Steps: spec §14.3 table, adapted to the video editor as built (v3 Part 6). Anchors and events live in
// Packages/RecordingKit/Sources/RecordingKit/TrimWindowController.swift. Windows-port copy: parity doc §7.7.
extension TourCatalog {
    /// The first time a video editor window has loaded its recording.
    static let videoEditor = Tour(id: .videoEditor, surface: .videoEditor, trigger: .surfaceShown(.videoEditor), steps: [
        TourStep(anchor: "video.preview", kind: .explain, title: "Preview",
                 body: "Plays only the parts you keep. Click it, or press Space, to play."),
        TourStep(anchor: "video.timeline", kind: .explain, title: "The timeline",
                 body: "Click to move the playhead. Drag a part’s yellow edge to trim it."),
        TourStep(anchor: "video.split", kind: .tryIt(advanceOn: .action("video.split")), title: "Split the clip",
                 body: "Click the timeline to place the playhead, then press S or click Split."),
        TourStep(anchor: "video.timeline", kind: .tryIt(advanceOn: .action("video.segmentDeleted")),
                 title: "Delete a part",
                 body: "Click a part to select it, then press ⌫ to cut it out."),
        TourStep(anchor: "video.segment", kind: .explain, title: "Selected part",
                 body: "Change its speed or mute just this part. Right-click a part for the same."),
        TourStep(anchor: "video.saveCopy", kind: .explain, title: "Save a copy",
                 body: "Saves the edit as a new file. The ▾ menu exports a GIF instead."),
        TourStep(anchor: "video.replace", kind: .explain, title: "Replace the original",
                 body: "Overwrites the recording with this edit, then reloads it for more changes."),
    ])
}
