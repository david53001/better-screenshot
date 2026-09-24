import TestKit
import CoreGraphics
@testable import EditorKit

let inspectorModelTests: [TestCase] = [
    TestCase("strokeToolsShowColourStrokeOpacity") { t in
        for tool in [EditorTool.arrow, .line, .rectangle, .ellipse] {
            let c = InspectorModel.content(tool: tool, selection: [])
            t.equal(c.sections, [.colour, .stroke, .opacity], "\(tool)")
            t.equal(c.title, tool.displayName)
        }
    },
    TestCase("filledRectangleAndCounterShowColourOpacity") { t in
        t.equal(InspectorModel.content(tool: .filledRectangle, selection: []).sections, [.colour, .opacity])
        t.equal(InspectorModel.content(tool: .counter, selection: []).sections, [.colour, .opacity])
    },
    TestCase("textShowsColourFontBackgroundOpacity") { t in
        t.equal(InspectorModel.content(tool: .text, selection: []).sections,
                [.colour, .font, .background, .opacity])
    },
    TestCase("redactionAndCropTools") { t in
        t.equal(InspectorModel.content(tool: .blur, selection: []).sections, [.redaction, .strength])
        t.equal(InspectorModel.content(tool: .pixelate, selection: []).sections, [.redaction, .strength])
        t.equal(InspectorModel.content(tool: .blackout, selection: []).sections, [.redaction], "a solid box has no strength")
        t.equal(InspectorModel.content(tool: .blackout, selection: []).title, "Black-out")
        t.equal(InspectorModel.content(tool: .crop, selection: []).sections, [.cropHelp])
    },
    TestCase("drawingToolIgnoresItsSelectionForSections") { t in
        // The selection under a drawing tool is the object just drawn — same sections, no Arrange.
        t.equal(InspectorModel.content(tool: .arrow, selection: [.arrow]).sections,
                [.colour, .stroke, .opacity])
    },
    TestCase("selectWithNothingSelected") { t in
        let c = InspectorModel.content(tool: .select, selection: [])
        t.equal(c.title, "Nothing selected")
        t.equal(c.sections, [.selectHelp])
    },
    TestCase("selectWithOneObjectShowsItsSectionsPlusArrange") { t in
        let c = InspectorModel.content(tool: .select, selection: [.text])
        t.equal(c.title, "Text")
        t.equal(c.sections, [.colour, .font, .background, .opacity, .arrange])
        t.equal(InspectorModel.content(tool: .select, selection: [.blur]).sections, [.redaction, .strength, .arrange])
        t.equal(InspectorModel.content(tool: .select, selection: [.blackout]).title, "Black-out")
    },
    TestCase("selectWithSeveralShowsSharedSectionsPlusArrange") { t in
        let c = InspectorModel.content(tool: .select, selection: [.arrow, .text])
        t.equal(c.title, "2 objects")
        t.equal(c.sections, [.colour, .opacity, .arrange])
        t.equal(InspectorModel.content(tool: .select, selection: [.arrow, .rectangle]).sections,
                [.colour, .stroke, .opacity, .arrange])
        t.equal(InspectorModel.content(tool: .select, selection: [.arrow, .pixelate]).sections, [.arrange])
    },
    TestCase("redactionSelectionsShareStrengthOnlyWithinOneMode") { t in
        t.equal(InspectorModel.content(tool: .select, selection: [.blur, .blur]).sections,
                [.redaction, .strength, .arrange])
        t.equal(InspectorModel.content(tool: .select, selection: [.blur, .pixelate]).sections,
                [.redaction, .arrange], "one slider can't be a blur radius and a pixel size at once")
        t.equal(InspectorModel.content(tool: .select, selection: [.pixelate, .blackout]).sections,
                [.redaction, .arrange])
    },
    TestCase("sectionsKeepPanelOrder") { t in
        for tool in EditorTool.allCases {
            let s = InspectorModel.objectSections(for: tool)
            let order = s.compactMap { InspectorSection.allCases.firstIndex(of: $0) }
            t.equal(order, order.sorted(), "\(tool)")
        }
    },
    TestCase("hintsCoverEveryToolAndState") { t in
        for tool in EditorTool.allCases {
            t.isFalse(InspectorModel.hint(tool: tool, selection: [], editingText: false).isEmpty)
        }
        let editing = InspectorModel.hint(tool: .text, selection: [], editingText: true)
        t.isTrue(editing.contains("⇧↩"), "editing hint names the newline key")
        t.isTrue(InspectorModel.hint(tool: .select, selection: [.text], editingText: false)
                    .contains("double-click"))
        t.isTrue(InspectorModel.hint(tool: .select, selection: [.arrow, .text], editingText: false)
                    .contains("together"))
    },
    TestCase("toolShortcutsAreUniqueAndCaseInsensitive") { t in
        let keys = EditorTool.allCases.map(\.shortcutKey)
        t.equal(Set(keys).count, keys.count, "no two tools share a key")
        for tool in EditorTool.allCases {
            t.equal(EditorTool.forShortcut(String(tool.shortcutKey)), tool)
            t.equal(EditorTool.forShortcut(tool.shortcutKey.uppercased()), tool)
        }
        t.isNil(EditorTool.forShortcut("z"))
        t.isNil(EditorTool.forShortcut("ab"))
        t.equal(EditorTool.arrow.tooltip, "Arrow (A)")
        t.equal(EditorTool.filledRectangle.tooltip, "Filled Rectangle (F)")
    },
    TestCase("recentColoursAreMostRecentFirstUniqueAndCapped") { t in
        func c(_ v: CGFloat) -> RGBAColor { RGBAColor(r: v, g: 0, b: 0, a: 1) }
        var r = RecentColors()
        for i in 0..<8 { r.add(c(CGFloat(i) / 10)) }
        t.equal(r.colors.count, RecentColors.capacity)
        t.isTrue(RecentColors.same(r.colors[0], c(0.7)), "newest first")
        r.add(c(0.4))
        t.isTrue(RecentColors.same(r.colors[0], c(0.4)), "re-adding moves to front")
        t.equal(r.colors.count, RecentColors.capacity, "no duplicate")
        r.add(c(0.95), replacingFront: true)
        t.isTrue(RecentColors.same(r.colors[0], c(0.95)))
        t.isFalse(r.colors.contains { RecentColors.same($0, c(0.4)) }, "front entry replaced")
        let restored = RecentColors([c(0.1), c(0.1), c(0.2)])
        t.equal(restored.colors.count, 2, "init dedupes and keeps order")
        t.isTrue(RecentColors.same(restored.colors[0], c(0.1)))
    },
]

