// Steps: spec §14.3 table. Filled by the Part 7 lanes (see Packages/TourKit/CLAUDE.md).
extension TourCatalog {
    static let firstRecording = Tour(id: .firstRecording, surface: .recordStrip, trigger: .surfaceShown(.recordStrip), steps: [], handsOverTo: .recordingPill)
    static let recordingPill = Tour(id: .recordingPill, surface: .recordingPill, trigger: .surfaceShown(.recordingPill), steps: [])
}
