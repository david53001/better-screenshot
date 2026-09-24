import Foundation

/// The editor's "Recent" colours: most recent first, no duplicates, at most `capacity`.
/// Shared by all tools; the host persists `colors` (see `EditorWindowController.onRecentColorsChanged`).
public struct RecentColors: Equatable {
    public static let capacity = 6
    public private(set) var colors: [RGBAColor] = []

    public init(_ colors: [RGBAColor] = []) {
        for c in colors.reversed() { add(c) }
    }

    /// Puts `color` first (moving it if already present). `replacingFront` swaps out the
    /// current first entry instead — the colour panel reports every intermediate colour
    /// while its wheel is dragged, and only the last one should stay in the list.
    public mutating func add(_ color: RGBAColor, replacingFront: Bool = false) {
        if replacingFront, !colors.isEmpty { colors.removeFirst() }
        colors.removeAll { Self.same($0, color) }
        colors.insert(color, at: 0)
        if colors.count > Self.capacity { colors.removeLast(colors.count - Self.capacity) }
    }

    /// Equal at 8-bit precision (what a user can tell apart).
    public static func same(_ a: RGBAColor, _ b: RGBAColor) -> Bool {
        func q(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
        return q(a.r) == q(b.r) && q(a.g) == q(b.g) && q(a.b) == q(b.b) && q(a.a) == q(b.a)
    }
}
