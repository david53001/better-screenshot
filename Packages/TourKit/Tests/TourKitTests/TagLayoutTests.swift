import AppKit
import TestKit
@testable import TourKit

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)   // visible frame (menu bar excluded)
private let tagSize = CGSize(width: 240, height: 90)
private let margin = TagStyle.screenMargin
private let gap = TagStyle.leaderLength

private func inside(_ r: CGRect, _ area: CGRect) -> Bool {
    r.minX >= area.minX - 0.001 && r.maxX <= area.maxX + 0.001
        && r.minY >= area.minY - 0.001 && r.maxY <= area.maxY + 0.001
}

private func onEdge(_ p: CGPoint, of r: CGRect) -> Bool {
    let onX = abs(p.x - r.minX) < 0.001 || abs(p.x - r.maxX) < 0.001
    let onY = abs(p.y - r.minY) < 0.001 || abs(p.y - r.maxY) < 0.001
    let withinX = p.x >= r.minX - 0.001 && p.x <= r.maxX + 0.001
    let withinY = p.y >= r.minY - 0.001 && p.y <= r.maxY + 0.001
    return (onX && withinY) || (onY && withinX)
}

let tagLayoutTests: [TestCase] = [
    TestCase("boxIsTheAnchorGrownByThePaddingAndOuterByTheStroke") { t in
        let p = TagLayout.place(anchor: CGRect(x: 600, y: 400, width: 50, height: 20), tagSize: tagSize, visible: screen)
        t.equal(p.box, CGRect(x: 596, y: 396, width: 58, height: 28))
        t.equal(p.outer, CGRect(x: 594, y: 394, width: 62, height: 32))
    },
    TestCase("prefersLeftLikeTheMock") { t in
        let anchor = CGRect(x: 800, y: 400, width: 100, height: 30)
        let p = TagLayout.place(anchor: anchor, tagSize: tagSize, visible: screen)
        t.equal(p.side, .left)
        t.equal(p.tag.maxX, p.outer.minX - gap)
        t.equal(p.tag.midY, p.box.midY)
        t.equal(p.tag.size, tagSize)
        // Straight leader from the tag's right edge to the box's left edge.
        t.equal(p.leader?.from, CGPoint(x: p.tag.maxX, y: p.box.midY))
        t.equal(p.leader?.to, CGPoint(x: p.outer.minX, y: p.box.midY))
    },
    TestCase("rightWhenNoRoomOnTheLeft") { t in
        let p = TagLayout.place(anchor: CGRect(x: 60, y: 400, width: 100, height: 30), tagSize: tagSize, visible: screen)
        t.equal(p.side, .right)
        t.equal(p.tag.minX, p.outer.maxX + gap)
        t.equal(p.leader?.from.x, p.tag.minX)
        t.equal(p.leader?.to.x, p.outer.maxX)
    },
    TestCase("menuBarIconGetsTheTagBelowIt") { t in
        // Status item button in the menu bar: above the visible frame (screen is 900 tall).
        let icon = CGRect(x: 1200, y: 878, width: 22, height: 22)
        let p = TagLayout.place(anchor: icon, tagSize: tagSize, visible: screen)
        t.equal(p.side, .below)
        t.equal(p.tag.maxY, p.outer.minY - gap)
        t.isTrue(inside(p.tag, screen.insetBy(dx: margin, dy: margin)), "tag \(p.tag) off the visible frame")
        t.equal(p.leader?.to, CGPoint(x: p.box.midX, y: p.outer.minY))
    },
    TestCase("menuBarIconAtTheRightEdgeSlidesTheTagLeftButStaysUnderIt") { t in
        let icon = CGRect(x: 1410, y: 878, width: 22, height: 22)
        let p = TagLayout.place(anchor: icon, tagSize: tagSize, visible: screen)
        t.equal(p.side, .below)
        t.equal(p.tag.maxX, screen.maxX - margin)
        t.isTrue(p.tag.maxX > p.box.minX, "tag no longer under the icon")
        // The leader leaves the tag away from its rounded corner.
        t.isTrue(p.leader!.from.x <= p.tag.maxX - TagStyle.tagRadius)
    },
    TestCase("verticalFirstPutsTheTagBelowAControlInABar") { t in
        let button = CGRect(x: 600, y: 700, width: 28, height: 28)
        let p = TagLayout.place(anchor: button, tagSize: tagSize, visible: screen,
                                order: TagLayout.order(verticalFirst: true))
        t.equal(p.side, .below)
        t.equal(p.tag.midX, p.box.midX)
    },
    TestCase("aboveWhenNothingFitsBesideOrBelow") { t in
        // A record-strip-like control: wide, at the bottom of the screen.
        let strip = CGRect(x: 20, y: 20, width: 1400, height: 40)
        let p = TagLayout.place(anchor: strip, tagSize: tagSize, visible: screen)
        t.equal(p.side, .above)
        t.equal(p.tag.minY, p.outer.maxY + gap)
    },
    TestCase("slidesDownFromTheTopEdgeButKeepsTouchingTheBox") { t in
        let anchor = CGRect(x: 800, y: 850, width: 100, height: 20)
        let p = TagLayout.place(anchor: anchor, tagSize: tagSize, visible: screen)
        t.equal(p.side, .left)
        t.equal(p.tag.maxY, screen.maxY - margin)
        t.isTrue(p.tag.minY < p.box.maxY && p.tag.maxY > p.box.minY)
        // Leader meets the tag's edge below its rounded corner.
        t.isTrue(p.leader!.from.y <= p.tag.maxY - TagStyle.tagRadius)
    },
    TestCase("overTheControlWhenNoSideHasRoom") { t in
        let huge = screen.insetBy(dx: 4, dy: 4)
        let p = TagLayout.place(anchor: huge, tagSize: tagSize, visible: screen)
        t.equal(p.side, .over)
        t.isNil(p.leader)
        t.isTrue(inside(p.tag, screen.insetBy(dx: margin, dy: margin)))
    },
    TestCase("secondScreenUsesItsOwnVisibleFrame") { t in
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        let p = TagLayout.place(anchor: CGRect(x: 1460, y: 300, width: 40, height: 40), tagSize: tagSize, visible: second)
        t.equal(p.side, .right)   // no room left of it on that screen
        t.isTrue(inside(p.tag, second.insetBy(dx: margin, dy: margin)))
    },
    TestCase("neverOffTheVisibleFrameAndLeaderJoinsTagToBox") { t in
        let area = screen.insetBy(dx: margin, dy: margin)
        var sides = Set<String>()
        for vertical in [false, true] {
            for x in stride(from: CGFloat(0), through: 1400, by: 70) {
                for y in stride(from: CGFloat(0), through: 860, by: 43) {
                    for size in [CGSize(width: 24, height: 24), CGSize(width: 320, height: 36), CGSize(width: 60, height: 400)] {
                        let anchor = CGRect(origin: CGPoint(x: x, y: y), size: size)
                        let p = TagLayout.place(anchor: anchor, tagSize: tagSize, visible: screen,
                                                order: TagLayout.order(verticalFirst: vertical))
                        sides.insert(p.side.rawValue)
                        if !inside(p.tag, area) { t.fail("tag \(p.tag) off screen for \(anchor)"); return }
                        if let l = p.leader {
                            if !onEdge(l.from, of: p.tag) { t.fail("leader \(l.from) not on tag \(p.tag)"); return }
                            if !onEdge(l.to, of: p.outer) { t.fail("leader \(l.to) not on box \(p.outer)"); return }
                            if p.tag.intersects(p.outer) { t.fail("tag \(p.tag) covers box \(p.outer)"); return }
                        }
                    }
                }
            }
        }
        t.equal(sides, ["left", "right", "below", "above"])
    },
    TestCase("smallPanelHostGetsTheTagOutsideTheWholePanel") { t in
        // The record strip near the bottom: the tag goes above the panel, not over its top row.
        let strip = CGRect(x: 400, y: 30, width: 640, height: 120)
        let mic = CGRect(x: 700, y: 60, width: 80, height: 22)
        let p = TagLayout.place(anchor: mic, tagSize: tagSize, visible: screen,
                                order: TagLayout.order(verticalFirst: true), keepOut: strip)
        t.equal(p.side, .above)
        t.equal(p.tag.minY, strip.maxY + gap)
        t.isFalse(p.tag.intersects(strip))
        t.equal(p.leader?.from.y, p.tag.minY)
        t.equal(p.leader?.to.y, p.outer.maxY)   // the leader reaches down to the box
    },
    TestCase("keepOutIsDroppedWhenNothingFitsOutsideIt") { t in
        let p = TagLayout.place(anchor: CGRect(x: 700, y: 400, width: 80, height: 22), tagSize: tagSize,
                                visible: screen, keepOut: screen)
        t.equal(p.side, .left)
        t.equal(p.tag.maxX, p.outer.minX - gap)
    },
    TestCase("menuBarBoxIsClippedToTheScreen") { t in
        let full = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let icon = CGRect(x: 1200, y: 875, width: 34, height: 25)   // fills the bar's height
        let p = TagLayout.place(anchor: icon, tagSize: tagSize, visible: screen, screen: full)
        t.equal(p.outer.maxY, full.maxY)
        t.equal(p.box.minY, icon.minY - TagStyle.boxPadding)
        t.equal(p.side, .below)
    },
    TestCase("barsPreferVertical") { t in
        t.isTrue(TagLayout.prefersVertical(containerSize: CGSize(width: 600, height: 40)))
        t.isTrue(TagLayout.prefersVertical(containerSize: CGSize(width: 90, height: 30)))
        t.isFalse(TagLayout.prefersVertical(containerSize: CGSize(width: 300, height: 400)))
        t.isFalse(TagLayout.prefersVertical(containerSize: CGSize(width: 80, height: 30)))
        t.isFalse(TagLayout.prefersVertical(containerSize: .zero))
    },
    TestCase("clampOfAnEmptyRangeIsItsMiddle") { t in
        t.equal(TagLayout.clamp(5, 10, 20), 10)
        t.equal(TagLayout.clamp(25, 10, 20), 20)
        t.equal(TagLayout.clamp(5, 20, 10), 15)
    },

    // MARK: A step's own placement (TourStep.placement)

    TestCase("aStepsSideWinsWhenItFits") { t in
        let anchor = CGRect(x: 800, y: 400, width: 100, height: 30)
        for (preferred, side) in [(TourStep.Placement.right, TagLayout.Side.right), (.above, .above), (.below, .below),
                                  (.left, .left)] {
            let p = TagLayout.place(anchor: anchor, tagSize: tagSize, visible: screen, preferred: preferred)
            t.equal(p.side, side, "\(preferred)")
            t.notNil(p.leader)
        }
    },
    TestCase("aStepsSideThatDoesntFitFallsBackToAutomatic") { t in
        // Right of a control at the screen's right edge: no room → the automatic order (left).
        let anchor = CGRect(x: 1300, y: 400, width: 100, height: 30)
        let p = TagLayout.place(anchor: anchor, tagSize: tagSize, visible: screen, preferred: .right)
        t.equal(p.side, .left)
    },
    TestCase("aStepsSideStillKeepsOffASmallPanel") { t in
        let strip = CGRect(x: 400, y: 300, width: 640, height: 120)
        let mic = CGRect(x: 700, y: 330, width: 80, height: 22)
        let p = TagLayout.place(anchor: mic, tagSize: tagSize, visible: screen, keepOut: strip, preferred: .below)
        t.equal(p.side, .below)
        t.equal(p.tag.maxY, strip.minY - gap)
    },
    TestCase("insideCornerPutsTheTagInTheControlsTopRightCorner") { t in
        let canvas = CGRect(x: 200, y: 150, width: 800, height: 600)
        let p = TagLayout.place(anchor: canvas, tagSize: tagSize, visible: screen, preferred: .insideCorner)
        t.equal(p.side, .insideCorner)
        t.isNil(p.leader)
        t.equal(p.tag.maxX, canvas.maxX - TagStyle.insideCornerInset)
        t.equal(p.tag.maxY, canvas.maxY - TagStyle.insideCornerInset)
        t.equal(p.box, canvas.insetBy(dx: -TagStyle.boxPadding, dy: -TagStyle.boxPadding))
    },
    TestCase("insideCornerOfATooSmallControlFallsBackToAutomatic") { t in
        let small = CGRect(x: 800, y: 400, width: 200, height: 60)
        let p = TagLayout.place(anchor: small, tagSize: tagSize, visible: screen, preferred: .insideCorner)
        t.equal(p.side, .left)
    },
    TestCase("insideCornerUsesTheVisiblePartOfTheControl") { t in
        // A tall scrolled control running past the window's top: the corner is the window's.
        let window = CGRect(x: 200, y: 100, width: 960, height: 700)
        let cards = CGRect(x: 224, y: 300, width: 912, height: 900)
        let p = TagLayout.place(anchor: cards, tagSize: tagSize, visible: screen, preferred: .insideCorner, host: window)
        t.equal(p.side, .insideCorner)
        t.equal(p.tag.maxY, window.maxY - TagStyle.insideCornerInset)
        t.equal(p.tag.maxX, cards.maxX - TagStyle.insideCornerInset)
    },

    // MARK: Big controls (review T3 — the editor canvas, the video preview, the Settings cards)

    TestCase("aBigControlSpansMostOfItsWindowBothWays") { t in
        let window = CGRect(x: 0, y: 0, width: 1000, height: 800)
        t.isTrue(TagLayout.isBig(anchor: CGRect(x: 0, y: 0, width: 700, height: 600), host: window))
        t.isFalse(TagLayout.isBig(anchor: CGRect(x: 0, y: 0, width: 260, height: 700), host: window))   // side panel
        t.isFalse(TagLayout.isBig(anchor: CGRect(x: 0, y: 0, width: 1000, height: 150), host: window))  // timeline
        // Settings: the three columns are big; the Keyboard Shortcuts card (half the area, a wide strip) isn't.
        let settings = CGRect(x: 255, y: 76, width: 960, height: 847)
        t.isTrue(TagLayout.isBig(anchor: CGRect(x: 273, y: 167, width: 923, height: 652), host: settings))
        t.isFalse(TagLayout.isBig(anchor: CGRect(x: 273, y: 76, width: 924, height: 458), host: settings))
        // The editor canvas and the video preview (measured in the probe).
        t.isTrue(TagLayout.isBig(anchor: CGRect(x: 169, y: 218, width: 848, height: 544),
                                 host: CGRect(x: 169, y: 154, width: 1132, height: 708)))
        t.isTrue(TagLayout.isBig(anchor: CGRect(x: 255, y: 394, width: 960, height: 458),
                                 host: CGRect(x: 255, y: 136, width: 960, height: 720)))
        // Only the part inside the window counts.
        t.isFalse(TagLayout.isBig(anchor: CGRect(x: 900, y: 0, width: 700, height: 800), host: window))
    },
    TestCase("aBigControlsTagGoesInsideItsCornerWhenItsWindowFillsTheScreen") { t in
        // The editor (1132 × 708, centred): no room beside the window, so not beside the canvas either
        // (that's over the side panel) — inside the canvas's top-right corner.
        let window = CGRect(x: 154, y: 84, width: 1132, height: 708)
        let canvas = CGRect(x: 154, y: 120, width: 852, height: 620)
        let p = TagLayout.place(anchor: canvas, tagSize: tagSize, visible: screen, host: window)
        t.equal(p.side, .insideCorner)
        t.isTrue(canvas.contains(p.tag))
        t.equal(p.tag.maxX, canvas.maxX - TagStyle.insideCornerInset)
        t.isNil(p.leader)
    },
    TestCase("aBigControlsTagGoesBesideTheWholeWindowWhenThereIsRoom") { t in
        // History (700 × 500) with its grid: left of the window, not over the window.
        let window = CGRect(x: 370, y: 190, width: 700, height: 500)
        let grid = CGRect(x: 370, y: 240, width: 700, height: 400)
        let p = TagLayout.place(anchor: grid, tagSize: tagSize, visible: screen, host: window)
        t.equal(p.side, .left)
        t.equal(p.tag.maxX, min(window.minX, p.outer.minX) - gap)   // clear of the window and the outline
        t.isFalse(p.tag.intersects(window))
    },
    TestCase("aSmallControlIgnoresItsWindow") { t in
        let window = CGRect(x: 154, y: 84, width: 1132, height: 708)
        let colour = CGRect(x: 1040, y: 500, width: 220, height: 60)   // inside the side panel
        let p = TagLayout.place(anchor: colour, tagSize: tagSize, visible: screen, host: window)
        t.equal(p.side, .left)
        t.equal(p.tag.maxX, p.outer.minX - gap)
    },
    TestCase("aStepsPlacementBeatsTheBigControlRule") { t in
        let window = CGRect(x: 154, y: 84, width: 1132, height: 708)
        let canvas = CGRect(x: 154, y: 120, width: 852, height: 620)
        let p = TagLayout.place(anchor: canvas, tagSize: tagSize, visible: screen, preferred: .above, host: window)
        t.equal(p.side, .above)
    },

    // MARK: Title bar (review E4)

    TestCase("titleBarControlsAreAboveTheContent") { t in
        let content = CGRect(x: 100, y: 100, width: 800, height: 600)   // window content layout rect (screen)
        t.isTrue(TagLayout.isInTitleBar(anchor: CGRect(x: 860, y: 704, width: 26, height: 22), contentLayout: content))
        t.isFalse(TagLayout.isInTitleBar(anchor: CGRect(x: 860, y: 660, width: 26, height: 22), contentLayout: content))
        // Treated as a bar: the tag goes below the ⓘ, not over the buttons beside it.
        let p = TagLayout.place(anchor: CGRect(x: 860, y: 704, width: 26, height: 22), tagSize: tagSize,
                                visible: screen, order: TagLayout.order(verticalFirst: true))
        t.equal(p.side, .below)
    },

    TestCase("aTagSlidesToStayWithinItsWindow") { t in
        // The editor's ⓘ, 6 pt from the window's right edge, with screen room to its right: the tag below it
        // ends at the window's edge instead of hanging past it — and the leader still drops straight down.
        let window = CGRect(x: 100, y: 84, width: 1000, height: 708)
        let info = CGRect(x: 1068, y: 766, width: 26, height: 22)
        let p = TagLayout.place(anchor: info, tagSize: tagSize, visible: screen,
                                order: TagLayout.order(verticalFirst: true), host: window)
        t.equal(p.side, .below)
        t.equal(p.tag.maxX, window.maxX)
        t.equal(p.leader?.from.x, p.leader?.to.x)
        // Without a host it's centred on the ⓘ, as before.
        let free = TagLayout.place(anchor: info, tagSize: tagSize, visible: screen,
                                   order: TagLayout.order(verticalFirst: true))
        t.equal(free.tag.midX, free.box.midX)
    },

    // MARK: Leader routing (review T5)

    TestCase("theLeaderSlidesIntoAGapBetweenControls") { t in
        // Tag above a panel; between it and the box a row of buttons with a gap at x 520–540.
        let box = CGRect(x: 400, y: 100, width: 260, height: 30)
        let tag = CGRect(x: 400, y: 250, width: 240, height: 90)
        let row = [CGRect(x: 380, y: 170, width: 140, height: 28), CGRect(x: 540, y: 170, width: 140, height: 28)]
        let (from, to) = TagLayout.leader(side: .above, tag: tag, box: box, outer: box.insetBy(dx: -2, dy: -2),
                                          obstacles: row)
        t.equal(from.x, to.x)
        t.isTrue(from.x > 520 && from.x < 540, "leader at x \(from.x) should run through the gap")
        let line = CGRect(x: from.x - 1, y: to.y, width: 2, height: from.y - to.y)
        t.isFalse(row.contains { $0.intersects(line) })
    },
    TestCase("theLeaderStaysInTheMiddleWhenNothingIsInTheWay") { t in
        let box = CGRect(x: 400, y: 100, width: 260, height: 30)
        let tag = CGRect(x: 410, y: 250, width: 240, height: 90)
        let (from, _) = TagLayout.leader(side: .above, tag: tag, box: box, outer: box.insetBy(dx: -2, dy: -2),
                                         obstacles: [CGRect(x: 900, y: 170, width: 50, height: 28)])
        t.equal(from.x, box.midX)
    },
    TestCase("anUnavoidableCrossingKeepsTheMiddle") { t in
        let box = CGRect(x: 400, y: 100, width: 260, height: 30)
        let tag = CGRect(x: 410, y: 250, width: 240, height: 90)
        let (from, _) = TagLayout.leader(side: .above, tag: tag, box: box, outer: box.insetBy(dx: -2, dy: -2),
                                         obstacles: [CGRect(x: 300, y: 170, width: 500, height: 28)])
        t.equal(from.x, box.midX)
    },
    TestCase("aSideLeaderAvoidsALabelToo") { t in
        // Tag left of a tall box; a label sits between them across the box's middle.
        let box = CGRect(x: 600, y: 300, width: 100, height: 120)
        let tag = CGRect(x: 300, y: 310, width: 240, height: 100)
        let label = CGRect(x: 560, y: 350, width: 30, height: 20)
        let (from, to) = TagLayout.leader(side: .left, tag: tag, box: box, outer: box.insetBy(dx: -2, dy: -2),
                                          obstacles: [label])
        t.equal(from.y, to.y)
        t.isFalse(label.intersects(CGRect(x: from.x, y: from.y - 1, width: to.x - from.x, height: 2)))
    },
    TestCase("neverOffScreenWithAHostAndPlacements") { t in
        let area = screen.insetBy(dx: margin, dy: margin)
        let window = CGRect(x: 154, y: 84, width: 1132, height: 708)
        for preferred in [TourStep.Placement.automatic, .left, .right, .above, .below, .insideCorner] {
            for x in stride(from: CGFloat(154), through: 1200, by: 90) {
                for y in stride(from: CGFloat(84), through: 700, by: 60) {
                    for size in [CGSize(width: 24, height: 24), CGSize(width: 600, height: 500), CGSize(width: 60, height: 400)] {
                        let anchor = CGRect(origin: CGPoint(x: x, y: y), size: size)
                        let p = TagLayout.place(anchor: anchor, tagSize: tagSize, visible: screen,
                                                preferred: preferred, host: window)
                        if !inside(p.tag, area) { t.fail("tag \(p.tag) off screen for \(anchor) \(preferred)"); return }
                        if p.side == .insideCorner, !anchor.contains(p.tag) {
                            t.fail("inside-corner tag \(p.tag) not inside \(anchor)"); return
                        }
                        if let l = p.leader, p.tag.intersects(p.outer) || !onEdge(l.to, of: p.outer) {
                            t.fail("bad leader for \(anchor) \(preferred)"); return
                        }
                    }
                }
            }
        }
    },
]

