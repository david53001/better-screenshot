import Foundation
import TestKit
@testable import CaptureKit

/// In-memory storage, so a test run never writes a preferences file (a `UserDefaults(suiteName:)`
/// per test left one plist in ~/Library/Preferences each time).
private final class MemoryStore: LaunchAtLoginPromptStorage {
    var values: [String: Any] = [:]
    func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
    func set(_ value: Int, forKey key: String) { values[key] = value }
    func set(_ value: Bool, forKey key: String) { values[key] = value }
    func set(_ value: Double, forKey key: String) { values[key] = value }
}

private typealias Prompt = LaunchAtLoginPrompt

/// A moment that is calm in every respect; each test spoils one field.
private let calm = Prompt.Moment(secondsSinceCapture: 10, secondsSinceKeyPress: 10, mouseButtonDown: false,
                                 captureOrRecordingActive: false, appIsActive: false, menuIsOpen: false,
                                 fullScreenInFront: false)

/// A prompt that is due (5 uses recorded).
private func duePrompt(_ store: MemoryStore = MemoryStore()) -> Prompt {
    let prompt = Prompt(storage: store)
    for _ in 1...5 { prompt.recordUse() }
    return prompt
}

/// A showing followed for `seconds` one-second ticks.
private func showing(seconds: Int, visible: (Int) -> Bool = { _ in true },
                     secondsSinceInput: (Int) -> TimeInterval) -> Prompt.Showing {
    var s = Prompt.Showing()
    for second in 1...seconds {
        s.tick(seconds: 1, cardVisible: visible(second), secondsSinceInput: secondsSinceInput(second))
    }
    return s
}

/// A showing the user saw: the mouse moved a moment ago on every tick, card visible throughout.
private let seenShowing = showing(seconds: 25, secondsSinceInput: { _ in 0.3 })

private let t0 = Date(timeIntervalSince1970: 2_000_000_000)

