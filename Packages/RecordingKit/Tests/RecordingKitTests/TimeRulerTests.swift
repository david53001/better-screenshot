import TestKit
import CoreGraphics
@testable import RecordingKit

/// 6 pt per character — stands in for the real font.
private func width(_ s: String) -> CGFloat { CGFloat(s.count) * 6 }

private func labelled(_ ticks: [TimeRuler.Tick]) -> [TimeRuler.Tick] { ticks.filter { $0.label != nil } }

/// No two labels closer than the gap, none past `maxX`.
private func assertNoCollisions(_ t: TestContext, _ ticks: [TimeRuler.Tick], maxX: CGFloat) {
    let shown = labelled(ticks)
    for (a, b) in zip(shown, shown.dropFirst()) {
        let aEnd = a.x + TimeRuler.labelOffset + width(a.label!)
        t.isTrue(b.x + TimeRuler.labelOffset >= aEnd + TimeRuler.labelGap - 0.001,
                 "“\(a.label!)” at \(a.x) touches “\(b.label!)” at \(b.x)")
    }
    for tick in shown {
        t.isTrue(tick.x + TimeRuler.labelOffset + width(tick.label!) <= maxX + 0.001, "“\(tick.label!)” runs past the end")
    }
    t.equal(Set(shown.map(\.label!)).count, shown.count, "a label repeats")
}

let timeRulerTests: [TestCase] = [
    TestCase("labelFormat") { t in
        t.equal(TimeRuler.label(5, step: 1), "0:05")
        t.equal(TimeRuler.label(65, step: 5), "1:05")
        t.equal(TimeRuler.label(3600, step: 600), "60:00", "minutes only, like the playhead readout")
        t.equal(TimeRuler.label(4.5, step: 0.5), "0:04.5")
        t.equal(TimeRuler.label(Double(3) * 0.1, step: 0.1), "0:00.3", "float noise rounds away")
    },
    TestCase("stepIsTheSmallestThatFitsTheWidestLabel") { t in
        // "0:20" = 24 pt → needs 3 + 24 + 12 = 39 pt between ticks.
        t.equal(TimeRuler.step(pointsPerSecond: 50, maxTime: 20, labelWidth: width).seconds, 1)
        t.equal(TimeRuler.step(pointsPerSecond: 38, maxTime: 20, labelWidth: width).seconds, 2)
        // Zoomed in: "0:20.0" = 36 pt → 51 pt; 0.1 s × 520 = 52.
        t.equal(TimeRuler.step(pointsPerSecond: 520, maxTime: 20, labelWidth: width).seconds, 0.1)
        // An hour-long recording at fit-to-width: "60:00" = 30 pt → 45 pt.
        t.equal(TimeRuler.step(pointsPerSecond: 936.0 / 3600, maxTime: 3600, labelWidth: width).seconds, 300)
    },
    TestCase("wholeRecordingIsTickedAtRoundTimes") { t in
        // 20 s over 1000 pt (50 pt/s): labels every second, 4 minor ticks per label.
        let ticks = TimeRuler.ticks(spans: [.init(x: 12, width: 1000, outputStart: 0)], pointsPerSecond: 50,
                                    maxX: 1022, labelWidth: width)
        let shown = labelled(ticks)
        t.equal(shown.first?.label, "0:00")
        t.equal(shown.first?.x, 12)
        t.equal(shown.map(\.time), Array(0..<20).map(Double.init), "0 … 19; the end (0:20) is not ticked")
        t.equal(ticks.filter { !$0.major }.count, 20 * 3)
        assertNoCollisions(t, ticks, maxX: 1022)
    },
    TestCase("cutsHaveNoTicksAndOutputTimeContinuesAfterThem") { t in
        // Kept 0–5 s at 50 pt/s, a 4 s cut (200 pt), then 11 s at 2× (5.5 s of output).
        let spans: [TimeRuler.Span] = [.init(x: 12, width: 250, outputStart: 0),
                                       .init(x: 462, width: 275, outputStart: 5)]
        let ticks = TimeRuler.ticks(spans: spans, pointsPerSecond: 50, maxX: 800, labelWidth: width)
        t.isFalse(ticks.contains { $0.x > 262 && $0.x < 462 }, "nothing over the cut")
        t.equal(labelled(ticks).map(\.label!), ["0:00", "0:01", "0:02", "0:03", "0:04",
                                                "0:05", "0:06", "0:07", "0:08", "0:09", "0:10"])
        t.equal(labelled(ticks).first { $0.time == 5 }?.x, 462, "0:05 is the start of the second segment")
        assertNoCollisions(t, ticks, maxX: 800)
    },
    TestCase("adjacentSegmentsTickTheirSharedTimeOnce") { t in
        // A split at 5 s; float noise either side of the boundary.
        for start in [5.0, 5.000000001, 4.999999999] {
            let spans: [TimeRuler.Span] = [.init(x: 0, width: CGFloat(start) * 50, outputStart: 0),
                                           .init(x: CGFloat(start) * 50, width: 250, outputStart: start)]
            let ticks = TimeRuler.ticks(spans: spans, pointsPerSecond: 50, maxX: 1000, labelWidth: width)
            t.equal(ticks.filter { abs($0.time - 5) < 1e-3 }.count, 1, "5 s ticked once (start \(start))")
            t.equal(labelled(ticks).count, 10)
        }
    },
    TestCase("labelThatWouldTouchThePreviousOneIsDropped") { t in
        // Segment 1 ends at 1.2 s (its 0:01 label spans 65…89); a 0.04 s cut; segment 2
        // starts at output 1.95, so its 0:02 tick lands at 74.5 — right under that label.
        let spans: [TimeRuler.Span] = [.init(x: 12, width: 60, outputStart: 0),
                                       .init(x: 72, width: 300, outputStart: 1.95)]
        let ticks = TimeRuler.ticks(spans: spans, pointsPerSecond: 50, maxX: 400, labelWidth: width)
        let two = ticks.first { $0.time == 2 }
        t.equal(two?.major, true, "the tick itself stays")
        t.isNil(two?.label, "its label is dropped")
        t.equal(ticks.first { $0.time == 3 }?.label, "0:03")
        assertNoCollisions(t, ticks, maxX: 400)
    },
    TestCase("lastLabelIsDroppedRatherThanClipped") { t in
        // 19 s tick at x = 12 + 950 = 962; "0:19" needs 3 + 24 → ends at 989 > 980.
        let ticks = TimeRuler.ticks(spans: [.init(x: 12, width: 1000, outputStart: 0)], pointsPerSecond: 50,
                                    maxX: 980, labelWidth: width)
        t.isNil(ticks.first { $0.time == 19 }?.label)
        t.equal(labelled(ticks).last?.label, "0:18")
        assertNoCollisions(t, ticks, maxX: 980)
    },
    TestCase("zoomedInLabelsAreUniqueAndEvenlySpaced") { t in
        // 12× zoom: 20 s over 11 232 pt.
        let pps: CGFloat = 11_232.0 / 20
        let ticks = TimeRuler.ticks(spans: [.init(x: 12, width: 11_232, outputStart: 0)], pointsPerSecond: pps,
                                    maxX: 11_254, labelWidth: width)
        let shown = labelled(ticks)
        t.equal(shown.count, 200)
        t.equal(shown[44].label, "0:04.4")
        let gaps = Set(zip(shown, shown.dropFirst()).map { (($1.x - $0.x) * 100).rounded() })
        t.equal(gaps.count, 1, "evenly spaced")
        assertNoCollisions(t, ticks, maxX: 11_254)
    },
    TestCase("nothingLoadedDrawsNothing") { t in
        t.equal(TimeRuler.ticks(spans: [], pointsPerSecond: 50, maxX: 100, labelWidth: width), [])
        t.equal(TimeRuler.ticks(spans: [.init(x: 0, width: 0, outputStart: 0)], pointsPerSecond: 0,
                                maxX: 100, labelWidth: width), [])
    },
]