let tagKeysTests: [TestCase] = [
    TestCase("returnAndEnterAreNextOnExplainSteps") { t in
        for code in [TagKeys.returnKey, TagKeys.keypadEnter] {
            t.equal(TagKeys.action(keyCode: code, modifiers: [], isRepeat: false, isExplainStep: true, isEditingText: false), .next)
            t.isNil(TagKeys.action(keyCode: code, modifiers: [], isRepeat: false, isExplainStep: false, isEditingText: false))
        }
    },
    TestCase("escapeSkipsTheTourOnAnyStep") { t in
        for explain in [true, false] {
            t.equal(TagKeys.action(keyCode: TagKeys.escape, modifiers: [], isRepeat: false, isExplainStep: explain, isEditingText: false), .skipTour)
        }
    },
    TestCase("escapeIsLeftToAHostThatClaimsIt") { t in
        // The editor while it's on a drawing tool or has a selection: Esc goes back to Select first.
        t.isNil(TagKeys.action(keyCode: TagKeys.escape, modifiers: [], isRepeat: false, isExplainStep: true,
                               isEditingText: false, hostClaimsEscape: true))
        t.equal(TagKeys.action(keyCode: TagKeys.returnKey, modifiers: [], isRepeat: false, isExplainStep: true,
                               isEditingText: false, hostClaimsEscape: true), .next)
    },
    TestCase("aControlRecordingKeysGetsReturnAndEscape") { t in
        // Settings while a shortcut well records: Esc cancels it, Return is just another key press.
        for code in [TagKeys.returnKey, TagKeys.keypadEnter, TagKeys.escape] {
            t.isNil(TagKeys.action(keyCode: code, modifiers: [], isRepeat: false, isExplainStep: true,
                                   isEditingText: false, hostClaimsKeys: true))
        }
    },
    TestCase("typingInATextViewPassesThrough") { t in
        t.isNil(TagKeys.action(keyCode: TagKeys.returnKey, modifiers: [], isRepeat: false, isExplainStep: true, isEditingText: true))
        t.isNil(TagKeys.action(keyCode: TagKeys.escape, modifiers: [], isRepeat: false, isExplainStep: true, isEditingText: true))
    },
    TestCase("modifiersRepeatsAndOtherKeysPassThrough") { t in
        for mods: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
            t.isNil(TagKeys.action(keyCode: TagKeys.returnKey, modifiers: mods, isRepeat: false, isExplainStep: true, isEditingText: false))
        }
        t.isNil(TagKeys.action(keyCode: TagKeys.returnKey, modifiers: [], isRepeat: true, isExplainStep: true, isEditingText: false))
        t.isNil(TagKeys.action(keyCode: 0 /* A */, modifiers: [], isRepeat: false, isExplainStep: true, isEditingText: false))
        // Caps Lock / keypad flags don't count as modifiers.
        t.equal(TagKeys.action(keyCode: TagKeys.keypadEnter, modifiers: [.capsLock, .numericPad], isRepeat: false,
                               isExplainStep: true, isEditingText: false), .next)
    },
]

