import CoreGraphics

/// Where the tag goes around the highlighted control (spec §14.3). Pure and unit-tested; screen
/// coordinates with AppKit's origin (bottom-left, y up) — "below" is lower on screen.
///
/// The outline box is the anchor grown by `boxPadding` (clipped to the screen, for a menu-bar icon);
/// its 2 pt stroke sits just outside that. The tag goes on the first side in the preference order
/// where it fits inside the visible frame (minus `screenMargin`) at `leaderLength` from the outline,
/// slid along that side to stay on screen but still overlapping the box's span so the leader line
/// stays short. With a `keepOut` rect (a small borderless host — the record strip, the pill) the tag
/// first tries to sit outside all of it, so it never covers that panel's other controls; if nothing
/// fits there it may overlap it. Nothing fits at all (a huge control on a full-screen window) → the
/// tag sits *over* the control's top-left corner.
enum TagLayout {
    enum Side: String, Equatable, Sendable {
        case left, right, below, above, over
    }

    struct Placement: Equatable, Sendable {
        var side: Side
        /// The outline's inner edge: the anchor grown by `boxPadding` (corner radius `boxRadius`).
        var box: CGRect
        /// The outline's outer edge (box grown by the stroke) — the dim's hole.
        var outer: CGRect
        var tag: CGRect
        /// From a point on the tag's edge to a point on the outline's outer edge; nil for `.over`.
        var leader: (from: CGPoint, to: CGPoint)?

        static func == (a: Placement, b: Placement) -> Bool {
            a.side == b.side && a.box == b.box && a.outer == b.outer && a.tag == b.tag
                && a.leader?.from == b.leader?.from && a.leader?.to == b.leader?.to
        }
    }

    /// Left/right first (the mock puts the tag left of the box), then below/above; or below/above
    /// first for a control sitting in a horizontal bar (toolbar, record strip, pill), so the tag
    /// doesn't cover the controls next to it.
    static func order(verticalFirst: Bool) -> [Side] {
        verticalFirst ? [.below, .above, .left, .right] : [.left, .right, .below, .above]
    }

    /// A control whose container is a wide, short bar (3:1 or wider) gets the tag above/below.
    static func prefersVertical(containerSize: CGSize) -> Bool {
        containerSize.height > 0 && containerSize.width >= 3 * containerSize.height
    }

    static func place(anchor: CGRect, tagSize: CGSize, visible: CGRect,
                      order: [Side] = order(verticalFirst: false),
                      keepOut: CGRect? = nil, screen: CGRect? = nil) -> Placement {
        var box = anchor.insetBy(dx: -TagStyle.boxPadding, dy: -TagStyle.boxPadding)
        if let screen {
            // A menu-bar icon fills the bar's height: keep the whole outline on the screen.
            let limit = screen.insetBy(dx: TagStyle.boxStroke, dy: TagStyle.boxStroke)
            if box.intersects(limit) { box = box.intersection(limit) }
        }
        let outer = box.insetBy(dx: -TagStyle.boxStroke, dy: -TagStyle.boxStroke)
        let area = visible.insetBy(dx: TagStyle.screenMargin, dy: TagStyle.screenMargin)

        if let keepOut, let p = firstFit(order, clear: outer.union(keepOut), box: box, outer: outer,
                                         size: tagSize, area: area) { return p }
        if let p = firstFit(order, clear: outer, box: box, outer: outer, size: tagSize, area: area) { return p }

        // Fallback: inside the control's top-left corner, kept on screen.
        let w = tagSize.width, h = tagSize.height, inset = TagStyle.tagRadius
        let tag = CGRect(x: clamp(box.minX + inset, area.minX, area.maxX - w),
                         y: clamp(box.maxY - inset - h, area.minY, area.maxY - h),
                         width: w, height: h)
        return Placement(side: .over, box: box, outer: outer, tag: tag, leader: nil)
    }

    /// The first side where the tag fits `leaderLength` outside `clear`, inside `area`, overlapping
    /// the box's span.
    private static func firstFit(_ order: [Side], clear: CGRect, box: CGRect, outer: CGRect,
                                 size: CGSize, area: CGRect) -> Placement? {
        let w = size.width, h = size.height, gap = TagStyle.leaderLength
        for side in order {
            var tag: CGRect
            switch side {
            case .left, .right:
                let x = side == .left ? clear.minX - gap - w : clear.maxX + gap
                let y = clamp(box.midY - h / 2, area.minY, area.maxY - h)
                tag = CGRect(x: x, y: y, width: w, height: h)
                guard tag.minX >= area.minX, tag.maxX <= area.maxX, h <= area.height,
                      tag.minY < box.maxY, tag.maxY > box.minY else { continue }
            case .below, .above:
                let y = side == .below ? clear.minY - gap - h : clear.maxY + gap
                let x = clamp(box.midX - w / 2, area.minX, area.maxX - w)
                tag = CGRect(x: x, y: y, width: w, height: h)
                guard tag.minY >= area.minY, tag.maxY <= area.maxY, w <= area.width,
                      tag.minX < box.maxX, tag.maxX > box.minX else { continue }
            case .over:
                continue
            }
            tag.origin = CGPoint(x: tag.origin.x.rounded(), y: tag.origin.y.rounded())   // whole points
            return Placement(side: side, box: box, outer: outer, tag: tag,
                             leader: leader(side: side, tag: tag, box: box, outer: outer))
        }
        return nil
    }

    /// Straight across when the tag and box overlap enough; kept off both shapes' rounded corners.
    private static func leader(side: Side, tag: CGRect, box: CGRect, outer: CGRect) -> (CGPoint, CGPoint) {
        let tr = TagStyle.tagRadius, br = TagStyle.boxRadius
        switch side {
        case .left, .right:
            let y = clamp(box.midY, tag.minY + tr, tag.maxY - tr)
            let yBox = clamp(y, box.minY + br, box.maxY - br)
            return side == .left
                ? (CGPoint(x: tag.maxX, y: y), CGPoint(x: outer.minX, y: yBox))
                : (CGPoint(x: tag.minX, y: y), CGPoint(x: outer.maxX, y: yBox))
        case .below, .above:
            let x = clamp(box.midX, tag.minX + tr, tag.maxX - tr)
            let xBox = clamp(x, box.minX + br, box.maxX - br)
            return side == .below
                ? (CGPoint(x: x, y: tag.maxY), CGPoint(x: xBox, y: outer.minY))
                : (CGPoint(x: x, y: tag.minY), CGPoint(x: xBox, y: outer.maxY))
        case .over:
            return (.zero, .zero)
        }
    }

    /// `lo...hi`, or the middle of the two when the range is empty (a tiny box or tag).
    static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        lo > hi ? (lo + hi) / 2 : min(max(v, lo), hi)
    }
}
