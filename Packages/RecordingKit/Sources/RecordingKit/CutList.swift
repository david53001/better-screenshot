import Foundation

/// One kept piece of a recording, in source seconds.
public struct CutSegment: Equatable {
    public var start: Double
    public var end: Double
    /// Playback speed — one of `CutList.speeds`.
    public var speed: Double
    /// Silences this segment's audio.
    public var muted: Bool

    public init(start: Double, end: Double, speed: Double = 1, muted: Bool = false) {
        self.start = start; self.end = end; self.speed = speed; self.muted = muted
    }

    /// Source seconds kept.
    public var length: Double { end - start }
    /// Seconds this segment lasts in the exported video.
    public var outputLength: Double { length / speed }
}

/// The video editor's edit list: the ordered, non-overlapping segments of a recording
/// that are kept (everything between them is cut), each with its own speed and mute.
/// Pure — the editor window draws it, `CutComposition` turns it into an AVComposition.
/// A plain trim is the single-segment case (`init(range:duration:)`).
///
/// Three time axes: *source* (the recording), *output* (the exported video — kept
/// segments back to back, sped ones shorter) and *timeline* (what the editor draws:
/// kept segments at their output length, cuts at their source length, in order).
public struct CutList: Equatable {
    public static let speeds: [Double] = [1, 1.5, 2, 4]
    /// Shortest segment an edit may leave.
    public static let minimumSegment = 0.1
    private static let epsilon = 1e-6

    /// Source recording length, seconds.
    public let duration: Double
    /// Never empty.
    public private(set) var segments: [CutSegment]

    public init(duration: Double) {
        self.duration = max(duration, 0)
        segments = [CutSegment(start: 0, end: self.duration)]
    }

    public init(range: TrimRange, duration: Double) {
        self.duration = max(duration, 0)
        segments = [CutSegment(start: range.start, end: range.end)]
    }

    // MARK: - Derived

    /// Length of the exported video.
    public var keptDuration: Double { segments.reduce(0) { $0 + $1.outputLength } }

    /// Non-nil when the edit is one contiguous stretch at 1× with a single mute state —
    /// a plain start/end trim, which exports losslessly (passthrough). Anything else
    /// (a middle cut, a speed change, mixed mute) must be re-encoded.
    public var passthrough: (range: TrimRange, muted: Bool)? {
        guard let first = segments.first, let last = segments.last else { return nil }
        for (a, b) in zip(segments, segments.dropFirst()) where abs(a.end - b.start) > Self.epsilon {
            return nil
        }
        guard segments.allSatisfy({ $0.speed == 1 && $0.muted == first.muted }) else { return nil }
        return (TrimRange(start: first.start, end: last.end), first.muted)
    }

    /// Where segment `index` begins in the output.
    public func outputStart(of index: Int) -> Double {
        segments.prefix(index).reduce(0) { $0 + $1.outputLength }
    }

    /// The segment playing at output time `t` (a boundary belongs to the later
    /// segment; the very end to the last).
    public func segmentIndex(atOutput t: Double) -> Int {
        var acc = 0.0
        for (i, s) in segments.enumerated() {
            if t < acc + s.outputLength - Self.epsilon { return i }
            acc += s.outputLength
        }
        return segments.count - 1
    }

    public func sourceTime(forOutput t: Double) -> Double {
        let i = segmentIndex(atOutput: t)
        let s = segments[i]
        let local = min(max(t - outputStart(of: i), 0), s.outputLength)
        return s.start + local * s.speed
    }

    /// The kept segment holding source time `t` (a shared boundary belongs to the later one).
    public func segmentIndex(containingSource t: Double) -> Int? {
        for (i, s) in segments.enumerated() {
            let last = i == segments.count - 1
            if t >= s.start - Self.epsilon && (t < s.end - Self.epsilon || (last && t <= s.end + Self.epsilon)) {
                return i
            }
        }
        return nil
    }

    /// nil when `t` is cut.
    public func outputTime(forSource t: Double) -> Double? {
        guard let i = segmentIndex(containingSource: t) else { return nil }
        let s = segments[i]
        return outputStart(of: i) + min(max(t - s.start, 0), s.length) / s.speed
    }

    // MARK: - Edits (each returns false and changes nothing when it can't apply)

    /// Splits the segment under source time `t` into two with the same speed and mute.
    public mutating func split(atSource t: Double) -> Bool {
        guard let i = segments.firstIndex(where: {
            t >= $0.start + Self.minimumSegment - Self.epsilon && t <= $0.end - Self.minimumSegment + Self.epsilon
        }) else { return false }
        var right = segments[i]
        right.start = t
        segments[i].end = t
        segments.insert(right, at: i + 1)
        return true
    }

    /// Cuts a segment out. The last remaining segment can't be removed.
    public mutating func remove(at index: Int) -> Bool {
        guard segments.count > 1, segments.indices.contains(index) else { return false }
        segments.remove(at: index)
        return true
    }

    /// Moves a segment's start, clamped between the previous segment's end (or 0) and
    /// its own end minus the minimum length.
    public mutating func setStart(_ t: Double, of index: Int) -> Bool {
        guard segments.indices.contains(index) else { return false }
        let lower = index > 0 ? segments[index - 1].end : 0
        let upper = max(lower, segments[index].end - Self.minimumSegment)
        let v = min(max(t, lower), upper)
        guard abs(v - segments[index].start) > Self.epsilon else { return false }
        segments[index].start = v
        return true
    }