let launchAtLoginPromptTests: [TestCase] = [
    // MARK: The decision

    TestCase("asksOnlyFromTheFifthUse") { t in
        t.equal(Prompt.usesBeforeAsking, 5)
        for uses in 0..<5 {
            t.isFalse(Prompt.shouldAsk(uses: uses, asked: false, legacyAutoEnabled: false, enabled: false), "\(uses) uses")
        }
        t.isTrue(Prompt.shouldAsk(uses: 5, asked: false, legacyAutoEnabled: false, enabled: false))
        t.isTrue(Prompt.shouldAsk(uses: 6, asked: false, legacyAutoEnabled: false, enabled: false))
    },
    TestCase("neverAsksWhenAlreadyEnabled") { t in
        t.isFalse(Prompt.shouldAsk(uses: 5, asked: false, legacyAutoEnabled: false, enabled: true))
    },
    TestCase("neverAsksTwice") { t in
        t.isFalse(Prompt.shouldAsk(uses: 5, asked: true, legacyAutoEnabled: false, enabled: false))
    },
    TestCase("neverAsksUsersOfTheOldAutoEnable") { t in
        // ≤ 3.1.0 turned it on at first launch: still on (nothing to do) or turned off on purpose.
        t.isFalse(Prompt.shouldAsk(uses: 5, asked: false, legacyAutoEnabled: true, enabled: false))
        t.isFalse(Prompt.shouldAsk(uses: 5, asked: false, legacyAutoEnabled: true, enabled: true))
    },

    // MARK: Counting, persisted

    TestCase("fiveRecordedUsesMakeItDue") { t in
        let prompt = Prompt(storage: MemoryStore())
        for i in 1...4 {
            t.isTrue(prompt.recordUse())
            t.isFalse(prompt.couldAsk, "after \(i)")
        }
        t.isTrue(prompt.recordUse())
        t.equal(prompt.uses, 5)
        t.isTrue(prompt.couldAsk)
        t.isTrue(prompt.shouldAsk(enabled: false))
        t.isFalse(prompt.shouldAsk(enabled: true))
    },
    TestCase("counterStopsAtTheThreshold") { t in
        let prompt = duePrompt()
        t.isFalse(prompt.recordUse())
        t.equal(prompt.uses, 5)
    },
    TestCase("keysAreTheDocumentedOnes") { t in
        let store = MemoryStore()
        let prompt = Prompt(storage: store)
        prompt.recordUse()
        prompt.cardHidUnanswered(seenShowing, now: t0)
        prompt.markAsked()
        t.equal(store.values["launchAtLoginPromptUses"] as? Int, 1)
        t.equal(store.values["launchAtLoginPromptUnansweredShowings"] as? Int, 1)
        t.equal(store.values["launchAtLoginPromptLastShownAt"] as? Double, t0.timeIntervalSince1970)
        t.equal(store.values["launchAtLoginPromptAsked"] as? Bool, true)
        t.equal(Prompt.Key.legacyAutoEnabled, "didRegisterLaunchAtLogin")
    },
    TestCase("userDefaultsIsTheAppsStorage") { t in
        // The app uses `LaunchAtLoginPrompt()`, i.e. the standard defaults; only read here.
        let standard: LaunchAtLoginPromptStorage = UserDefaults.standard
        t.equal(standard.integer(forKey: "LaunchAtLoginPromptTests.neverWritten"), 0)
    },
    TestCase("askedIsForGood") { t in
        let store = MemoryStore()
        let prompt = duePrompt(store)
        prompt.markAsked()
        t.isFalse(prompt.couldAsk)
        t.isFalse(prompt.recordUse(), "nothing is counted any more")
        // A new instance (next launch) reads the same answer.
        t.isFalse(Prompt(storage: store).couldAsk)
    },
    TestCase("legacyFlagStopsCountingAndAsking") { t in
        let store = MemoryStore()
        store.set(true, forKey: Prompt.Key.legacyAutoEnabled)
        let prompt = Prompt(storage: store)
        for _ in 1...6 { t.isFalse(prompt.recordUse()) }
        t.equal(prompt.uses, 0)
        t.isFalse(prompt.couldAsk)
        t.isFalse(prompt.shouldAsk(enabled: false))
    },
    TestCase("aChoiceInSettingsBeforeTheFifthUseMeansNeverAsked") { t in
        let prompt = Prompt(storage: MemoryStore())
        prompt.recordUse()
        prompt.markAsked()   // what the Settings switch does
        for _ in 1...5 { prompt.recordUse() }
        t.isFalse(prompt.couldAsk)
    },

    // MARK: Calm moment

    TestCase("calmMomentNeedsEveryCondition") { t in
        t.isTrue(Prompt.isCalmMoment(calm))
        var m = calm; m.secondsSinceCapture = 1
        t.isFalse(Prompt.isCalmMoment(m), "right after the capture")
        m = calm; m.secondsSinceKeyPress = 0.5
        t.isFalse(Prompt.isCalmMoment(m), "while typing")
        m = calm; m.mouseButtonDown = true
        t.isFalse(Prompt.isCalmMoment(m), "mid-drag")
        m = calm; m.captureOrRecordingActive = true
        t.isFalse(Prompt.isCalmMoment(m), "during a selection or recording")
        m = calm; m.appIsActive = true
        t.isFalse(Prompt.isCalmMoment(m), "while working in our editor or Settings")
        m = calm; m.menuIsOpen = true
        t.isFalse(Prompt.isCalmMoment(m), "while the menu-bar menu is open")
        m = calm; m.fullScreenInFront = true
        t.isFalse(Prompt.isCalmMoment(m), "while a full-screen app, presentation or game is in front")
    },
    TestCase("fullScreenInFrontMeansTheFrontmostAppCoversAWholeScreen") { t in
        typealias W = Prompt.WindowInfo
        // Primary 1512×982 without a notch at the origin; a second 1920×1080 screen above it, at x = -200.
        let screens = [Prompt.Screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
                       Prompt.Screen(frame: CGRect(x: -200, y: 982, width: 1920, height: 1080))]
        let front: Int32 = 42
        let full = W(ownerPID: front, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
        t.isTrue(Prompt.fullScreenInFront(frontmostPID: front, windows: [full], screens: screens))
        // The second screen's frame in window coordinates: top-left origin, y grows downwards.
        let fullOnSecond = W(ownerPID: front, layer: 0, bounds: CGRect(x: -200, y: -1080, width: 1920, height: 1080))
        t.isTrue(Prompt.fullScreenInFront(frontmostPID: front, windows: [fullOnSecond], screens: screens))
        // A presentation or game above the normal layer counts too.
        t.isTrue(Prompt.fullScreenInFront(frontmostPID: front, windows: [W(ownerPID: front, layer: 25, bounds: full.bounds)],
                                          screens: screens))
        // A zoomed window stops at the menu bar.
        let zoomed = W(ownerPID: front, layer: 0, bounds: CGRect(x: 0, y: 33, width: 1512, height: 949))
        t.isFalse(Prompt.fullScreenInFront(frontmostPID: front, windows: [zoomed], screens: screens))
        // The desktop (negative layer) and another app's full-screen window don't count.
        t.isFalse(Prompt.fullScreenInFront(frontmostPID: front, windows: [W(ownerPID: front, layer: -2147483603, bounds: full.bounds)],
                                           screens: screens))
        t.isFalse(Prompt.fullScreenInFront(frontmostPID: 7, windows: [full], screens: screens))
        t.isFalse(Prompt.fullScreenInFront(frontmostPID: nil, windows: [full], screens: screens))
        t.isFalse(Prompt.fullScreenInFront(frontmostPID: front, windows: [full], screens: []))
    },
    TestCase("fullScreenOnANotchedDisplayStartsBelowTheNotch") { t in
        typealias W = Prompt.WindowInfo
        // The owner's MacBook Air (Mac15,12), measured 2026-10-18 on macOS 26.7.1: screen 1470×956,
        // safe-area top 32; a real full-screen window is (0, 33, 1470, 923), and the app also owns
        // a layer-26 strip (0, 0, 1470, 33) and a layer-0 one (0, 33, 1470, 32) for the title bar.
        let air = [Prompt.Screen(frame: CGRect(x: 0, y: 0, width: 1470, height: 956), topInset: 32)]
        let front: Int32 = 42
        let measured = [W(ownerPID: front, layer: 26, bounds: CGRect(x: 0, y: 0, width: 1470, height: 33)),
                        W(ownerPID: front, layer: 0, bounds: CGRect(x: 0, y: 33, width: 1470, height: 32)),
                        W(ownerPID: front, layer: 0, bounds: CGRect(x: 0, y: 33, width: 1470, height: 923))]
        t.isTrue(Prompt.fullScreenInFront(frontmostPID: front, windows: measured, screens: air))
        t.isTrue(Prompt.fullScreenInFront(frontmostPID: front, windows: [measured[2]], screens: air), "the window alone")
        t.isFalse(Prompt.fullScreenInFront(frontmostPID: front, windows: Array(measured[0...1]), screens: air),
                  "the strips alone aren't a full-screen window")
        // Covering the notch row too (a game or presentation) still counts.
        t.isTrue(Prompt.fullScreenInFront(frontmostPID: front, windows: [W(ownerPID: front, layer: 0,
                                          bounds: CGRect(x: 0, y: 0, width: 1470, height: 956))], screens: air))
        // A zoomed window with the Dock shown stops above the Dock.
        t.isFalse(Prompt.fullScreenInFront(frontmostPID: front, windows: [W(ownerPID: front, layer: 0,
                                           bounds: CGRect(x: 0, y: 33, width: 1470, height: 860))], screens: air))
        // Dock on the left or right: not the full width.
        t.isFalse(Prompt.fullScreenInFront(frontmostPID: front, windows: [W(ownerPID: front, layer: 0,
                                           bounds: CGRect(x: 60, y: 33, width: 1410, height: 923))], screens: air))
        // Starts lower than just under the notch row.
        t.isFalse(Prompt.fullScreenInFront(frontmostPID: front, windows: [W(ownerPID: front, layer: 0,
                                           bounds: CGRect(x: 0, y: 40, width: 1470, height: 916))], screens: air))
        // The same rectangle on a screen without a notch is a zoomed window with the Dock hidden.
        let flat = [Prompt.Screen(frame: air[0].frame)]
        t.isFalse(Prompt.fullScreenInFront(frontmostPID: front, windows: [measured[2]], screens: flat))
        // Another app's full-screen window doesn't count.
        t.isFalse(Prompt.fullScreenInFront(frontmostPID: 7, windows: measured, screens: air))
        // The notched built-in display as the second screen, beside an external primary 1920×1080.
        let two = [Prompt.Screen(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                   Prompt.Screen(frame: CGRect(x: 1920, y: 0, width: 1470, height: 956), topInset: 32)]
        t.isTrue(Prompt.fullScreenInFront(frontmostPID: front, windows: [W(ownerPID: front, layer: 0,
                                          bounds: CGRect(x: 1920, y: 157, width: 1470, height: 923))], screens: two))
    },
    TestCase("calmMomentThresholdsAreInclusive") { t in
        var m = calm
        m.secondsSinceCapture = Prompt.settleSeconds
        m.secondsSinceKeyPress = Prompt.typingQuietSeconds
        t.isTrue(Prompt.isCalmMoment(m))
    },

    // MARK: The flow (each step applies its own side effects; the controller only acts on the result)

    TestCase("afterCaptureRecordsTheUseAndStartsWaitingOnlyWhenDueAndHidden") { t in
        let prompt = Prompt(storage: MemoryStore())
        var statusReads = 0
        let off = { () -> Bool in statusReads += 1; return false }
        for i in 1...4 {
            t.equal(prompt.afterCapture(cardVisible: false, isEnabled: off), .nothing, "capture \(i)")
        }
        t.equal(prompt.afterCapture(cardVisible: true, isEnabled: off), .nothing, "card already up")
        t.equal(prompt.uses, 5, "every capture was recorded by the step itself")
        t.equal(statusReads, 0, "no XPC status call unless it could be due and the card is hidden")
        t.equal(prompt.afterCapture(cardVisible: false, isEnabled: off), .startWaiting)
        t.equal(statusReads, 1)
        t.isFalse(prompt.asked)
    },
    TestCase("alreadyEnabledMarksItAskedSoLaterCapturesSkipTheStatusCall") { t in
        let prompt = duePrompt()
        t.equal(prompt.afterCapture(cardVisible: false, isEnabled: { true }), .alreadyEnabled)
        t.isTrue(prompt.asked, "afterCapture itself marked it asked")
        var statusReads = 0
        t.equal(prompt.afterCapture(cardVisible: false, isEnabled: { statusReads += 1; return true }), .nothing)
        t.equal(statusReads, 0)
    },
    TestCase("waitStepWaitsForCalmThenShows") { t in
        let prompt = duePrompt()
        var m = calm; m.secondsSinceKeyPress = 0
        var statusReads = 0
        t.equal(prompt.waitStep(m, isEnabled: { statusReads += 1; return false }), .keepWaiting)
        t.equal(statusReads, 0, "the status is only read once the moment is calm")
        t.equal(prompt.waitStep(calm, isEnabled: { false }), .show)
        t.isFalse(prompt.asked, "showing isn't answering")
    },
    TestCase("waitStepGivesUpAfterTwoMinutesEvenIfCalm") { t in
        let prompt = duePrompt()
        var m = calm
        m.secondsSinceCapture = Prompt.giveUpSeconds - 1
        t.equal(prompt.waitStep(m, isEnabled: { false }), .show)
        m.secondsSinceCapture = Prompt.giveUpSeconds
        t.equal(prompt.waitStep(m, isEnabled: { false }), .giveUp)
        m.secondsSinceKeyPress = 0
        t.equal(prompt.waitStep(m, isEnabled: { false }), .giveUp)
    },
    TestCase("waitStepRechecksBeforeShowing") { t in
        let answered = duePrompt()
        answered.markAsked()   // the Settings switch meanwhile
        t.equal(answered.waitStep(calm, isEnabled: { false }), .noLongerDue)
        let turnedOn = duePrompt()
        t.equal(turnedOn.waitStep(calm, isEnabled: { true }), .alreadyEnabled, "turned on in System Settings meanwhile")
        t.isTrue(turnedOn.asked, "waitStep itself marked it asked")
    },
    TestCase("theMenuOffersTheQuestionOnlyWhileItIsDue") { t in
        let prompt = Prompt(storage: MemoryStore())
        var statusReads = 0
        let off = { () -> Bool in statusReads += 1; return false }
        for _ in 1...4 { prompt.recordUse() }
        t.isFalse(prompt.offersMenuItem(isEnabled: off), "4 uses")
        t.equal(statusReads, 0, "no XPC status call before it is due")
        prompt.recordUse()
        t.isTrue(prompt.offersMenuItem(isEnabled: off))
        t.isFalse(prompt.asked, "offering isn't answering")
        let turnedOn = duePrompt()
        t.isFalse(turnedOn.offersMenuItem(isEnabled: { true }), "turned on in System Settings meanwhile")
        t.isTrue(turnedOn.asked, "found on: marked asked")
        let answered = duePrompt()
        answered.markAsked()
        t.isFalse(answered.offersMenuItem(isEnabled: off))
        let legacy = MemoryStore()
        legacy.values[Prompt.Key.legacyAutoEnabled] = true
        legacy.values[Prompt.Key.uses] = 5
        t.isFalse(Prompt(storage: legacy).offersMenuItem(isEnabled: off), "a ≤ 3.1.0 user")
    },

    // MARK: An unanswered card

    TestCase("anUnansweredCardHidesAfterItsTimeButNotUnderThePointer") { t in
        t.isTrue(Prompt.unansweredHideSeconds >= 20 && Prompt.unansweredHideSeconds <= 30)
        t.isFalse(Prompt.shouldHideUnanswered(secondsShown: Prompt.unansweredHideSeconds - 1, pointerOnCard: false))
        t.isTrue(Prompt.shouldHideUnanswered(secondsShown: Prompt.unansweredHideSeconds, pointerOnCard: false))
        t.isFalse(Prompt.shouldHideUnanswered(secondsShown: 600, pointerOnCard: true), "the user is about to click")
    },
    TestCase("aShowingCountsOnlyIfTheUserCouldHaveSeenIt") { t in
        t.isTrue(seenShowing.counts)
        t.equal(seenShowing.secondsShown, 25)
        // On another (full-screen) Space, covered, or the screen locked / asleep: never visible.
        t.isFalse(showing(seconds: 25, visible: { _ in false }, secondsSinceInput: { _ in 0.3 }).counts)
        // Walked away right after the capture: no input since the card appeared.
        t.isFalse(showing(seconds: 25, secondsSinceInput: { 60 + TimeInterval($0) }).counts)
        // Came back at second 22: only 4 s seen.
        t.isFalse(showing(seconds: 25, secondsSinceInput: { $0 >= 22 ? 0.5 : 60 + TimeInterval($0) }).counts)
        // Came back at second 20: 6 s seen.
        t.isTrue(showing(seconds: 25, secondsSinceInput: { $0 >= 20 ? 0.5 : 60 + TimeInterval($0) }).counts)
        // Moved the mouse once at second 3, then only read it: seen from then on.
        t.isTrue(showing(seconds: 25, secondsSinceInput: { $0 >= 3 ? TimeInterval($0) - 2.5 : 60 + TimeInterval($0) }).counts)
        // Visible only for 3 s (switched to a full-screen Space after that).
        t.isFalse(showing(seconds: 25, visible: { $0 <= 3 }, secondsSinceInput: { _ in 0.3 }).counts)
    },
    TestCase("aLateTickAfterSleepAddsAtMostTwoSeenSeconds") { t in
        var s = Prompt.Showing()
        s.tick(seconds: 3600, cardVisible: true, secondsSinceInput: 0.2)   // woke up with a key press
        t.equal(s.secondsShown, 3600, "wall-clock time, so it hides now")
        t.equal(s.secondsSeen, Prompt.Showing.maxSecondsPerTick)
        t.isFalse(s.counts)
    },
    TestCase("anUnseenShowingDoesNotCountAndOnlyDelaysTheNextOne") { t in
        let store = MemoryStore()
        let prompt = duePrompt(store)
        let unseen = showing(seconds: 25, visible: { _ in false }, secondsSinceInput: { _ in 0.3 })
        for _ in 1...5 { t.isFalse(prompt.cardHidUnanswered(unseen, now: t0)) }
        t.equal(prompt.unansweredShowings, 0)
        t.equal(prompt.secondsSinceLastShowing(now: t0), nil)
        t.isTrue(prompt.couldAsk)
        t.equal(prompt.afterCapture(cardVisible: false, unseenShowingEndedAt: t0,
                                    now: t0.addingTimeInterval(60), isEnabled: { false }),
                .tooSoon, "not on the very next screenshot")
        t.equal(prompt.afterCapture(cardVisible: false, unseenShowingEndedAt: t0,
                                    now: t0.addingTimeInterval(Prompt.reshowAfterUnseenSeconds), isEnabled: { false }),
                .startWaiting, "ten minutes later")
        t.equal(prompt.afterCapture(cardVisible: false, now: t0.addingTimeInterval(60),
                                    isEnabled: { false }),
                .startWaiting, "after a relaunch (the app only keeps the unseen time in memory)")
    },
    TestCase("aSeenShowingComesBackOnlyADayLaterEvenAfterARelaunch") { t in
        let store = MemoryStore()
        let prompt = duePrompt(store)
        t.isTrue(prompt.cardHidUnanswered(seenShowing, now: t0))
        t.equal(prompt.unansweredShowings, 1)
        var statusReads = 0
        let off = { () -> Bool in statusReads += 1; return false }
        // A burst of screenshots: not again within the day.
        let burst: [TimeInterval] = [1, 3, 60, 23 * 60]
        for minutes in burst {
            t.equal(prompt.afterCapture(cardVisible: false, now: t0.addingTimeInterval(minutes * 60), isEnabled: off),
                    .tooSoon, "\(minutes) min later")
        }
        // Relaunched (an automatic update, or the user reopened it): the stored time still holds.
        let relaunched = Prompt(storage: store)
        t.equal(relaunched.afterCapture(cardVisible: false, now: t0.addingTimeInterval(60), isEnabled: off),
                .tooSoon, "a relaunch a minute later")
        t.equal(relaunched.afterCapture(cardVisible: false, now: t0.addingTimeInterval(Prompt.reshowAfterSeconds - 60),
                                        isEnabled: off), .tooSoon, "a relaunch the next morning, under 24 h")
        t.equal(statusReads, 0, "no status call while spaced out")
        t.equal(relaunched.afterCapture(cardVisible: false, now: t0.addingTimeInterval(Prompt.reshowAfterSeconds),
                                        isEnabled: off), .startWaiting, "a day later")
        t.isTrue(Prompt.mayShowAgain(secondsSinceLastShowing: nil), "never shown yet")
        t.isTrue(Prompt.mayShowAgain(secondsSinceLastShowing: -3600), "the clock was set back")
    },
    TestCase("anIgnoredCardStaysDueUntilItsThirdSeenShowing") { t in
        let store = MemoryStore()
        let prompt = duePrompt(store)
        t.equal(Prompt.maxShowings, 3)
        t.isTrue(prompt.cardHidUnanswered(seenShowing, now: t0))
        t.isTrue(prompt.couldAsk, "comes back after a later capture")
        t.isTrue(prompt.cardHidUnanswered(seenShowing, now: t0.addingTimeInterval(Prompt.reshowAfterSeconds)))
        t.isTrue(prompt.couldAsk)
        t.isTrue(prompt.cardHidUnanswered(seenShowing, now: t0.addingTimeInterval(2 * Prompt.reshowAfterSeconds)))
        t.equal(prompt.unansweredShowings, 3, "the third was the last")
        t.isFalse(prompt.couldAsk)
        t.isTrue(prompt.asked)
        t.isFalse(Prompt(storage: store).couldAsk, "still answered after a relaunch")
    },
    TestCase("recordUnansweredShowingCapsAtThree") { t in
        let prompt = duePrompt()
        t.isFalse(prompt.recordUnansweredShowing())
        t.isFalse(prompt.recordUnansweredShowing())
        t.isTrue(prompt.recordUnansweredShowing())
        t.isTrue(prompt.asked)
    },
]
