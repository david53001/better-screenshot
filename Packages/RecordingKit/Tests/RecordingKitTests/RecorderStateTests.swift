import TestKit
import Foundation
@testable import RecordingKit

let recorderStateTests: [TestCase] = [
    TestCase("legalTransitions") { t in
        var s = RecorderState.idle
        t.isTrue(s.transition(.arm)); t.equal(s, .armed)
        t.isTrue(s.transition(.begin(Date(timeIntervalSince1970: 100))))
        if case .recording(let started, let acc) = s {
            t.equal(started, Date(timeIntervalSince1970: 100)); t.equal(acc, 0)
        } else { t.fail("expected .recording") }
        t.isTrue(s.transition(.finish)); t.equal(s, .finishing)
        t.isTrue(s.transition(.reset)); t.equal(s, .idle)
    },
    TestCase("pauseResumeTransitions") { t in
        var s = RecorderState.armed
        _ = s.transition(.begin(Date(timeIntervalSince1970: 0)))
        t.isTrue(s.transition(.pause(Date(timeIntervalSince1970: 10))))   // recording → paused
        if case .paused(let started, let acc, let since) = s {
            t.equal(started, Date(timeIntervalSince1970: 0)); t.equal(acc, 0)
            t.equal(since, Date(timeIntervalSince1970: 10))
        } else { t.fail("expected .paused") }
        t.isTrue(s.transition(.resume(Date(timeIntervalSince1970: 13))))  // paused → recording, +3s
        if case .recording(_, let acc) = s { t.equal(acc, 3) } else { t.fail("expected .recording") }
        t.isTrue(s.transition(.finish)); t.equal(s, .finishing)
    },
    TestCase("pauseThenFinish") { t in
        var s = RecorderState.armed
        _ = s.transition(.begin(Date(timeIntervalSince1970: 0)))
        _ = s.transition(.pause(Date(timeIntervalSince1970: 5)))
        t.isTrue(s.transition(.finish)); t.equal(s, .finishing)           // paused → finishing (⌘⇧5 / quit)
    },
    TestCase("illegalTransitionsRejected") { t in
        var s = RecorderState.idle
        t.isFalse(s.transition(.finish))
        t.isFalse(s.transition(.begin(Date())))
        t.isFalse(s.transition(.pause(Date())))     // can't pause when idle
        t.isFalse(s.transition(.resume(Date())))    // can't resume when idle
        s = .armed
        t.isFalse(s.transition(.pause(Date())))     // can't pause from armed (no engine yet)
        s = .finishing
        t.isFalse(s.transition(.arm))
        t.isFalse(s.transition(.pause(Date())))
        s = .armed
        t.isTrue(s.transition(.reset)); t.equal(s, .idle)
    },
    TestCase("elapsedExcludesPause") { t in
        let start = Date(timeIntervalSince1970: 0)
        // recording with 3 s accumulated pause: at now = +10 → 7 s of real recording
        let rec = RecorderState.recording(started: start, accumulatedPause: 3)
        t.equal(rec.elapsedString(now: start.addingTimeInterval(10)), "0:07")
        t.equal(rec.elapsedString(now: start.addingTimeInterval(725)), "12:02")
        // paused freezes at since - started - acc, independent of now
        let paused = RecorderState.paused(started: start, accumulatedPause: 3,
                                          since: start.addingTimeInterval(20))
        t.equal(paused.elapsedString(now: start.addingTimeInterval(999)), "Paused · 0:17")
        t.isNil(RecorderState.idle.elapsedString(now: Date()))
    },
    TestCase("dockBadgeIsShortWhilePaused") { t in
        let start = Date(timeIntervalSince1970: 0)
        let rec = RecorderState.recording(started: start, accumulatedPause: 3)
        t.equal(rec.badgeString(now: start.addingTimeInterval(10)), "0:07")
        let paused = RecorderState.paused(started: start, accumulatedPause: 3,
                                          since: start.addingTimeInterval(20))
        t.equal(paused.badgeString(now: start.addingTimeInterval(999)), "⏸ 0:17")
        t.isNil(RecorderState.idle.badgeString(now: Date()))
        t.isNil(RecorderState.armed.badgeString(now: Date()))
    },
]
