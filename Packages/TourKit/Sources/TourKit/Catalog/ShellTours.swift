// Steps: spec §14.3 table. Filled by the Part 7 lanes (see Packages/TourKit/CLAUDE.md).
extension TourCatalog {
    static let settings = Tour(id: .settings, surface: .settings, trigger: .surfaceShown(.settings), steps: [])
    static let history = Tour(id: .history, surface: .history, trigger: .surfaceShown(.history), steps: [])
}
