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
        t.equal(TagStyle.skipStepTitle, "Skip step")
        t.equal(TagStyle.skipTourTitle, "Skip tour")
    },
    TestCase("voiceOverReadsTitleBodyAndPosition") { t in
        t.equal(TagStyle.announcement(title: "Colours", body: "Pick a colour.", number: 2, total: 7),
                "Colours. Pick a colour. Step 2 of 7.")
    },
    TestCase("tourRedIsFF453A") { t in
        let c = TagStyle.tourRed.usingColorSpace(.sRGB)!
        t.equal(Int((c.redComponent * 255).rounded()), 0xFF)
        t.equal(Int((c.greenComponent * 255).rounded()), 0x45)
        t.equal(Int((c.blueComponent * 255).rounded()), 0x3A)
    },
]
