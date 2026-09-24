import Foundation

/// The kept part of a recording, in seconds. Pure — the single-segment case of a
/// `CutList` (a plain start/end trim, which exports losslessly) and the home of the
/// editor's "m:ss.t" timestamp format.
public struct TrimRange: Equatable {
    public var start: Double
    public var end: Double

    /// Shortest range the exporter will write.
    public static let minimumLength = 0.5

    public init(start: Double, end: Double) { self.start = start; self.end = end }

    public var length: Double { end - start }

    /// Orders the ends, clamps them into `0…duration`, and widens the range to at
    /// least `minimum` (never past either end). A recording shorter than `minimum`
    /// comes back whole.
    public static func clamped(start: Double, end: Double, duration: Double,
                               minimum: Double = minimumLength) -> TrimRange {
        let d = max(duration, 0)
        var s = min(max(min(start, end), 0), d)
        var e = min(max(max(start, end), 0), d)
        if e - s < minimum {
            e = min(s + minimum, d)
            s = max(e - minimum, 0)
        }
        return TrimRange(start: s, end: e)
    }

    /// True when the range keeps (practically) the whole recording.
    public func isNoOp(duration: Double, tolerance: Double = 0.05) -> Bool {
        start <= tolerance && end >= duration - tolerance
    }

    /// "0:02.1 – 0:41.8 of 0:45.0"
    public func label(duration: Double) -> String {
        "\(Self.timestamp(start)) – \(Self.timestamp(end)) of \(Self.timestamp(duration))"
    }

    /// "m:ss.t", rounded to the nearest tenth.
    public static func timestamp(_ seconds: Double) -> String {
        let tenths = Int((max(seconds, 0) * 10).rounded())
        let m = tenths / 600, s = (tenths / 10) % 60, t = tenths % 10
        return "\(m):" + String(format: "%02d", s) + ".\(t)"
    }
}
