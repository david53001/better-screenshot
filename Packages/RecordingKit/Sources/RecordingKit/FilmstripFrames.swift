import CoreGraphics

/// Which frames the editor's filmstrip loads: enough that no two neighbouring tiles
/// show the same frame even fully zoomed in (one per tile across the widest possible
/// timeline), never more than 30 per second of video, 12…400. Loaded coarse to fine so
/// the whole strip fills in at once and then sharpens. Pure.
enum FilmstripFrames {
    static let minimum = 12
    static let maximum = 400
    static let maxPerSecond = 30.0

    static func count(duration: Double, timelineWidth: CGFloat, tileWidth: CGFloat) -> Int {
        guard duration > 0, tileWidth > 0 else { return minimum }
        let tiles = Int((timelineWidth / tileWidth).rounded(.up))
        let cap = max(minimum, Int(duration * maxPerSecond))
        return min(max(tiles, minimum), maximum, cap)
    }

    /// Evenly spaced frame times — `(k + 0.5) × duration ÷ count` — ordered every 8th
    /// first, then every 4th, every 2nd, then the rest.
    static func times(duration: Double, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        var order: [Int] = []
        for stride in [8, 4, 2, 1] {
            order += (0..<count).filter { $0 % stride == 0 && (stride == 8 || $0 % (stride * 2) != 0) }
        }
        return order.map { (Double($0) + 0.5) * duration / Double(count) }
    }
}
