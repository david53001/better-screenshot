import TestKit
@testable import TourKit

private let editorV1 = Tour(id: .editor, surface: .editor, trigger: .surfaceShown(.editor), steps: [])
private let editorV2 = Tour(id: .editor, version: 2, surface: .editor, trigger: .surfaceShown(.editor), steps: [])

let tourRulesTests: [TestCase] = [
    TestCase("autoStartNeedsToursOnAndUnseen") { t in
        t.isTrue(TourRules.shouldAutoStart(editorV1, firstUseToursEnabled: true, seen: [:]))
        t.isFalse(TourRules.shouldAutoStart(editorV1, firstUseToursEnabled: false, seen: [:]))
        t.isFalse(TourRules.shouldAutoStart(editorV1, firstUseToursEnabled: true, seen: ["editor": 1]))
    },
    TestCase("autoStartDefaultsToOffWhenAbsent") { t in
        t.isFalse(TourRules.shouldAutoStart(editorV1, firstUseToursEnabled: nil, seen: [:]))
    },
    TestCase("versionBumpReoffersOnlyWhenToursOn") { t in
        t.isTrue(TourRules.shouldAutoStart(editorV2, firstUseToursEnabled: true, seen: ["editor": 1]))
        t.isFalse(TourRules.shouldAutoStart(editorV2, firstUseToursEnabled: true, seen: ["editor": 2]))
        t.isFalse(TourRules.shouldAutoStart(editorV2, firstUseToursEnabled: nil, seen: ["editor": 1]))
        t.isFalse(TourRules.shouldAutoStart(editorV2, firstUseToursEnabled: false, seen: [:]))
    },
    TestCase("seenIsPerTourId") { t in
        t.isFalse(TourRules.isSeen(editorV1, seen: ["text": 5]))
        t.isTrue(TourRules.isSeen(editorV1, seen: ["editor": 3]))
    },
    TestCase("questionOnlyForUnansweredNewUsers") { t in
        t.isTrue(TourRules.shouldAskQuestion(audience: .new, answered: false))
        t.isFalse(TourRules.shouldAskQuestion(audience: .new, answered: true))
        t.isFalse(TourRules.shouldAskQuestion(audience: .existing, answered: false))
        t.isFalse(TourRules.shouldAskQuestion(audience: nil, answered: false))
    },
    TestCase("welcomeOpensAtLaunchOnlyForUnansweredNewUsersWithPermission") { t in
        t.isTrue(TourRules.shouldOpenWelcomeOnLaunch(audience: .new, answered: false, permissionGranted: true))
        t.isFalse(TourRules.shouldOpenWelcomeOnLaunch(audience: .new, answered: false, permissionGranted: false))
        t.isFalse(TourRules.shouldOpenWelcomeOnLaunch(audience: .new, answered: true, permissionGranted: true))
        t.isFalse(TourRules.shouldOpenWelcomeOnLaunch(audience: .existing, answered: false, permissionGranted: true))
    },
    TestCase("toursTriggeredBy") { t in
        let ids = TourRules.tours(triggeredBy: .event(.toolSelected("text")), in: TourCatalog.all).map(\.id)
        t.equal(ids, [.text])
        t.equal(TourRules.tours(triggeredBy: .surfaceShown(.editor), in: TourCatalog.all).map(\.id), [.editor])
        t.equal(TourRules.tours(triggeredBy: .event(.captureTaken), in: TourCatalog.all).map(\.id), [])
    },
    TestCase("shortcutPlaceholdersResolveFromLookup") { t in
        let keys = ["captureArea": "⇧⌘4", "record": "⇧⌘5"]
        t.equal(TourText.resolvingShortcuts(in: "Press {shortcut:captureArea} and drag.") { keys[$0] },
                "Press ⇧⌘4 and drag.")
        t.equal(TourText.resolvingShortcuts(in: "{shortcut:captureArea} or {shortcut:record}") { keys[$0] },
                "⇧⌘4 or ⇧⌘5")
        t.equal(TourText.resolvingShortcuts(in: "No placeholders.") { keys[$0] }, "No placeholders.")
    },
    TestCase("unknownOrBrokenPlaceholdersAreLeftAlone") { t in
        let keys = ["captureArea": "⇧⌘4"]
        t.equal(TourText.resolvingShortcuts(in: "Press {shortcut:nope}.") { keys[$0] }, "Press {shortcut:nope}.")
        t.equal(TourText.resolvingShortcuts(in: "Press {shortcut:captureArea") { keys[$0] },
                "Press {shortcut:captureArea")
    },
    TestCase("shortcutNamesListsPlaceholders") { t in
        t.equal(TourText.shortcutNames(in: "a {shortcut:captureArea} b {shortcut:record}"), ["captureArea", "record"])
        t.equal(TourText.shortcutNames(in: "none"), [])
    },
    TestCase("menuTitlesAreTitleCaseTours") { t in
        for id in TourID.allCases {
            let words = id.menuTitle.split(separator: " ")
            t.equal(words.last.map(String.init), "Tour", id.rawValue)
            for word in words where word != "&" {
                t.isTrue(word.first?.isUppercase == true, "\(id.menuTitle) not Title Case")
            }
            t.isFalse(id.menuSymbol.isEmpty)
        }
    },
    TestCase("resetSaysHowToSeeToursWhenTheyAreOff") { t in
        t.equal(TourRules.resetConfirmation(firstUseToursEnabled: true), "Tours reset")
        for off in [false, nil] as [Bool?] {
            t.equal(TourRules.resetConfirmation(firstUseToursEnabled: off),
                    "Tours reset — turn on Tours & tips to see them again")
        }
    },
]
