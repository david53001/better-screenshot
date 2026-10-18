import Foundation
import TestKit
@testable import CaptureKit

/// A throwaway defaults domain per test, so nothing touches the app's real preferences.
private func freshDefaults() -> UserDefaults {
    let name = "LaunchAtLoginPromptTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private typealias Prompt = LaunchAtLoginPrompt

/// A moment that is calm in every respect; each test spoils one field.
private let calm = Prompt.Moment(secondsSinceCapture: 10, secondsSinceKeyPress: 10, mouseButtonDown: false,
                                 captureOrRecordingActive: false, appIsActive: false)

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
        let prompt = Prompt(defaults: freshDefaults())
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
        let prompt = Prompt(defaults: freshDefaults())
        for _ in 1...5 { prompt.recordUse() }
        t.isFalse(prompt.recordUse())
        t.equal(prompt.uses, 5)
    },
    TestCase("keysAreTheDocumentedOnes") { t in
        let defaults = freshDefaults()
        let prompt = Prompt(defaults: defaults)
        prompt.recordUse()
        prompt.markAsked()
        t.equal(defaults.integer(forKey: "launchAtLoginPromptUses"), 1)
        t.isTrue(defaults.bool(forKey: "launchAtLoginPromptAsked"))
        t.equal(Prompt.Key.legacyAutoEnabled, "didRegisterLaunchAtLogin")
    },
    TestCase("askedIsForGood") { t in
        let defaults = freshDefaults()
        let prompt = Prompt(defaults: defaults)
        for _ in 1...5 { prompt.recordUse() }
        prompt.markAsked()
        t.isFalse(prompt.couldAsk)
        t.isFalse(prompt.recordUse(), "nothing is counted any more")
        // A new instance (next launch) reads the same answer.
        t.isFalse(Prompt(defaults: defaults).couldAsk)
    },
    TestCase("legacyFlagStopsCountingAndAsking") { t in
        let defaults = freshDefaults()
        defaults.set(true, forKey: Prompt.Key.legacyAutoEnabled)
        let prompt = Prompt(defaults: defaults)
        for _ in 1...6 { t.isFalse(prompt.recordUse()) }
        t.equal(prompt.uses, 0)
        t.isFalse(prompt.couldAsk)
        t.isFalse(prompt.shouldAsk(enabled: false))
    },
    TestCase("aChoiceInSettingsBeforeTheFifthUseMeansNeverAsked") { t in
        let prompt = Prompt(defaults: freshDefaults())
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
    },
    TestCase("calmMomentThresholdsAreInclusive") { t in
        var m = calm
        m.secondsSinceCapture = Prompt.settleSeconds
        m.secondsSinceKeyPress = Prompt.typingQuietSeconds
        t.isTrue(Prompt.isCalmMoment(m))
    },
]
