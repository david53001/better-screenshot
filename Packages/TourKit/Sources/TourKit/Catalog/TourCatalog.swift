/// Every tour, as data. One file per area so parallel work doesn't collide:
/// `WelcomeTours.swift` (welcome, quickAccess), `EditorTours.swift` (editor, text, redaction,
/// highlighter, spotlight), `RecordingTours.swift` (firstRecording, recordingPill),
/// `VideoEditorTours.swift` (videoEditor), `ShellTours.swift` (settings, history).
/// Steps and wording: spec §14.3 table; copy rules (≤ 4-word titles, ≤ 20-word bodies) are enforced
/// by `CatalogLintTests`.
public enum TourCatalog {
    public static let all: [Tour] = [
        welcome, quickAccess,
        editor, text, redaction, highlighter, spotlight,
        firstRecording, recordingPill,
        videoEditor,
        settings, history,
    ]

    public static func tour(_ id: TourID) -> Tour {
        all.first { $0.id == id }!
    }
}
