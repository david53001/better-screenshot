import Foundation

/// Pure recording state machine. `recording`/`paused` carry the start time and
/// the total time spent paused so the elapsed timer can exclude pauses.
public enum RecorderState: Equatable {
    case idle
    case armed                                                   // record strip showing
    case recording(started: Date, accumulatedPause: TimeInterval)
    case paused(started: Date, accumulatedPause: TimeInterval, since: Date)
    case finishing                                              // writer finalizing — new commands rejected

    public enum Event: Equatable {
        case arm                     // show the strip
        case begin(Date)             // capture started
        case pause(Date)             // recording → paused at this time
        case resume(Date)            // paused → recording at this time
        case finish                  // stop requested
        case reset                   // back to idle (finalized or cancelled)
    }

    /// Applies `event` if legal; returns whether the state changed.
    @discardableResult
    public mutating func transition(_ event: Event) -> Bool {
        switch (self, event) {
        case (.idle, .arm):                       self = .armed
        case (.armed, .begin(let date)):          self = .recording(started: date, accumulatedPause: 0)
        case (.armed, .reset):                    self = .idle
        case (.recording(let started, let acc), .pause(let at)):
            self = .paused(started: started, accumulatedPause: acc, since: at)
        case (.paused(let started, let acc, let since), .resume(let at)):
            self = .recording(started: started, accumulatedPause: acc + at.timeIntervalSince(since))
        case (.recording, .finish):               self = .finishing
        case (.paused, .finish):                  self = .finishing
        case (.finishing, .reset):                self = .idle
        default:                                  return false
        }
        return true
    }

    /// "m:ss" while recording (paused time excluded); "Paused · m:ss" (frozen)
    /// while paused; nil otherwise.
    public func elapsedString(now: Date) -> String? {
        switch self {
        case .recording(let started, let acc):
            let secs = max(0, Int(now.timeIntervalSince(started) - acc))
            return "\(secs / 60):" + String(format: "%02d", secs % 60)
        case .paused(let started, let acc, let since):
            let secs = max(0, Int(since.timeIntervalSince(started) - acc))
            return "Paused · \(secs / 60):" + String(format: "%02d", secs % 60)
        default:
            return nil
        }
    }

    /// The Dock icon's badge: the elapsed time, "⏸ 0:17" while paused (the badge is too narrow for
    /// "Paused · …"), nil when not recording.
    public func badgeString(now: Date) -> String? {
        guard let elapsed = elapsedString(now: now) else { return nil }
        if case .paused = self { return "⏸ " + elapsed.replacingOccurrences(of: "Paused · ", with: "") }
        return elapsed
    }
}
