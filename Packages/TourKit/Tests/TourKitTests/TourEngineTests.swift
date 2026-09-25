import TestKit
@testable import TourKit

/// explain a · try b (arrow tool) · explain c · try d (annotation) · explain e
private let steps: [TourStep] = [
    TourStep(anchor: "editor.a", kind: .explain, title: "A", body: "A."),
    TourStep(anchor: "editor.b", kind: .tryIt(advanceOn: .toolSelected("arrow")), title: "B", body: "Pick b."),
    TourStep(anchor: "editor.c", kind: .explain, title: "C", body: "C."),
    TourStep(anchor: "editor.d", kind: .tryIt(advanceOn: .annotationAdded("arrow")), title: "D", body: "Draw d."),
    TourStep(anchor: "editor.e", kind: .explain, title: "E", body: "E."),
]
private let tour = Tour(id: .editor, surface: .editor, trigger: .surfaceShown(.editor), steps: steps,
                        handsOverTo: .text)
private let all: (String) -> Bool = { _ in true }
private func except(_ missing: String...) -> (String) -> Bool { { !missing.contains($0) } }

let tourEngineTests: [TestCase] = [
    TestCase("startsAtFirstStep") { t in
        var e = TourEngine(tour: tour)
        t.equal(e.start(isPresent: all), .show(step: 0))
        t.equal(e.status, .running)
    },
    TestCase("nextWalksExplainSteps") { t in
        var e = TourEngine(tour: tour)
        _ = e.start(isPresent: all)
        t.equal(e.next(isPresent: all), .show(step: 1))
    },
    TestCase("nextIsIgnoredOnTryStep") { t in
        var e = TourEngine(tour: tour)
        _ = e.start(at: 1, isPresent: all)
        t.equal(e.next(isPresent: all), .none)
        t.equal(e.current, 1)
    },
    TestCase("tryStepAdvancesOnlyOnItsExactEvent") { t in
        var e = TourEngine(tour: tour)
        _ = e.start(at: 1, isPresent: all)
        t.equal(e.handle(.toolSelected("text"), isPresent: all), .none)
        t.equal(e.handle(.annotationAdded("arrow"), isPresent: all), .none)
        t.equal(e.handle(.action("quickAccess.edit"), isPresent: all), .none)
        t.equal(e.current, 1)
        t.equal(e.handle(.toolSelected("arrow"), isPresent: all), .show(step: 2))
    },
    TestCase("eventsDoNothingOnExplainSteps") { t in
        var e = TourEngine(tour: tour)
        _ = e.start(isPresent: all)
        t.equal(e.handle(.toolSelected("arrow"), isPresent: all), .none)
        t.equal(e.current, 0)
    },
    TestCase("alreadyDoneTryStepIsSkipped") { t in
        var e = TourEngine(tour: tour)
        _ = e.start(isPresent: all)
        _ = e.handle(.toolSelected("arrow"), isPresent: all)   // done early, during step 0
        t.equal(e.next(isPresent: all), .show(step: 2))         // step 1 skipped silently
    },
    TestCase("skipStepMovesOnFromTryStep") { t in
        var e = TourEngine(tour: tour)
        _ = e.start(at: 1, isPresent: all)
        t.equal(e.skipStep(isPresent: all), .show(step: 2))
    },
    TestCase("missingAnchorsAreSkipped") { t in
        var e = TourEngine(tour: tour)
        t.equal(e.start(isPresent: except("editor.a", "editor.b")), .show(step: 2))
        t.equal(e.next(isPresent: except("editor.d")), .show(step: 4))
    },
    TestCase("anchorVanishingMidStepSkipsIt") { t in
        var e = TourEngine(tour: tour)
        _ = e.start(at: 2, isPresent: all)
        t.equal(e.skipIfAnchorMissing(isPresent: all), .none)
        t.equal(e.skipIfAnchorMissing(isPresent: except("editor.c")), .show(step: 3))
    },
    TestCase("startWithNothingPresentChangesNothing") { t in
        var e = TourEngine(tour: tour)
        t.equal(e.start(isPresent: { _ in false }), .nothingToShow)
        t.equal(e.status, .idle)
        var empty = TourEngine(tour: Tour(id: .settings, surface: .settings,
                                          trigger: .surfaceShown(.settings), steps: []))
        t.equal(empty.start(isPresent: all), .nothingToShow)
    },
    TestCase("lastNextFinishesWithHandOver") { t in
        var e = TourEngine(tour: tour)
        _ = e.start(at: 4, isPresent: all)
        t.equal(e.next(isPresent: all), .finished(handsOverTo: .text))
        t.equal(e.status, .finished)
        t.equal(e.next(isPresent: all), .none)
    },
    TestCase("finishingByTryEventOnLastStep") { t in
        let last = Tour(id: .welcome, surface: .welcome, trigger: .startedByApp, steps: [
            TourStep(anchor: "welcome.a", kind: .explain, title: "A", body: "A."),
            TourStep(anchor: "welcome.b", kind: .tryIt(advanceOn: .captureTaken), title: "B", body: "Take one."),
        ], handsOverTo: .quickAccess)
        var e = TourEngine(tour: last)
        _ = e.start(isPresent: all)
        _ = e.next(isPresent: all)
        t.equal(e.handle(.captureTaken, isPresent: all), .finished(handsOverTo: .quickAccess))
    },
    TestCase("trailingMissingAnchorsFinish") { t in
        var e = TourEngine(tour: tour)
        _ = e.start(at: 3, isPresent: all)
        t.equal(e.skipStep(isPresent: except("editor.e")), .finished(handsOverTo: .text))
    },
    TestCase("skipTourFromRunningOrPaused") { t in
        var e = TourEngine(tour: tour)
        _ = e.start(isPresent: all)
        t.equal(e.skipTour(), .skipped)
        t.equal(e.status, .skipped)
        t.equal(e.next(isPresent: all), .none)
        var p = TourEngine(tour: tour)
        _ = p.start(isPresent: all)
        _ = p.pause()
        t.equal(p.skipTour(), .skipped)
    },
    TestCase("pauseKeepsIndexAndResumeReturnsThere") { t in
        var e = TourEngine(tour: tour)
        _ = e.start(isPresent: all)
        _ = e.next(isPresent: all)
        _ = e.skipStep(isPresent: all)
        t.equal(e.pause(), .paused(at: 2))
        t.equal(e.handle(.annotationAdded("arrow"), isPresent: all), .none)   // paused: ignored
        t.equal(e.next(isPresent: all), .none)
        t.equal(e.resume(isPresent: all), .show(step: 2))
        t.equal(e.status, .running)
    },
    TestCase("resumeSkipsStepsNowMissing") { t in
        var e = TourEngine(tour: tour)
        _ = e.start(at: 2, isPresent: all)
        _ = e.pause()
        t.equal(e.resume(isPresent: except("editor.c")), .show(step: 3))
    },
    TestCase("resumeWithNothingPresentStaysPaused") { t in
        var e = TourEngine(tour: tour)
        _ = e.start(at: 2, isPresent: all)
        _ = e.pause()
        t.equal(e.resume(isPresent: { _ in false }), .nothingToShow)
        t.equal(e.status, .paused)
        t.equal(e.current, 2)
    },
    TestCase("startAtPersistedIndexAndOutOfRangeFallsBackToZero") { t in
        var e = TourEngine(tour: tour)
        t.equal(e.start(at: 3, isPresent: all), .show(step: 3))
        var f = TourEngine(tour: tour)
        t.equal(f.start(at: 99, isPresent: all), .show(step: 0))
        var g = TourEngine(tour: tour)
        t.equal(g.start(at: -1, isPresent: all), .show(step: 0))
    },
    TestCase("pauseWhenNotRunningDoesNothing") { t in
        var e = TourEngine(tour: tour)
        t.equal(e.pause(), .none)
        t.equal(e.resume(isPresent: all), .none)
    },
]