let zoomMathTests: [TestCase] = [
    TestCase("percentIsPerScreenPixel") { t in
        t.approxEqual(Double(ZoomMath.percent(magnification: 0.5, backingScale: 2)), 100)
        t.approxEqual(Double(ZoomMath.percent(magnification: 1, backingScale: 1)), 100)
        t.approxEqual(Double(ZoomMath.magnification(percent: 200, backingScale: 2)), 1)
    },
    TestCase("fitCoversBothDimensionsAndNeverUpscalesPastOnePointPerPixel") { t in
        t.approxEqual(Double(ZoomMath.fitMagnification(imageSize: CGSize(width: 2000, height: 1000),
                                                       available: CGSize(width: 1000, height: 1000))), 0.5)
        t.approxEqual(Double(ZoomMath.fitMagnification(imageSize: CGSize(width: 1000, height: 3000),
                                                       available: CGSize(width: 1000, height: 600))), 0.2)
        t.approxEqual(Double(ZoomMath.fitMagnification(imageSize: CGSize(width: 200, height: 100),
                                                       available: CGSize(width: 1000, height: 1000))), 1)
    },
    TestCase("clampRangeIsFitToEightHundred") { t in
        // Retina: 800% = m 4; fit 0.3 is the floor.
        t.approxEqual(Double(ZoomMath.clamp(10, fit: 0.3, backingScale: 2)), 4)
        t.approxEqual(Double(ZoomMath.clamp(0.1, fit: 0.3, backingScale: 2)), 0.3)
        // A small image fits at m 1 (200%) — 100% (m 0.5) is still reachable.
        t.approxEqual(Double(ZoomMath.clamp(0.2, fit: 1, backingScale: 2)), 0.5)
    },
    TestCase("stepsWalkTheStopTable") { t in
        t.approxEqual(Double(ZoomMath.steppedPercent(from: 100, zoomIn: true)), 150)
        t.approxEqual(Double(ZoomMath.steppedPercent(from: 57, zoomIn: true)), 75)
        t.approxEqual(Double(ZoomMath.steppedPercent(from: 57, zoomIn: false)), 50)
        t.approxEqual(Double(ZoomMath.steppedPercent(from: 800, zoomIn: true)), 800)
        t.approxEqual(Double(ZoomMath.steppedPercent(from: 10, zoomIn: false)), 10)
    },
    TestCase("anchoredZoomKeepsThePointUnderThePointer") { t in
        // Pointer over doc point (300, 200) with the view scrolled to (100, 50): after 2× the
        // same image point is at (600, 400) and must stay 200/150 points from the visible origin.
        let o = ZoomMath.anchoredOrigin(anchor: CGPoint(x: 300, y: 200), visibleOrigin: CGPoint(x: 100, y: 50),
                                        from: 1, to: 2)
        t.approxEqual(Double(o.x), 400)
        t.approxEqual(Double(o.y), 250)
        let back = ZoomMath.anchoredOrigin(anchor: CGPoint(x: 600, y: 400), visibleOrigin: o, from: 2, to: 1)
        t.approxEqual(Double(back.x), 100)
        t.approxEqual(Double(back.y), 50)
    },
    TestCase("labels") { t in
        t.equal(ZoomMath.label(percent: 56.6, isFit: true), "Fit · 57%")
        t.equal(ZoomMath.label(percent: 150, isFit: false), "150%")
        t.isTrue(ZoomMath.isFit(0.5004, fit: 0.5))
        t.isFalse(ZoomMath.isFit(0.52, fit: 0.5))
    },
]
