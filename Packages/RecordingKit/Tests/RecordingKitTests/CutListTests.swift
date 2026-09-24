import TestKit
import Foundation
@testable import RecordingKit

private func seg(_ s: Double, _ e: Double, _ speed: Double = 1, muted: Bool = false) -> CutSegment {
    CutSegment(start: s, end: e, speed: speed, muted: muted)
}

/// [0,2] · (cut 2–4) · [4,8] at 2× · (cut 8–10) — a 10 s recording.
private func spedList() -> CutList {
    var l = CutList(duration: 10)
    _ = l.split(atSource: 2); _ = l.split(atSource: 4); _ = l.split(atSource: 8)
    _ = l.remove(at: 1)          // drops 2–4
    _ = l.remove(at: 2)          // drops 8–10
    _ = l.setSpeed(2, of: 1)
    return l
}

let cutListTests: [TestCase] = [
    TestCase("wholeRecordingIsOneSegment") { t in
        let l = CutList(duration: 45)
        t.equal(l.segments, [seg(0, 45)])
        t.approxEqual(l.keptDuration, 45)
        t.equal(l.passthrough?.range, TrimRange(start: 0, end: 45))
        t.equal(l.passthrough?.muted, false)
    },
    TestCase("trimRangeIsTheSingleSegmentCase") { t in
        let l = CutList(range: TrimRange(start: 1, end: 5), duration: 10)
        t.equal(l.segments, [seg(1, 5)])
        t.equal(l.passthrough?.range, TrimRange(start: 1, end: 5))
    },
    TestCase("splitDividesTheSegmentUnderTheTime") { t in
        var l = CutList(duration: 10)
        t.isTrue(l.split(atSource: 3))
        t.equal(l.segments, [seg(0, 3), seg(3, 10)])
        t.isTrue(l.split(atSource: 7))
        t.equal(l.segments, [seg(0, 3), seg(3, 7), seg(7, 10)])
        t.approxEqual(l.keptDuration, 10)
    },
    TestCase("splitPreservesSpeedAndMute") { t in
        var l = CutList(duration: 10)
        _ = l.setSpeed(2, of: 0)
        _ = l.setMuted(false, of: 0)
        t.isTrue(l.split(atSource: 4))
        t.equal(l.segments, [seg(0, 4, 2), seg(4, 10, 2)])
        var m = CutList(duration: 10)
        _ = m.setMuted(true, of: 0)
        _ = m.split(atSource: 5)
        t.equal(m.segments, [seg(0, 5, muted: true), seg(5, 10, muted: true)])
    },
    TestCase("splitRefusesSlivers") { t in
        var l = CutList(duration: 10)
        t.isFalse(l.split(atSource: 0.05), "too close to the start")
        t.isFalse(l.split(atSource: 9.95), "too close to the end")
        t.isFalse(l.split(atSource: 0))
        t.isTrue(l.split(atSource: 5))
        t.isFalse(l.split(atSource: 5), "already split there")
        t.equal(l.segments.count, 2)
    },
    TestCase("splitInsideACutFails") { t in
        var l = CutList(duration: 10)
        _ = l.split(atSource: 3); _ = l.split(atSource: 6); _ = l.remove(at: 1)
        t.isFalse(l.split(atSource: 4.5))
        t.equal(l.segments, [seg(0, 3), seg(6, 10)])
    },
    TestCase("removeDropsASegmentButNeverTheLast") { t in
        var l = CutList(duration: 10)
        _ = l.split(atSource: 3); _ = l.split(atSource: 6)
        t.isTrue(l.remove(at: 1))
        t.equal(l.segments, [seg(0, 3), seg(6, 10)])
        t.approxEqual(l.keptDuration, 7)
        t.isFalse(l.remove(at: 5), "out of range")
        t.isTrue(l.remove(at: 0))
        t.isFalse(l.remove(at: 0), "the last segment stays")
        t.equal(l.segments, [seg(6, 10)])
    },
    TestCase("keptDurationAccountsForSpeed") { t in
        let l = spedList()
        t.equal(l.segments, [seg(0, 2), seg(4, 8, 2, muted: true)])
        t.approxEqual(l.keptDuration, 2 + 2)      // 4 s of source at 2× = 2 s
        var four = CutList(duration: 8)
        _ = four.setSpeed(4, of: 0)
        t.approxEqual(four.keptDuration, 2)
        _ = four.setSpeed(1.5, of: 0)
        t.approxEqual(four.keptDuration, 8 / 1.5, tol: 1e-9)
    },
    TestCase("speedMutesByDefaultAndOnlyKnownSpeeds") { t in
        var l = CutList(duration: 10)
        t.isTrue(l.setSpeed(2, of: 0))
        t.isTrue(l.segments[0].muted, "sped-up audio is muted by default")
        t.isTrue(l.setMuted(false, of: 0))
        t.isTrue(l.setSpeed(4, of: 0))
        t.isFalse(l.segments[0].muted, "an explicit unmute survives 2× → 4×")
        t.isTrue(l.setSpeed(1, of: 0))
        t.isFalse(l.segments[0].muted)
        _ = l.setSpeed(2, of: 0)
        t.isTrue(l.setSpeed(1, of: 0))
        t.isFalse(l.segments[0].muted, "back to 1× unmutes")
        t.isFalse(l.setSpeed(3, of: 0), "3× isn't offered")
        t.isFalse(l.setSpeed(1, of: 0), "no change")
        t.isFalse(l.setMuted(false, of: 0), "no change")
        t.equal(CutList.speeds, [1, 1.5, 2, 4])
    },
    TestCase("edgeDragsClampToNeighboursAndMinimum") { t in
        var l = CutList(duration: 10)
        _ = l.split(atSource: 3); _ = l.split(atSource: 6); _ = l.remove(at: 1)   // [0,3] [6,10]
        t.isTrue(l.setStart(4, of: 1))
        t.equal(l.segments[1], seg(4, 10))
        t.isTrue(l.setStart(1, of: 1))
        t.equal(l.segments[1].start, 3, "stops at the previous segment's end")
        t.isFalse(l.setEnd(9.99, of: 0), "can't grow into the next segment")
        t.equal(l.segments[0].end, 3)
        t.isTrue(l.setEnd(0, of: 0))
        t.approxEqual(l.segments[0].end, CutList.minimumSegment, tol: 1e-9)
        t.isFalse(l.setEnd(42, of: 1), "already at the recording's end")
        t.isFalse(l.setStart(-5, of: 0), "already at 0")
        t.isTrue(l.setStart(99, of: 1))
        t.approxEqual(l.segments[1].start, 10 - CutList.minimumSegment, tol: 1e-9)
    },
    TestCase("inAndOutPoints") { t in
        var l = CutList(duration: 10)
        _ = l.split(atSource: 3); _ = l.split(atSource: 6)          // [0,3] [3,6] [6,10]
        t.isTrue(l.trimBefore(source: 4))
        t.equal(l.segments, [seg(4, 6), seg(6, 10)])
        t.isTrue(l.trimAfter(source: 8))
        t.equal(l.segments, [seg(4, 6), seg(6, 8)])
        t.isTrue(l.trimAfter(source: 6), "out at a boundary drops the later segment")
        t.equal(l.segments, [seg(4, 6)])
        t.isFalse(l.trimBefore(source: 4), "no change")
        var m = CutList(duration: 10)
        t.isTrue(m.trimBefore(source: 9.99))
        t.approxEqual(m.segments[0].start, 10 - CutList.minimumSegment, tol: 1e-9)
    },
    TestCase("outputSourceMapping") { t in
        let l = spedList()                                          // [0,2] · [4,8]@2×
        t.approxEqual(l.sourceTime(forOutput: 1), 1)
        t.approxEqual(l.sourceTime(forOutput: 3), 6)
        t.approxEqual(l.sourceTime(forOutput: 4), 8)
        t.approxEqual(l.outputTime(forSource: 6) ?? -1, 3)
        t.isNil(l.outputTime(forSource: 3), "cut")
        t.equal(l.segmentIndex(atOutput: 0), 0)
        t.equal(l.segmentIndex(atOutput: 2), 1, "a boundary belongs to the later segment")
        t.equal(l.segmentIndex(atOutput: 4), 1, "the very end belongs to the last")
        t.approxEqual(l.outputStart(of: 1), 2)
        t.equal(l.segmentIndex(containingSource: 4), 1)
        t.isNil(l.segmentIndex(containingSource: 9))
    },
    TestCase("passthroughOnlyForOneContiguousStretch") { t in
        var l = CutList(duration: 10)
        _ = l.split(atSource: 4)
        t.equal(l.passthrough?.range, TrimRange(start: 0, end: 10), "a split alone joins back up")
        _ = l.setMuted(true, of: 0); _ = l.setMuted(true, of: 1)
        t.equal(l.passthrough?.muted, true, "all muted = whole-file mute")
        _ = l.setMuted(false, of: 1)
        t.isNil(l.passthrough, "mixed mute needs a re-encode")
        var c = CutList(duration: 10)
        _ = c.split(atSource: 3); _ = c.split(atSource: 6); _ = c.remove(at: 1)
        t.isNil(c.passthrough, "a middle cut needs a re-encode")
        var s = CutList(duration: 10)
        _ = s.setSpeed(1.5, of: 0)
        t.isNil(s.passthrough, "speed needs a re-encode")
        var e = CutList(duration: 10)
        _ = e.setStart(1, of: 0); _ = e.setEnd(9, of: 0)
        t.equal(e.passthrough?.range, TrimRange(start: 1, end: 9), "a plain start/end trim stays lossless")
    },
    TestCase("timelineShowsCutsAndNarrowsSpedSegments") { t in
        let l = spedList()
        t.equal(l.timeline, [
            CutList.TimelineItem(kind: .kept(0), sourceStart: 0, sourceEnd: 2, displayStart: 0, displayLength: 2),
            CutList.TimelineItem(kind: .removed, sourceStart: 2, sourceEnd: 4, displayStart: 2, displayLength: 2),
            CutList.TimelineItem(kind: .kept(1), sourceStart: 4, sourceEnd: 8, displayStart: 4, displayLength: 2),
            CutList.TimelineItem(kind: .removed, sourceStart: 8, sourceEnd: 10, displayStart: 6, displayLength: 2),
        ])
        t.approxEqual(l.timelineLength, 8)
        t.approxEqual(l.timelinePosition(forOutput: 3), 5)
        t.approxEqual(l.outputTime(forTimelinePosition: 5), 3)
        // A click on a cut jumps to the next kept segment, or the end when nothing follows.
        t.approxEqual(l.outputTime(forTimelinePosition: 3), 2)
        t.approxEqual(l.outputTime(forTimelinePosition: 7.5), 4)
        // Filmstrip: cuts map 1:1 to source time, a 2× segment at double rate.
        t.approxEqual(l.sourceTime(forTimelinePosition: 3), 3)
        t.approxEqual(l.sourceTime(forTimelinePosition: 5), 6)
    },
    TestCase("historyUndoesAndRedoesWholeEdits") { t in
        var h = CutHistory(CutList(duration: 10))
        t.isFalse(h.canUndo); t.isFalse(h.canRedo)
        t.isTrue(h.apply { $0.split(atSource: 4) })
        t.isTrue(h.apply { $0.remove(at: 0) })
        t.equal(h.current.segments, [seg(4, 10)])
        t.isFalse(h.apply { $0.remove(at: 0) }, "a refused edit adds no step")
        t.isTrue(h.undo())
        t.equal(h.current.segments, [seg(0, 4), seg(4, 10)])
        t.isTrue(h.undo())
        t.equal(h.current.segments, [seg(0, 10)])
        t.isFalse(h.undo())
        t.isTrue(h.redo())
        t.equal(h.current.segments.count, 2)
        // A drag commits its end state as one step; a new edit clears redo.
        var dragged = h.current
        _ = dragged.setEnd(3, of: 0); _ = dragged.setEnd(2, of: 0)
        h.commit(dragged)
        t.isFalse(h.canRedo)
        t.equal(h.current.segments[0], seg(0, 2))
        h.commit(h.current)
        t.isTrue(h.undo())
        t.equal(h.current.segments[0], seg(0, 4), "the whole drag undoes at once")
    },
]
