// Steps: spec §14.3 table. Filled by the Part 7 lanes (see Packages/TourKit/CLAUDE.md).
extension TourCatalog {
    static let welcome = Tour(id: .welcome, surface: .welcome, trigger: .startedByApp, steps: [], handsOverTo: .quickAccess)
    static let quickAccess = Tour(id: .quickAccess, surface: .quickAccess, trigger: .surfaceShown(.quickAccess), steps: [], handsOverTo: .editor)
}
