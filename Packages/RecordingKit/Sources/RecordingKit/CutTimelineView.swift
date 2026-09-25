import AppKit

/// The video editor's timeline: a time ruler (output time, laid out by `TimeRuler`)
/// over a filmstrip of the recording split into kept segments (sped ones narrower,
/// with a "2×" badge; muted ones with a speaker badge) and the cuts between them
/// (dimmed, hatched — still visible so an edge can be dragged back over them). The
/// selected segment has a yellow frame with drag handles; the white line is the
/// playhead. Draws a `CutList`; all edits go through the callbacks.
@MainActor
final class CutTimelineView: NSView {
    enum Edge { case start, end }
    enum DragPhase { case began, changed, ended }

    var cuts = CutList(duration: 0) { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) } }
    var selected = 0 { didSet { needsDisplay = true } }
    /// Output seconds.
    var playhead = 0.0 { didSet { if playhead != oldValue { needsDisplay = true } } }
    /// Width ÷ height of a video frame, for the filmstrip tiles.
    var aspect: CGFloat = 16 / 10 { didSet { needsDisplay = true } }

    /// Output time under a click / drag on a segment's body or a cut.
    var onScrub: ((Double) -> Void)?
    var onSelect: ((Int) -> Void)?
    /// An edge drag: segment, which edge, the proposed source time (unclamped).
    var onEdgeDrag: ((Int, Edge, Double, DragPhase) -> Void)?
    /// Context menu for a (just selected) segment.
    var menuForSegment: ((Int) -> NSMenu?)?

    static let inset: CGFloat = 12
    /// The ruler strip above the track (ticks end 1 pt above the track's backdrop).
    private static let rulerHeight: CGFloat = 14
    private static let trackTop: CGFloat = 18
    private static let trackBottom: CGFloat = 6
    private static let edgeGrab: CGFloat = 7

    private var thumbnails: [(time: Double, image: CGImage)] = []
    private var drag: (index: Int, edge: Edge, anchor: CutList, scale: CGFloat)?
    private var scrubbing = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func addThumbnail(time: Double, image: CGImage) {
        let i = thumbnails.firstIndex { $0.time > time } ?? thumbnails.count
        thumbnails.insert((time, image), at: i)
        needsDisplay = true
    }

    func resetThumbnails() { thumbnails = []; needsDisplay = true }

    /// The narrowest filmstrip tile (a cut's, which is drawn 8 pt shorter than the track).
    var minimumTileWidth: CGFloat { Self.tileWidth(height: trackRect.height - 8, aspect: aspect) }
    private static func tileWidth(height: CGFloat, aspect: CGFloat) -> CGFloat { max(24, min(160, height * aspect)) }

    // MARK: - Geometry

    /// Points per timeline second — frozen while an edge is dragged so the edge
    /// stays under the pointer even when a sped segment changes the total length.
    private var scale: CGFloat {
        if let drag { return drag.scale }
        let length = cuts.timelineLength
        return length > 0 ? (bounds.width - 2 * Self.inset) / CGFloat(length) : 0
    }
    private func x(_ timeline: Double) -> CGFloat { Self.inset + CGFloat(timeline) * scale }
    private func timelinePosition(_ x: CGFloat) -> Double {
        scale > 0 ? Double((x - Self.inset) / scale) : 0
    }
    private var trackRect: NSRect {
        NSRect(x: 0, y: Self.trackTop, width: bounds.width,
               height: bounds.height - Self.trackTop - Self.trackBottom)
    }
    private func rect(for item: CutList.TimelineItem) -> NSRect {
        let t = trackRect
        return NSRect(x: x(item.displayStart), y: t.minY,
                      width: CGFloat(item.displayLength) * scale, height: t.height)
    }
    var playheadX: CGFloat { x(cuts.timelinePosition(forOutput: playhead)) }

    /// The kept-segment edge under `p`, preferring the selected segment's, then the
    /// side of a shared boundary the pointer is on.
    private func edge(at p: NSPoint) -> (Int, Edge)? {
        var hits: [(Int, Edge, CGFloat)] = []
        for item in cuts.timeline {
            guard case .kept(let i) = item.kind else { continue }
            let r = rect(for: item)
            if abs(p.x - r.minX) <= Self.edgeGrab { hits.append((i, .start, p.x - r.minX)) }
            if abs(p.x - r.maxX) <= Self.edgeGrab { hits.append((i, .end, p.x - r.maxX)) }
        }
        if let h = hits.first(where: { $0.0 == selected }) { return (h.0, h.1) }
        if hits.count > 1, let h = hits.first(where: { ($0.1 == .start) == ($0.2 >= 0) }) { return (h.0, h.1) }
        return hits.first.map { ($0.0, $0.1) }
    }

    private func keptIndex(at p: NSPoint) -> Int? {
        for item in cuts.timeline {
            if case .kept(let i) = item.kind, rect(for: item).insetBy(dx: 0, dy: -Self.trackTop).contains(p) { return i }
        }
        return nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let track = trackRect
        NSColor(white: 0, alpha: 0.35).setFill()
        NSBezierPath(roundedRect: track.insetBy(dx: 2, dy: -3), xRadius: 8, yRadius: 8).fill()
        guard scale > 0 else { return }   // nothing loaded yet

        let items = cuts.timeline
        for item in items {
            let r = rect(for: item)
            guard r.width > 0.5, r.intersects(dirtyRect) else { continue }
            switch item.kind {
            case .removed: drawRemoved(item, in: r)
            case .kept(let i): drawKept(item, index: i, in: r)
            }
        }
        if let item = items.first(where: { $0.kind == .kept(selected) }) { drawSelection(in: rect(for: item)) }
        drawRuler(items, in: dirtyRect)
        drawPlayhead()
    }

    /// Filmstrip tiles across `r` (clipped by the caller), each showing the frame at
    /// its centre.
    private func drawFilmstrip(_ item: CutList.TimelineItem, in r: NSRect) {
        guard !thumbnails.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else {
            NSColor(white: 0.22, alpha: 1).setFill(); r.fill(); return
        }
        let tileW = Self.tileWidth(height: r.height, aspect: aspect)
        var tx = r.minX
        while tx < r.maxX {
            let centre = min(tx + tileW / 2, r.maxX - 0.5)
            let d = min(max(timelinePosition(centre), item.displayStart), item.displayEnd)
            let image = nearestThumbnail(cuts.sourceTime(forTimelinePosition: d))
            // Aspect-fill the tile.
            let tile = NSRect(x: tx, y: r.minY, width: tileW, height: r.height)
            let iw = CGFloat(image.width), ih = CGFloat(image.height)
            let s = max(tile.width / iw, tile.height / ih)
            let draw = NSRect(x: tile.midX - iw * s / 2, y: tile.midY - ih * s / 2, width: iw * s, height: ih * s)
            ctx.saveGState()
            ctx.clip(to: tile)
            // Flipped view: flip the image back upright.
            ctx.translateBy(x: 0, y: draw.maxY + draw.minY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: draw)
            ctx.restoreGState()
            tx += tileW
        }
    }

    private func nearestThumbnail(_ t: Double) -> CGImage {
        var lo = 0, hi = thumbnails.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if thumbnails[mid].time < t { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0, abs(thumbnails[lo - 1].time - t) < abs(thumbnails[lo].time - t) { lo -= 1 }
        return thumbnails[lo].image
    }

    private func drawKept(_ item: CutList.TimelineItem, index: Int, in full: NSRect) {
        let r = full.insetBy(dx: 1, dy: 0)
        let shape = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        drawFilmstrip(item, in: r)
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 1, alpha: 0.22).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        // Badges: speed, then mute.
        let segment = cuts.segments[index]
        var bx = r.minX + 5
        if segment.speed != 1 {
            bx = badge(text: Self.speedLabel(segment.speed), symbol: nil, at: bx, in: r)
        }
        if segment.muted { _ = badge(text: nil, symbol: "speaker.slash.fill", at: bx, in: r) }
    }

    /// Draws a small dark pill at the top-left of `r` and returns the x after it.
    private func badge(text: String?, symbol: String?, at bx: CGFloat, in r: NSRect) -> CGFloat {
        let h: CGFloat = 16
        var content: NSSize
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .bold),
                                                    .foregroundColor: NSColor.white]
        var image: NSImage?
        if let text {
            content = (text as NSString).size(withAttributes: attrs)
        } else {
            image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }?
                .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
            content = image?.size ?? .zero
        }
        let pill = NSRect(x: bx, y: r.minY + 4, width: content.width + 10, height: h)
        guard pill.maxX <= r.maxX - 4 else { return bx }
        NSColor(white: 0, alpha: 0.7).setFill()
        NSBezierPath(roundedRect: pill, xRadius: h / 2, yRadius: h / 2).fill()
        if let text {
            (text as NSString).draw(at: NSPoint(x: pill.minX + 5, y: pill.midY - content.height / 2),
                                    withAttributes: attrs)
        } else if let image {
            let tinted = NSImage(size: image.size, flipped: false) { rect in
                image.draw(in: rect)
                NSColor.white.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: pill.minX + 5, y: pill.midY - content.height / 2,
                                   width: content.width, height: content.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        return pill.maxX + 4
    }

    private func drawRemoved(_ item: CutList.TimelineItem, in full: NSRect) {
        let r = full.insetBy(dx: 1, dy: 4)
        let shape = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        drawFilmstrip(item, in: r)
        NSColor(white: 0, alpha: 0.66).setFill()
        r.fill()
        // Hatching: what's cut.
        NSColor(white: 1, alpha: 0.09).setStroke()
        let hatch = NSBezierPath()
        hatch.lineWidth = 1.5
        var hx = r.minX - r.height
        while hx < r.maxX {
            hatch.move(to: NSPoint(x: hx, y: r.maxY))
            hatch.line(to: NSPoint(x: hx + r.height, y: r.minY))
            hx += 7
        }
        hatch.stroke()
        NSGraphicsContext.restoreGraphicsState()
        if r.width >= 22, let scissors = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Cut")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold)) {
            let s = scissors.size
            let tinted = NSImage(size: s, flipped: false) { rect in
                scissors.draw(in: rect)
                NSColor(white: 1, alpha: 0.45).set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    /// Yellow frame + edge handles (QuickTime-style) on the selected segment.
    private func drawSelection(in full: NSRect) {
        let r = full.insetBy(dx: 1, dy: 0)
        guard r.width >= 4 else { return }
        let yellow = NSColor.systemYellow
        yellow.setStroke()
        let frame = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        frame.lineWidth = 2.5
        frame.stroke()
        let handleW: CGFloat = min(10, r.width / 3)
        for hx in [r.minX, r.maxX - handleW] {
            let handle = NSRect(x: hx, y: r.minY, width: handleW, height: r.height)
            yellow.setFill()
            NSBezierPath(roundedRect: handle, xRadius: 4, yRadius: 4).fill()
            NSColor(white: 0, alpha: 0.55).setFill()
            NSBezierPath(roundedRect: NSRect(x: handle.midX - 1, y: handle.midY - 7, width: 2, height: 14),
                         xRadius: 1, yRadius: 1).fill()
        }
    }

    private static let rulerAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
        .foregroundColor: NSColor(white: 1, alpha: 0.55),
    ]

    /// Round output times above the kept segments: a full-height tick with its label
    /// beside it, short minor ticks between.
    private func drawRuler(_ items: [CutList.TimelineItem], in dirtyRect: NSRect) {
        let spans = items.compactMap { item -> TimeRuler.Span? in
            guard case .kept(let i) = item.kind else { return nil }
            return TimeRuler.Span(x: x(item.displayStart), width: CGFloat(item.displayLength) * scale,
                                  outputStart: cuts.outputStart(of: i))
        }
        let ticks = TimeRuler.ticks(spans: spans, pointsPerSecond: scale, maxX: bounds.maxX - 2) {
            ($0 as NSString).size(withAttributes: Self.rulerAttributes).width
        }
        for tick in ticks where tick.x >= dirtyRect.minX - 80 && tick.x <= dirtyRect.maxX + 1 {
            let x = tick.x.rounded()
            NSColor(white: 1, alpha: tick.major ? 0.3 : 0.18).setFill()
            let top: CGFloat = tick.major ? 1 : Self.rulerHeight - 3
            NSRect(x: x, y: top, width: 1, height: Self.rulerHeight - top).fill()
            if let label = tick.label {
                (label as NSString).draw(at: NSPoint(x: x + TimeRuler.labelOffset, y: 0),
                                         withAttributes: Self.rulerAttributes)
            }
        }
    }

    /// The knob sits just under the ruler's labels, so it never covers one.
    private static let knobTop: CGFloat = 9.5

    private func drawPlayhead() {
        let px = playheadX.rounded() + 0.5
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.6)
        shadow.shadowBlurRadius = 2
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        NSRect(x: px - 1, y: Self.knobTop + 2, width: 2, height: bounds.height - Self.knobTop - 3).fill()
        NSBezierPath(ovalIn: NSRect(x: px - 4, y: Self.knobTop, width: 8, height: 8)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func speedLabel(_ speed: Double) -> String {
        (speed == speed.rounded() ? String(Int(speed)) : String(speed)) + "×"
    }

    // MARK: - Mouse

    override func resetCursorRects() {
        for item in cuts.timeline {
            guard case .kept = item.kind else { continue }
            let r = rect(for: item)
            for ex in [r.minX, r.maxX] {
                addCursorRect(NSRect(x: ex - Self.edgeGrab, y: trackRect.minY, width: 2 * Self.edgeGrab,
                                     height: trackRect.height), cursor: .resizeLeftRight)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if let (i, e) = edge(at: p) {
            drag = (i, e, cuts, scale)
            onSelect?(i)
            onEdgeDrag?(i, e, sourceTime(forEdgeAt: p.x), .began)
            return
        }
        if let i = keptIndex(at: p) { onSelect?(i) }
        scrubbing = true
        onScrub?(cuts.outputTime(forTimelinePosition: timelinePosition(p.x)))
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let drag {
            onEdgeDrag?(drag.index, drag.edge, sourceTime(forEdgeAt: p.x), .changed)
            autoscroll(with: event)
        } else if scrubbing {
            onScrub?(cuts.outputTime(forTimelinePosition: timelinePosition(p.x)))
            autoscroll(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let d = drag {
            let t = sourceTime(forEdgeAt: p.x)
            drag = nil
            onEdgeDrag?(d.index, d.edge, t, .ended)
        }
        scrubbing = false
    }

    /// The source time an edge dragged to `x` stands for, measured from the side that
    /// doesn't move: a start edge from the end of the cut before it (cuts are drawn at
    /// source length), an end edge from its own segment's start (drawn at output length).
    private func sourceTime(forEdgeAt px: CGFloat) -> Double {
        guard let drag else { return 0 }
        let a = drag.anchor, i = drag.index, s = drag.scale
        guard s > 0, let item = a.timeline.first(where: { $0.kind == .kept(i) }) else { return 0 }
        let segment = a.segments[i]
        switch drag.edge {
        case .start:
            let before = i > 0 ? a.segments[i - 1].end : 0
            let gapStart = item.displayStart - (segment.start - before)
            return before + Double((px - Self.inset) / s) - gapStart
        case .end:
            return segment.start + (Double((px - Self.inset) / s) - item.displayStart) * segment.speed
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = keptIndex(at: p) else { return nil }
        onSelect?(i)
        return menuForSegment?(i)
    }
}
