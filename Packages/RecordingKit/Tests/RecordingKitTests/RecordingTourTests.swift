import TestKit
import AppKit
import TourKit
@testable import RecordingKit

// Guided tours (v3 Part 7) for recording: the strip, the live pill and the video editor. The strip and
// pill live in the App target (checked by the lane's headless probe); the video editor's anchors and ⓘ
// are checked here, and every recording-tour body must fit the tag.

/// Height of `body` in the tag bubble's body label (same font, width and label type), with at most
/// `maxLines` lines (0 = unlimited). The widest a tag gets is `TagStyle.tagMaxWidth`.
@MainActor private func tagBodyHeight(_ body: String, maxLines: Int) -> CGFloat {
    let label = NSTextField(wrappingLabelWithString: body)
    label.font = TagStyle.bodyFont
    label.maximumNumberOfLines = maxLines
    label.lineBreakMode = .byWordWrapping
    let inner = TagStyle.tagMaxWidth - 2 * TagStyle.tagPaddingX
    label.preferredMaxLayoutWidth = inner
    return ceil(label.sizeThatFits(NSSize(width: inner, height: 1000)).height)
}

private let recordingTours: [TourID] = [.firstRecording, .recordingPill, .videoEditor]

let recordingTourTests: [TestCase] = [
    TestCase("everyRecordingTourBodyFitsTheTagsTwoLines") { t in
        // The 20-word lint doesn't guarantee it (an 18-word editor body was cut off with "…").
        MainActor.assumeIsolated {
            for id in recordingTours {
                for step in TourCatalog.tour(id).steps {
                    // A `{shortcut:…}` shows the user's own combo: measure the default look and the longest
                    // (same list as TourKit's TagFitTests).
                    for keys in ["⇧⌘4", "⌃⌥⇧⌘4", "⌃⌥⇧⌘F12", TourText.unboundShortcut] {
                        let body = TourText.resolvingShortcuts(in: step.body) { _ in keys }
                        let full = tagBodyHeight(body, maxLines: 0)
                        let shown = tagBodyHeight(body, maxLines: TagStyle.bodyMaxLines)
                        t.isTrue(full <= shown, "\(id)/\(step.title) [\(keys)]: body needs \(full) pt, the tag shows \(shown)")
                    }
                }
            }
        }
    },
    TestCase("everyVideoEditorTourStepPointsAtARealControl") { t in
        MainActor.assumeIsolated {
            let controller = TrimWindowController(url: URL(fileURLWithPath: "/nonexistent/probe.mp4"))
            let window = controller.window!
            window.contentView?.layoutSubtreeIfNeeded()
            for step in TourCatalog.tour(.videoEditor).steps {
                t.notNil(window.view(forTourAnchor: step.anchor), step.anchor)
            }
            t.equal(TourCatalog.tour(.videoEditor).surface, .videoEditor)
        }
    },
    TestCase("theVideoEditorInfoButtonReplaysItsTourAndListsItsKeys") { t in
        MainActor.assumeIsolated {
            let window = TrimWindowController(url: URL(fileURLWithPath: "/nonexistent/probe.mp4")).window!
            guard let info = t.unwrap(window.titlebarAccessoryViewControllers.first?.view.subviews.first
                                        as? InfoButton, "ⓘ is the rightmost title-bar accessory") else { return }
            t.equal(info.tour, .videoEditor)
            let keys = Dictionary(info.shortcuts.map { ($0.action, $0.keys) }, uniquingKeysWith: { a, _ in a })
            for (k, a) in [("Space", "Play or pause"), ("← →", "Step one frame"), ("S or ⌘B", "Split at the playhead"),
                           ("⌫", "Delete the selected part"), ("⌘Z", "Undo"), ("⇧⌘Z", "Redo")] {
                t.equal(keys[a], k, a)
            }
            t.equal(info.shortcuts.count, 8)
        }
    },
    TestCase("theRecordingToursHandOverAndWaitForPostedEvents") { t in
        t.equal(TourCatalog.tour(.firstRecording).handsOverTo, .recordingPill)
        t.equal(TourCatalog.tour(.firstRecording).trigger, .surfaceShown(.recordStrip))
        t.equal(TourCatalog.tour(.recordingPill).trigger, .surfaceShown(.recordingPill))
        t.equal(TourCatalog.tour(.videoEditor).trigger, .surfaceShown(.videoEditor))
        // The events the surfaces post (RecordStripController, RecordingControlsController,
        // RecordingCoordinator, TrimWindowController) — a Try step on anything else would never advance.
        let posted: Set<TourEvent> = [
            .menuOpened("strip.microphone"), .menuOpened("strip.systemAudio"), .choiceMade("strip.targets"),
            .action("pill.micMuted"), .action("recording.stopped"),
            .action("video.split"), .action("video.segmentDeleted"),
        ]
        for id in recordingTours {
            for step in TourCatalog.tour(id).steps {
                if case .tryIt(let event) = step.kind { t.isTrue(posted.contains(event), "\(id): \(event)") }
                if let needed = step.requires { t.isTrue(posted.contains(needed), "\(id): requires \(needed)") }
            }
        }
        // The pill tour runs over a live recording: no Try step may change it (a "Mute the mic" Try step
        // completed on mute and left the mic muted — review P2). Only Stop, which ends it anyway.
        for step in TourCatalog.tour(.recordingPill).steps {
            if case .tryIt(let event) = step.kind { t.equal(event, .action("recording.stopped"), step.title) }
        }
    },
]
