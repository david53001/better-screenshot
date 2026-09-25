// Steps: spec §14.3 table. Filled by the Part 7 lanes (see Packages/TourKit/CLAUDE.md).
extension TourCatalog {
    static let editor = Tour(id: .editor, surface: .editor, trigger: .surfaceShown(.editor), steps: [])
    static let text = Tour(id: .text, surface: .editor, trigger: .event(.toolSelected("text")), steps: [])
    static let redaction = Tour(id: .redaction, surface: .editor, trigger: .event(.toolSelected("blur")), steps: [])
    static let highlighter = Tour(id: .highlighter, surface: .editor, trigger: .event(.toolSelected("highlighter")), steps: [])
    static let spotlight = Tour(id: .spotlight, surface: .editor, trigger: .event(.toolSelected("spotlight")), steps: [])
}
