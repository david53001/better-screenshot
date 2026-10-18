import Foundation
import TestKit
@testable import CaptureKit

/// In-memory storage, so a test run never writes a preferences file (a `UserDefaults(suiteName:)`
/// per test left one plist in ~/Library/Preferences each time).
private final class MemoryStore: LaunchAtLoginPromptStorage {
    var values: [String: Any] = [:]
    func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func set(_ value: Int, forKey key: String) { values[key] = value }
    func set(_ value: Bool, forKey key: String) { values[key] = value }
}

private typealias Prompt = LaunchAtLoginPrompt

/// A moment that is calm in every respect; each test spoils one field.
private let calm = Prompt.Moment(secondsSinceCapture: 10, secondsSinceKeyPress: 10, mouseButtonDown: false,
                                 captureOrRecordingActive: false, appIsActive: false, menuIsOpen: false)

/// A prompt that is due (5 uses recorded).
private func duePrompt(_ store: MemoryStore = MemoryStore()) -> Prompt {
    let prompt = Prompt(storage: store)
    for _ in 1...5 { prompt.recordUse() }
    return prompt
}

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
        prompt.recordUnansweredShowing()
        prompt.markAsked()
        t.equal(store.values["launchAtLoginPromptUses"] as? Int, 1)
        t.equal(store.values["launchAtLoginPromptUnansweredShowings"] as? Int, 1)
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
    },
    TestCase("calmMomentThresholdsAreInclusive") { t in
        var m = calm
        m.secondsSinceCapture = Prompt.settleSeconds
        m.secondsSinceKeyPress = Prompt.typingQuietSeconds
        t.isTrue(Prompt.isCalmMoment(m))
    },

    // MARK: The flow

    TestCase("afterCaptureStartsWaitingOnlyWhenDueAndHidden") { t in
        var statusReads = 0
        let off = { () -> Bool in statusReads += 1; return false }
        t.equal(Prompt.afterCapture(couldAsk: false, cardVisible: false, isEnabled: off), .nothing)
        t.equal(Prompt.afterCapture(couldAsk: true, cardVisible: true, isEnabled: off), .nothing)
        t.equal(statusReads, 0, "no XPC status call unless it could be due and the card is hidden")
        t.equal(Prompt.afterCapture(couldAsk: true, cardVisible: false, isEnabled: off), .startWaiting)
        t.equal(Prompt.afterCapture(couldAsk: true, cardVisible: false, isEnabled: { true }), .alreadyEnabled)
    },
    TestCase("alreadyEnabledMarksItAskedSoLaterCapturesSkipTheStatusCall") { t in
        // What the controller does with `.alreadyEnabled` (review L3).
        let prompt = duePrompt()
        if Prompt.afterCapture(couldAsk: prompt.couldAsk, cardVisible: false, isEnabled: { true }) == .alreadyEnabled {
            prompt.markAsked()
        }
        var statusReads = 0
        t.equal(Prompt.afterCapture(couldAsk: prompt.couldAsk, cardVisible: false,
                                    isEnabled: { statusReads += 1; return true }), .nothing)
        t.equal(statusReads, 0)
    },
    TestCase("waitStepWaitsForCalmThenShows") { t in
        var m = calm; m.secondsSinceKeyPress = 0
        var statusReads = 0
        t.equal(Prompt.waitStep(m, couldAsk: true, isEnabled: { statusReads += 1; return false }), .keepWaiting)
        t.equal(statusReads, 0, "the status is only read once the moment is calm")
        t.equal(Prompt.waitStep(calm, couldAsk: true, isEnabled: { false }), .show)
    },
    TestCase("waitStepGivesUpAfterTwoMinutesEvenIfCalm") { t in
        var m = calm
        m.secondsSinceCapture = Prompt.giveUpSeconds - 1
        t.equal(Prompt.waitStep(m, couldAsk: true, isEnabled: { false }), .show)
        m.secondsSinceCapture = Prompt.giveUpSeconds
        t.equal(Prompt.waitStep(m, couldAsk: true, isEnabled: { false }), .giveUp)
        m.secondsSinceKeyPress = 0
        t.equal(Prompt.waitStep(m, couldAsk: true, isEnabled: { false }), .giveUp)
    },
    TestCase("waitStepRechecksBeforeShowing") { t in
        t.equal(Prompt.waitStep(calm, couldAsk: false, isEnabled: { false }), .noLongerDue, "answered in Settings meanwhile")
        t.equal(Prompt.waitStep(calm, couldAsk: true, isEnabled: { true }), .alreadyEnabled, "turned on in System Settings meanwhile")
    },

    // MARK: An unanswered card

    TestCase("anUnansweredCardHidesAfterItsTimeButNotUnderThePointer") { t in
        t.isTrue(Prompt.unansweredHideSeconds >= 20 && Prompt.unansweredHideSeconds <= 30)
        t.isFalse(Prompt.shouldHideUnanswered(secondsShown: Prompt.unansweredHideSeconds - 1, pointerOnCard: false))
        t.isTrue(Prompt.shouldHideUnanswered(secondsShown: Prompt.unansweredHideSeconds, pointerOnCard: false))
        t.isFalse(Prompt.shouldHideUnanswered(secondsShown: 600, pointerOnCard: true), "the user is about to click")
    },
    TestCase("anIgnoredCardStaysDueUntilItsThirdShowing") { t in
        let store = MemoryStore()
        let prompt = duePrompt(store)
        t.equal(Prompt.maxShowings, 3)
        t.isFalse(prompt.recordUnansweredShowing())
        t.isTrue(prompt.couldAsk, "comes back after a later capture")
        t.isFalse(prompt.recordUnansweredShowing())
        t.isTrue(prompt.couldAsk)
        t.isTrue(prompt.recordUnansweredShowing(), "the third was the last")
        t.isFalse(prompt.couldAsk)
        t.isTrue(prompt.asked)
        t.isFalse(Prompt(storage: store).couldAsk, "still answered after a relaunch")
    },
]
