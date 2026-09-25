import TestKit
import AppKit
import TourKit
@testable import EditorKit

// Guided tours (v3 Part 7): the editor's anchors and events must match what `TourCatalog`'s editor
// tours name — a missing anchor or an event nobody posts makes a step silently skip or never advance.

private func plainImage(_ w: Int = 400, _ h: Int = 300) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

/// Records every tour event posted while `body` runs.
@MainActor private func events(during body: () -> Void) -> [TourEvent] {
    var seen: [TourEvent] = []
    let before = TourEvents.onEvent
    TourEvents.onEvent = { seen.append($0) }
    body()
    TourEvents.onEvent = before
    return seen
}

@MainActor private func choose(_ tool: EditorTool, in window: NSWindow) {
    guard let b = window.view(forTourAnchor: "editor.tool.\(tool.rawValue)") as? NSButton else { return }
    b.sendAction(b.action, to: b.target)
}

@MainActor private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }

/// The tool each editor tour runs under (the intro opens on the Arrow).
private let tourTool: [TourID: EditorTool] = [
    .editor: .arrow, .text: .text, .redaction: .blur, .highlighter: .highlighter, .spotlight: .spotlight,
]

/// Height of `body` in the tag bubble's body label (same font, width and label type), with at most
/// `maxLines` lines (0 = unlimited).
@MainActor private func tagBodyHeight(_ body: String, maxLines: Int) -> CGFloat {
    let label = NSTextField(wrappingLabelWithString: body)
    label.font = TagStyle.bodyFont
    label.maximumNumberOfLines = maxLines
    label.lineBreakMode = .byWordWrapping
    let inner = TagStyle.tagMaxWidth - 2 * TagStyle.tagPaddingX
    label.preferredMaxLayoutWidth = inner
    return ceil(label.sizeThatFits(NSSize(width: inner, height: 1000)).height)
}