let filmstripFramesTests: [TestCase] = [
    TestCase("countCoversEveryTileAtFullZoom") { t in
        // A 20 s clip, a 1 728 pt screen at 12× zoom, 80 pt tiles → 260 frames (13 a second).
        t.equal(FilmstripFrames.count(duration: 20, timelineWidth: 1728 * 12, tileWidth: 80), 260)
        // Capped at 400, and at 30 frames per second of video.
        t.equal(FilmstripFrames.count(duration: 3600, timelineWidth: 5120 * 12, tileWidth: 80), 400)
        t.equal(FilmstripFrames.count(duration: 1, timelineWidth: 1728 * 12, tileWidth: 80), 30)
        // Never fewer than 12.
        t.equal(FilmstripFrames.count(duration: 0.2, timelineWidth: 1728 * 12, tileWidth: 80), 12)
        t.equal(FilmstripFrames.count(duration: 0, timelineWidth: 1728 * 12, tileWidth: 80), 12)
    },
    TestCase("timesAreEvenAndCoarseToFine") { t in
        let times = FilmstripFrames.times(duration: 16, count: 16)
        t.equal(times.sorted(), (0..<16).map { Double($0) + 0.5 }, "every frame once, centred in its slot")
        t.equal(Array(times.prefix(2)), [0.5, 8.5], "every 8th first")
        t.equal(Array(times[2..<4]), [4.5, 12.5], "then every 4th")
        t.equal(FilmstripFrames.times(duration: 10, count: 0), [])
    },
]
