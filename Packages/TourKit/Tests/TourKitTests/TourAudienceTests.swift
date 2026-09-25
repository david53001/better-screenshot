import TestKit
@testable import TourKit

/// The owner's real preference keys (2026-09-25) — must classify as existing.
private let ownerKeys: Set<String> = [
    "didRegisterLaunchAtLogin", "captureSettings", "hotkeyBindings", "recordingConfig", "saveDirectory",
    "editorDefaultStyle", "editorRecentColors", "windowPlacement.annotate",
    "NSStatusItem Preferred Position Item-0", "NSWindow Frame NSColorPanel",
]

private func signals(keys: Set<String> = [], folder: Bool = false, granted: Bool = false,
                     bundle: String? = TourAudience.knownBundleIdentifier) -> TourAudience.Signals {
    TourAudience.Signals(preferenceKeys: keys, supportFolderHasContent: folder,
                         screenRecordingGranted: granted, bundleIdentifier: bundle)
}

let tourAudienceTests: [TestCase] = [
    TestCase("ownersRealKeySetIsExisting") { t in
        t.equal(TourAudience.classify(signals(keys: ownerKeys)), .existing)
    },
    TestCase("ownersKeysPlusTourKeysStillExisting") { t in
        t.equal(TourAudience.classify(signals(keys: ownerKeys.union(TourPreferenceKey.all))), .existing)
    },
    TestCase("nothingAtAllIsNew") { t in
        t.equal(TourAudience.classify(signals()), .new)
    },
    TestCase("onlyTourKeysIsNew") { t in
        t.equal(TourAudience.classify(signals(keys: TourPreferenceKey.all)), .new)
        t.equal(TourAudience.classify(signals(keys: ["tourAudience"])), .new)
    },
    TestCase("anySingleAppKeyIsExisting") { t in
        for key in ownerKeys.union(["RelaunchedAfterPermissionGrant", "windowPlacement.history",
                                    "NSStatusItem VisibleCC Item-0", "anythingElse"]) {
            t.equal(TourAudience.classify(signals(keys: [key])), .existing, key)
        }
    },
    TestCase("supportFolderContentAloneIsExisting") { t in
        t.equal(TourAudience.classify(signals(folder: true)), .existing)
    },
    TestCase("permissionAlreadyGrantedAloneIsExisting") { t in
        t.equal(TourAudience.classify(signals(granted: true)), .existing)
    },
    TestCase("unknownOrMissingBundleIdIsExisting") { t in
        t.equal(TourAudience.classify(signals(bundle: nil)), .existing)
        t.equal(TourAudience.classify(signals(bundle: "com.betterscreenshot.app")), .existing)
        t.equal(TourAudience.classify(signals(bundle: "")), .existing)
    },
    TestCase("storedValueParsingFailsSafe") { t in
        t.isNil(TourAudience(stored: nil))
        t.equal(TourAudience(stored: "new"), .new)
        t.equal(TourAudience(stored: "existing"), .existing)
        t.equal(TourAudience(stored: "New"), .existing)
        t.equal(TourAudience(stored: ""), .existing)
    },
    TestCase("tourKeysAreExactlyTheFive") { t in
        t.equal(TourPreferenceKey.all, ["tourAudience", "tourQuestionAnswered", "firstUseToursEnabled",
                                        "toursSeen", "toursPaused"])
    },
]
