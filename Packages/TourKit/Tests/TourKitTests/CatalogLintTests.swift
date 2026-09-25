import Foundation
import TestKit
@testable import TourKit

/// `HotkeyAction` raw values (CaptureKit). TourKit doesn't depend on CaptureKit, so the list lives here:
/// add a new action's raw value when one is added to `HotkeyAction`.
let hotkeyActionRawValues: Set<String> = [
    "captureArea", "captureWindow", "captureFullscreen", "captureText", "pinFromClipboard", "record",
    "openHistory", "restoreRecentlyClosed", "pauseResumeRecording",
]

/// Copy rules (spec §14.3): title ≤ 4 words; body ≤ 20 words and ≤ 2 sentences; Try bodies start with a
/// verb; anchors and event names look like "<surface>.<name>"; placeholders name real hotkey actions.
enum CatalogLint {
    static let maxTitleWords = 4
    static let maxBodyWords = 20
    static let maxSentences = 2
    /// Words a Try step's body must not start with (it should start with a verb: "Pick", "Drag"…).
    static let notVerbs: Set<String> = ["this", "these", "that", "the", "your", "a", "an", "here", "it", "you"]

    /// A word is a token with a letter or digit (so "—" and "·" don't count); a placeholder is one word.
    static func words(_ text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace).filter { $0.contains { $0.isLetter || $0.isNumber } }
    }

    static func sentenceCount(_ text: String) -> Int {
        let pieces = text.components(separatedBy: CharacterSet(charactersIn: ".!?…"))
        return max(1, pieces.filter { $0.contains { $0.isLetter || $0.isNumber } }.count)
    }

    static func isAnchorShaped(_ s: String) -> Bool {
        s.range(of: #"^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)+$"#, options: .regularExpression) != nil
    }

    static func isName(_ s: String) -> Bool {
        s.range(of: #"^[a-z][A-Za-z0-9]*$"#, options: .regularExpression) != nil
    }

    /// Every problem with one step, as readable strings (empty = fine).
    static func problems(_ step: TourStep, in tour: TourID) -> [String] {
        let at = "\(tour.rawValue)/\(step.anchor)"
        var out: [String] = []
        let titleWords = words(step.title).count
        if titleWords == 0 || titleWords > maxTitleWords { out.append("\(at): title has \(titleWords) words") }
        let bodyWords = words(step.body).count
        if bodyWords == 0 || bodyWords > maxBodyWords { out.append("\(at): body has \(bodyWords) words") }
        if sentenceCount(step.body) > maxSentences { out.append("\(at): body has more than 2 sentences") }
        if !isAnchorShaped(step.anchor) { out.append("\(at): anchor isn't <surface>.<name>") }
        for name in TourText.shortcutNames(in: step.body) where !hotkeyActionRawValues.contains(name) {
            out.append("\(at): {shortcut:\(name)} isn't a HotkeyAction")
        }
        let stripped = TourText.resolvingShortcuts(in: step.body) { _ in "" }
        if stripped.contains("{") || stripped.contains("}") || step.title.contains("{") {
            out.append("\(at): stray brace — placeholders are {shortcut:<action>} in the body only")
        }
        if case .tryIt(let event) = step.kind {
            if let first = words(step.body).first, notVerbs.contains(first.lowercased()) {
                out.append("\(at): Try body should start with a verb, not \"\(first)\"")
            }
            switch event {
            case .captureTaken: break
            case .toolSelected(let n), .annotationAdded(let n), .styleChanged(let n):
                if !isName(n) { out.append("\(at): event name \"\(n)\" isn't lowerCamel") }
            case .menuOpened(let a), .choiceMade(let a), .action(let a):
                if !isAnchorShaped(a) { out.append("\(at): event \"\(a)\" isn't <surface>.<name>") }
            }
        }
        return out
    }

    /// Step problems, plus: no two Try steps in one tour wait for the same event (the engine would
    /// skip the second as "already done").
    static func problems(_ tour: Tour) -> [String] {
        var out = tour.steps.flatMap { problems($0, in: tour.id) }
        var awaited: Set<TourEvent> = []
        for s in tour.steps {
            guard case .tryIt(let event) = s.kind else { continue }
            if !awaited.insert(event).inserted { out.append("\(tour.id.rawValue): two Try steps wait for \(event)") }
        }
        return out
    }
}

private func step(_ title: String, _ body: String, anchor: String = "editor.toolbar",
                  kind: TourStep.Kind = .explain) -> TourStep {
    TourStep(anchor: anchor, kind: kind, title: title, body: body)
}

let catalogLintTests: [TestCase] = [
    // The real catalog (bites once the Part 7 lanes fill the steps).
    TestCase("everyCatalogStepPassesTheCopyRules") { t in
        for tour in TourCatalog.all {
            for problem in CatalogLint.problems(tour) { t.fail(problem) }
        }
    },

    // The lint itself (so it's known to bite).
    TestCase("lintAcceptsGoodCopy") { t in
        t.equal(CatalogLint.problems(step("The colours", "Pick any swatch. The arrow changes colour."), in: .editor), [])
        t.equal(CatalogLint.problems(step("Take a screenshot", "Press {shortcut:captureArea} and drag — any area works.",
                                         anchor: "welcome.shortcuts", kind: .tryIt(advanceOn: .captureTaken)),
                                    in: .welcome), [])
        t.equal(CatalogLint.problems(step("Open the menu", "Click the Microphone menu.", anchor: "strip.microphone",
                                         kind: .tryIt(advanceOn: .menuOpened("strip.microphone"))),
                                    in: .firstRecording), [])
    },
    TestCase("lintRejectsLongTitle") { t in
        t.equal(CatalogLint.problems(step("This title is five words", "Fine."), in: .editor).count, 1)
    },
    TestCase("lintRejectsLongBody") { t in
        let body = Array(repeating: "word", count: 21).joined(separator: " ")
        t.equal(CatalogLint.problems(step("Title", body), in: .editor).count, 1)
        let twenty = Array(repeating: "word", count: 20).joined(separator: " ") + " —"
        t.equal(CatalogLint.problems(step("Title", twenty), in: .editor), [])
    },
    TestCase("lintRejectsThreeSentences") { t in
        t.equal(CatalogLint.problems(step("Title", "One. Two. Three."), in: .editor).count, 1)
        t.equal(CatalogLint.problems(step("Title", "One! Two?"), in: .editor), [])
    },
    TestCase("lintRejectsBadAnchors") { t in
        for bad in ["toolbar", "Editor.toolbar", "editor.", ".toolbar", "editor toolbar", "editor.tool-bar"] {
            t.equal(CatalogLint.problems(step("Title", "Body.", anchor: bad), in: .editor).count, 1, bad)
        }
        t.equal(CatalogLint.problems(step("Title", "Body.", anchor: "editor.inspector.colour"), in: .editor), [])
    },
    TestCase("lintRejectsUnknownShortcutsAndStrayBraces") { t in
        t.equal(CatalogLint.problems(step("Title", "Press {shortcut:captureEverything}."), in: .editor).count, 1)
        t.equal(CatalogLint.problems(step("Title", "Press {shortcut captureArea}."), in: .editor).count, 1)
        t.equal(CatalogLint.problems(step("Title {x}", "Body."), in: .editor).count, 1)
        for raw in hotkeyActionRawValues {
            t.equal(CatalogLint.problems(step("Title", "Press {shortcut:\(raw)}."), in: .editor), [], raw)
        }
    },
    TestCase("lintRejectsTryBodyNotStartingWithVerb") { t in
        let s = step("Title", "The Arrow draws arrows.", kind: .tryIt(advanceOn: .toolSelected("arrow")))
        t.equal(CatalogLint.problems(s, in: .editor).count, 1)
    },
    TestCase("lintRejectsTwoTryStepsOnOneEvent") { t in
        let a = step("Pick it", "Pick the arrow.", anchor: "editor.a", kind: .tryIt(advanceOn: .toolSelected("arrow")))
        let b = step("Again", "Pick it again.", anchor: "editor.b", kind: .tryIt(advanceOn: .toolSelected("arrow")))
        let tour = Tour(id: .editor, surface: .editor, trigger: .surfaceShown(.editor), steps: [a, b])
        t.equal(CatalogLint.problems(tour).count, 1)
    },
    TestCase("lintRejectsBadEventNames") { t in
        let bad1 = step("Title", "Open it.", kind: .tryIt(advanceOn: .menuOpened("microphone")))
        let bad2 = step("Title", "Pick it.", kind: .tryIt(advanceOn: .toolSelected("Text Tool")))
        let bad3 = step("Title", "Split it.", kind: .tryIt(advanceOn: .action("split")))
        for s in [bad1, bad2, bad3] { t.equal(CatalogLint.problems(s, in: .editor).count, 1) }
        let good = step("Title", "Split it.", kind: .tryIt(advanceOn: .action("video.split")))
        t.equal(CatalogLint.problems(good, in: .videoEditor), [])
    },
]