let tagStyleTests: [TestCase] = [
    TestCase("footerStrings") { t in
        t.equal(TagStyle.counter(2, of: 7), "2 of 7")
        t.equal(TagStyle.nextButtonTitle(number: 2, total: 7), "Next")
        t.equal(TagStyle.nextButtonTitle(number: 7, total: 7), "Done")
        t.equal(TagStyle.skipStepTitle, "Skip Step")
        t.equal(TagStyle.skipTourTitle, "Skip Tour")
    },
    TestCase("skipTourIsLeftOutOnlyNextToTheLastStepsDone") { t in
        t.isTrue(TagStyle.showsSkipTour(number: 2, total: 7, isExplain: true))
        t.isFalse(TagStyle.showsSkipTour(number: 7, total: 7, isExplain: true))
        // A last Try step reads "Skip Step" (which also hands over): Skip Tour stays.
        t.isTrue(TagStyle.showsSkipTour(number: 3, total: 3, isExplain: false))
    },
    TestCase("dimIsDeeperOverDarkHosts") { t in
        t.equal(TagStyle.dimAlpha(hostIsDark: false), 0.2)
        t.equal(TagStyle.dimAlpha(hostIsDark: true), 0.35)
    },
    TestCase("voiceOverReadsTitleBodyAndPosition") { t in
        t.equal(TagStyle.announcement(title: "Colours", body: "Pick a colour.", number: 2, total: 7),
                "Colours. Pick a colour. Step 2 of 7.")
    },
    TestCase("tourRedIsC62D22") { t in
        let c = TagStyle.tourRed.usingColorSpace(.sRGB)!
        t.equal(Int((c.redComponent * 255).rounded()), 0xC6)
        t.equal(Int((c.greenComponent * 255).rounded()), 0x2D)
        t.equal(Int((c.blueComponent * 255).rounded()), 0x22)
    },
]