    /// Moves a segment's end, clamped between its start plus the minimum length and
    /// the next segment's start (or the recording's end).
    public mutating func setEnd(_ t: Double, of index: Int) -> Bool {
        guard segments.indices.contains(index) else { return false }
        let upper = index < segments.count - 1 ? segments[index + 1].start : duration
        let lower = min(upper, segments[index].start + Self.minimumSegment)
        let v = min(max(t, lower), upper)
        guard abs(v - segments[index].end) > Self.epsilon else { return false }
        segments[index].end = v
        return true
    }

    /// Speeding a 1× segment up mutes it (fast audio sounds rushed); returning to 1×
    /// unmutes it. An explicit unmute survives changes between faster speeds.
    public mutating func setSpeed(_ speed: Double, of index: Int) -> Bool {
        guard segments.indices.contains(index), Self.speeds.contains(speed),
              segments[index].speed != speed else { return false }
        let old = segments[index].speed
        segments[index].speed = speed
        if old == 1 { segments[index].muted = true }
        if speed == 1 { segments[index].muted = false }
        return true
    }

    public mutating func setMuted(_ muted: Bool, of index: Int) -> Bool {
        guard segments.indices.contains(index), segments[index].muted != muted else { return false }
        segments[index].muted = muted
        return true
    }

    /// In point: drops everything before source time `t`.
    public mutating func trimBefore(source t: Double) -> Bool {
        var kept = segments.filter { $0.end > t + Self.epsilon }
        guard !kept.isEmpty else { return false }
        if kept[0].start < t { kept[0].start = min(t, kept[0].end - Self.minimumSegment) }
        guard kept != segments else { return false }
        segments = kept
        return true
    }

    /// Out point: drops everything after source time `t`.
    public mutating func trimAfter(source t: Double) -> Bool {
        var kept = segments.filter { $0.start < t - Self.epsilon }
        guard !kept.isEmpty else { return false }
        let last = kept.count - 1
        if kept[last].end > t { kept[last].end = max(t, kept[last].start + Self.minimumSegment) }
        guard kept != segments else { return false }
        segments = kept
        return true
    }

    // MARK: - Timeline

    /// One block of the editor's timeline, in timeline seconds.
    public struct TimelineItem: Equatable {
        public enum Kind: Equatable { case kept(Int), removed }
        public var kind: Kind
        public var sourceStart: Double
        public var sourceEnd: Double
        public var displayStart: Double
        public var displayLength: Double
        public var displayEnd: Double { displayStart + displayLength }
    }

    /// Kept segments at their output length (sped ones narrower) and the cuts between
    /// them at their source length, so what was removed stays visible and can be
    /// dragged back.
    public var timeline: [TimelineItem] {
        var items: [TimelineItem] = []
        var source = 0.0, display = 0.0
        func removed(to end: Double) {
            guard end - source > Self.epsilon else { return }
            items.append(TimelineItem(kind: .removed, sourceStart: source, sourceEnd: end,
                                      displayStart: display, displayLength: end - source))
            display += end - source
        }
        for (i, s) in segments.enumerated() {
            removed(to: s.start)
            items.append(TimelineItem(kind: .kept(i), sourceStart: s.start, sourceEnd: s.end,
                                      displayStart: display, displayLength: s.outputLength))
            display += s.outputLength
            source = s.end
        }
        removed(to: duration)
        return items
    }

    public var timelineLength: Double { timeline.last?.displayEnd ?? 0 }

    /// Where output time `t` (the playhead) sits on the timeline.
    public func timelinePosition(forOutput t: Double) -> Double {
        let i = segmentIndex(atOutput: t)
        guard let item = timeline.first(where: { $0.kind == .kept(i) }) else { return 0 }
        return item.displayStart + min(max(t - outputStart(of: i), 0), item.displayLength)
    }

    /// The output time for a click at timeline position `d`. A click on a cut lands on
    /// the start of the next kept segment (or the end, when none follows).
    public func outputTime(forTimelinePosition d: Double) -> Double {
        let items = timeline
        guard let hit = items.firstIndex(where: { d < $0.displayEnd }) else { return keptDuration }
        for item in items[hit...] {
            if case .kept(let i) = item.kind {
                return outputStart(of: i) + min(max(d - item.displayStart, 0), item.displayLength)
            }
        }
        return keptDuration
    }

    /// The source time drawn at timeline position `d` (for the filmstrip).
    public func sourceTime(forTimelinePosition d: Double) -> Double {
        let items = timeline
        guard let item = items.first(where: { d < $0.displayEnd }) ?? items.last else { return 0 }
        let local = min(max(d - item.displayStart, 0), item.displayLength)
        if case .kept(let i) = item.kind { return item.sourceStart + local * segments[i].speed }
        return item.sourceStart + local
    }
}

/// Undo / redo over whole `CutList` values — one step per user action (a whole edge
/// drag is one step: the window edits a working copy, then `commit`s it).
public struct CutHistory {
    public private(set) var current: CutList
    private var undoStack: [CutList] = []
    private var redoStack: [CutList] = []

    public init(_ list: CutList) { current = list }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Makes `list` current as one undo step (none when nothing changed).
    public mutating func commit(_ list: CutList) {
        guard list != current else { return }
        undoStack.append(current)
        redoStack.removeAll()
        current = list
    }

    @discardableResult
    public mutating func apply(_ edit: (inout CutList) -> Bool) -> Bool {
        var list = current
        guard edit(&list) else { return false }
        commit(list)
        return true
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(current)
        current = previous
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(current)
        current = next
        return true
    }
}
