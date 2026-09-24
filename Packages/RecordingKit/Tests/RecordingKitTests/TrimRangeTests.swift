import TestKit
import Foundation
@testable import RecordingKit

let trimRangeTests: [TestCase] = [
    TestCase("clampOrdersAndBounds") { t in
        t.equal(TrimRange.clamped(start: 8, end: 2, duration: 10), TrimRange(start: 2, end: 8))
        t.equal(TrimRange.clamped(start: -3, end: 42, duration: 10), TrimRange(start: 0, end: 10))
    },
    TestCase("clampEnforcesMinimumLength") { t in
        t.equal(TrimRange.clamped(start: 4, end: 4.1, duration: 10), TrimRange(start: 4, end: 4.5))
        // At the very end the range grows backwards instead of past the duration.
        t.equal(TrimRange.clamped(start: 9.9, end: 10, duration: 10), TrimRange(start: 9.5, end: 10))
        // A recording shorter than the minimum is kept whole.
        t.equal(TrimRange.clamped(start: 0.1, end: 0.2, duration: 0.3), TrimRange(start: 0, end: 0.3))
    },
    TestCase("noOpDetection") { t in
        t.isTrue(TrimRange(start: 0, end: 45).isNoOp(duration: 45))
        t.isTrue(TrimRange(start: 0.02, end: 44.97).isNoOp(duration: 45))
        t.isFalse(TrimRange(start: 1, end: 45).isNoOp(duration: 45))
        t.isFalse(TrimRange(start: 0, end: 44).isNoOp(duration: 45))
    },
    TestCase("labels") { t in
        t.equal(TrimRange.timestamp(2.14), "0:02.1")
        t.equal(TrimRange.timestamp(61.96), "1:02.0")
        t.equal(TrimRange.timestamp(0), "0:00.0")
        t.equal(TrimRange(start: 2.1, end: 41.8).label(duration: 45), "0:02.1 – 0:41.8 of 0:45.0")
    },
    TestCase("trimmedFileNames") { t in
        t.equal(TrimmedFileName.name(forOriginal: "Recording 2026-09-24 at 10.00.00.mp4"),
                "Recording 2026-09-24 at 10.00.00 (trimmed).mp4")
        // Trimming a trimmed copy doesn't stack suffixes.
        t.equal(TrimmedFileName.name(forOriginal: "Rec (trimmed).mp4"), "Rec (trimmed).mp4")
        t.equal(TrimmedFileName.name(forOriginal: "Rec (trimmed) 3.mp4"), "Rec (trimmed).mp4")
        let taken: Set = ["Rec (trimmed).mp4", "Rec (trimmed) 2.mp4"]
        t.equal(TrimmedFileName.unique(forOriginal: "Rec.mp4", exists: taken.contains), "Rec (trimmed) 3.mp4")
        t.equal(TrimmedFileName.unique(forOriginal: "Rec (trimmed).mp4", exists: taken.contains),
                "Rec (trimmed) 3.mp4")
    },
    TestCase("editedGIFFileNames") { t in
        let gif = { (o: String) in TrimmedFileName.name(forOriginal: o, suffix: TrimmedFileName.edited, ext: "gif") }
        t.equal(gif("Recording 2026-09-24 at 10.00.00.mp4"), "Recording 2026-09-24 at 10.00.00 (edited).gif")
        // Exports of exports keep one suffix.
        t.equal(gif("Rec (trimmed).mp4"), "Rec (edited).gif")
        t.equal(gif("Rec (trimmed) 2.mp4"), "Rec (edited).gif")
        t.equal(TrimmedFileName.name(forOriginal: "Rec (edited).mp4"), "Rec (trimmed).mp4")
        let taken: Set = ["Rec (edited).gif"]
        t.equal(TrimmedFileName.unique(forOriginal: "Rec.mp4", suffix: TrimmedFileName.edited, ext: "gif",
                                       exists: taken.contains), "Rec (edited) 2.gif")
    },
]
