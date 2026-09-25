import CoreGraphics
import Foundation

/// Lays out the video editor's time ruler: ticks at round **output** times (the edit's
/// own clock — what the playhead readout shows) over the kept segments. Cuts get no
/// ticks, since they aren't in the output. The label step is the smallest round
/// interval whose widest label fits between two ticks; a label that would still touch
/// the one before it or run past the end is left off, so labels never overlap, repeat
/// or get clipped. Pure — `CutTimelineView` draws the result.
enum TimeRuler {
    /// A kept segment as drawn: left edge and width in points, and the output time at
    /// its left edge.
    struct Span: Equatable {
        var x: CGFloat
        var width: CGFloat
        var outputStart: Double
    }

    struct Tick: Equatable {
        var time: Double
        var x: CGFloat
        var major: Bool
        /// Only on major ticks, and only where it fits.
        var label: String?
    }

    /// Label intervals (seconds) and how many minor ticks divide each.
    static let steps: [(seconds: Double, divisions: Int)] = [
        (0.1, 2), (0.2, 2), (0.5, 5), (1, 4), (2, 4), (5, 5), (10, 5), (15, 3), (30, 6),
        (60, 4), (120, 4), (300, 5), (600, 5), (900, 3), (1800, 6), (3600, 4),
    ]
    /// A label starts this far right of its tick.
    static let labelOffset: CGFloat = 3
    /// Minimum space between one label's end and the next label's start.
    static let labelGap: CGFloat = 12
    /// Minor ticks closer together than this are left out.
    static let minorSpacing: CGFloat = 4

    /// "0:05" for whole-second steps, "0:04.5" (`TrimRange.timestamp`) for finer ones.
    static func label(_ t: Double, step: Double) -> String {
        if step < 1 { return TrimRange.timestamp(t) }
        let s = Int(t.rounded())
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /// The smallest step whose widest label (at `maxTime`) fits between two ticks.
    static func step(pointsPerSecond pps: CGFloat, maxTime: Double,
                     labelWidth: (String) -> CGFloat) -> (seconds: Double, divisions: Int) {
        for s in steps {
            let widest = labelWidth(label((maxTime / s.seconds).rounded(.down) * s.seconds, step: s.seconds))
            if CGFloat(s.seconds) * pps >= labelOffset + widest + labelGap { return s }
        }
        return steps[steps.count - 1]
    }

    /// Ticks left to right. A span covers output times [start, start + width ÷ pps) —
    /// half-open, so where two segments meet their shared time is ticked once. Labels
    /// are kept greedily from the left: one is dropped if it would start less than
    /// `labelGap` after the previous label ends, or end past `maxX`.
    static func ticks(spans: [Span], pointsPerSecond pps: CGFloat, maxX: CGFloat,
                      labelWidth: (String) -> CGFloat) -> [Tick] {
        guard pps > 0, let last = spans.last else { return [] }
        let maxTime = last.outputStart + Double(last.width / pps)
        let (step, divisions) = step(pointsPerSecond: pps, maxTime: maxTime, labelWidth: labelWidth)
        let showMinor = CGFloat(step / Double(divisions)) * pps >= minorSpacing
        let unit = showMinor ? step / Double(divisions) : step
        let epsilon = 1e-6
        var ticks: [Tick] = []
        var labelEnd = -CGFloat.infinity
        for span in spans {
            let end = span.outputStart + Double(span.width / pps)
            var k = Int((span.outputStart / unit - epsilon).rounded(.up))
            while Double(k) * unit < end - epsilon {
                let t = Double(k) * unit
                let x = span.x + CGFloat(t - span.outputStart) * pps
                let major = !showMinor || k % divisions == 0
                var text: String?
                if major {
                    let l = label(t, step: step), lx = x + labelOffset, w = labelWidth(l)
                    if lx >= labelEnd + labelGap, lx + w <= maxX { text = l; labelEnd = lx + w }
                }
                ticks.append(Tick(time: t, x: x, major: major, label: text))
                k += 1
            }
        }
        return ticks
    }
}
