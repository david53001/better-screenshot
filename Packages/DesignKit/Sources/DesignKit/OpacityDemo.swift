import Foundation

/// The Settings tour's Opacity demo (step `settings.opacity`): the slider sweeps slowly from the user's
/// value down to fully transparent, up to fully opaque and back, so every window and panel shows what the
/// setting does. Pure: the value at `t` seconds, for a demo that started at `start`. Loops every `period`.
public enum OpacityDemoPath {
    /// (duration, target) legs; a leg whose target is nil goes back to `start`.
    static let legs: [(duration: TimeInterval, target: Double?)] = [
        (0.6, nil),   // hold: the tag appears first
        (2.4, 0),     // down to Transparent
        (0.8, 0),     // hold
        (3.2, 1),     // up to Opaque
        (0.8, 1),     // hold
        (1.6, nil),   // back to the user's value
        (1.0, nil),   // rest before the next loop
    ]

    public static var period: TimeInterval { legs.reduce(0) { $0 + $1.duration } }

    public static func value(at t: TimeInterval, from start: Double) -> Double {
        let start = min(max(start.isNaN ? 0.5 : start, 0), 1)
        var time = max(t, 0).truncatingRemainder(dividingBy: period)
        var from = start
        for leg in legs {
            let to = leg.target ?? start
            if time < leg.duration {
                let x = time / leg.duration
                let eased = x * x * (3 - 2 * x)   // smoothstep: eases in and out of each end
                return from + (to - from) * eased
            }
            time -= leg.duration
            from = to
        }
        return start
    }
}