let editorTourTests: [TestCase] = [
    TestCase("everyEditorTourBodyFitsTheTagsTwoLines") { t in
        // The word limit alone doesn't guarantee it: a long 18-word body was cut off with "…".
        MainActor.assumeIsolated {
            for tour in TourCatalog.all where tour.surface == .editor {
                for step in tour.steps {
                    // A `{shortcut:…}` shows the user's own combo: measure the default look and the longest
                    // (same list as TourKit's TagFitTests).
                    for keys in ["⇧⌘4", "⌃⌥⇧⌘4", "⌃⌥⇧⌘F12"] {
                        let body = TourText.resolvingShortcuts(in: step.body) { _ in keys }
                        let full = tagBodyHeight(body, maxLines: 0)
                        let shown = tagBodyHeight(body, maxLines: TagStyle.bodyMaxLines)
                        t.isTrue(full <= shown, "\(tour.id)/\(step.title) [\(keys)]: body needs \(full) pt, the tag shows \(shown)")
                    }
                }
            }
        }
    },
    TestCase("everyEditorTourStepPointsAtARealControl") { t in
        MainActor.assumeIsolated {
            let controller = EditorWindowController(image: plainImage())
            let window = controller.window!
            for tour in TourCatalog.all where tour.surface == .editor {
                guard let tool = t.unwrap(tourTool[tour.id], "\(tour.id) has a tool state") else { continue }
                choose(tool, in: window)
                window.contentView?.layoutSubtreeIfNeeded()
                for step in tour.steps {
                    t.notNil(window.view(forTourAnchor: step.anchor), "\(tour.id): \(step.anchor) under \(tool)")
                }
            }
        }
    },
    TestCase("everyToolButtonAndBottomBarControlIsAnchored") { t in
        MainActor.assumeIsolated {
            let window = EditorWindowController(image: plainImage()).window!
            let tools: [EditorTool] = [.select, .arrow, .line, .rectangle, .filledRectangle, .ellipse, .text,
                                       .counter, .highlighter, .blur, .pixelate, .spotlight, .crop]
            for tool in tools { t.notNil(window.view(forTourAnchor: "editor.tool.\(tool.rawValue)"), tool.rawValue) }
            for name in ["toolbar", "canvas", "inspector", "hint", "zoom", "imageSize", "actions", "done", "stack",
                         "save", "copy", "undo", "redo", "panelToggle", "info"] {
                t.notNil(window.view(forTourAnchor: "editor.\(name)"), name)
            }
        }
    },
    TestCase("theInfoButtonIsRightmostAndListsTheToolKeys") { t in
        MainActor.assumeIsolated {
            let window = EditorWindowController(image: plainImage()).window!
            guard let info = t.unwrap(window.view(forTourAnchor: "editor.info") as? InfoButton) else { return }
            t.equal(info.tour, .editor)
            t.equal(window.titlebarAccessoryViewControllers.first?.view.subviews.first, info, "index 0 = rightmost")
            let keys = Dictionary(info.shortcuts.map { ($0.action, $0.keys) }, uniquingKeysWith: { a, _ in a })
            for tool in EditorTool.allCases { t.equal(keys[tool.displayName], tool.shortcutKey.uppercased(), tool.rawValue) }
            for (k, a) in [("⌘Z", "Undo"), ("⇧⌘Z", "Redo"), ("⌥⌘I", "Show or hide the side panel"), ("⌘0", "Zoom to fit")] {
                t.equal(keys[a], k)
            }
        }
    },
    TestCase("toolChangesPostToolSelectedAndBlurOrPixelatePostTheRedactionTrigger") { t in
        MainActor.assumeIsolated {
            var controller: EditorWindowController!   // keeps the buttons' target alive
            t.equal(events { controller = EditorWindowController(image: plainImage()) }, [],
                    "opening on the Arrow isn't the user's choice")
            let window = controller.window!
            t.equal(events { choose(.text, in: window) }, [.toolSelected("text")])
            t.equal(events { choose(.blur, in: window) },
                    [.toolSelected("blur"), .action("editor.redactionToolChosen")])
            t.equal(events { choose(.pixelate, in: window) },
                    [.toolSelected("pixelate"), .action("editor.redactionToolChosen")])
            t.equal(events { choose(.highlighter, in: window) }, [.toolSelected("highlighter")])
        }
    },
    TestCase("aNewObjectPostsAnnotationAddedAndARedactionAlsoTheSharedEvent") { t in
        MainActor.assumeIsolated {
            let canvas = EditorCanvasView(document: EditorDocument(baseImage: plainImage()))
            t.equal(events { canvas.insert(ArrowAnnotation(start: .zero, end: CGPoint(x: 40, y: 40), style: .default)) },
                    [.annotationAdded("arrow")])
            t.equal(events { canvas.insert(TextAnnotation(text: "Hi", origin: .zero, style: .default)) },
                    [.annotationAdded("text")])
            var s = AnnotationStyle.default
            s.redactionMode = .pixelate
            let r = RedactionAnnotation(frame: CGRect(x: 0, y: 0, width: 50, height: 50), source: plainImage(), style: s)
            t.equal(events { canvas.insert(r) }, [.annotationAdded("pixelate"), .action("editor.redactionAdded")])
        }
    },
    TestCase("panelEditsPostStyleChanged") { t in
        MainActor.assumeIsolated {
            let controller = EditorWindowController(image: plainImage())
            let window = controller.window!
            guard let colour = t.unwrap(window.view(forTourAnchor: "editor.inspector.colour")),
                  let swatch = t.unwrap(allViews(colour).compactMap({ $0 as? SwatchButton }).first) else { return }
            t.equal(events { swatch.sendAction(swatch.action, to: swatch.target) }, [.styleChanged("strokeColor")])
            choose(.blur, in: window)
            window.contentView?.layoutSubtreeIfNeeded()
            guard let strength = t.unwrap(window.view(forTourAnchor: "editor.inspector.strength")),
                  let row = t.unwrap(allViews(strength).compactMap({ $0 as? LabeledSliderRow }).first) else { return }
            row.slider.doubleValue = 20
            // No mouse event in flight = a released slider, which is when the edit counts.
            t.equal(events { row.slider.sendAction(row.slider.action, to: row.slider.target) }, [.styleChanged("strength")])
        }
    },
    TestCase("escIsTheEditorsWhileItHasAJobForIt") { t in
        MainActor.assumeIsolated {
            let controller = EditorWindowController(image: plainImage())
            let window = controller.window!
            guard let claiming = t.unwrap(window as? TourEscapeClaiming) else { return }
            t.isTrue(claiming.claimsEscape, "Arrow → Esc goes back to Select")
            window.cancelOperation(nil)
            t.isFalse(claiming.claimsEscape, "Select with nothing selected → Esc is free to skip a tour")
        }
    },
]
