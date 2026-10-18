import Foundation

/// When BetterScreenshot asks "Open BetterScreenshot at login?" (a small card,
/// `App/MenuBar/LaunchAtLoginPromptController.swift`). Same rules as MacStats and JVoice.
///
/// Rules: count each completed screenshot capture (area, window, full screen or Capture Text that
/// produced an image; a cancelled selection or a failed capture isn't one). Once
/// `usesBeforeAsking` are recorded, ask at the next calm moment (`isCalmMoment`). Ask at most once
/// ever, never when launch at login is already on, and never for users of ≤ 3.1.0, whose first
/// launch turned it on by itself (that build wrote `didRegisterLaunchAtLogin`): they either still
/// have it, or turned it off on purpose. A choice made with the Settings switch also counts as
/// answered.
///
/// All state is in the standard defaults under the `Key` names (docs/sparkle-updates/README.md).
public struct LaunchAtLoginPrompt {
    public enum Key {
        /// Int: completed captures counted so far (stops at `usesBeforeAsking`).
        public static let uses = "launchAtLoginPromptUses"
        /// Bool: the question was shown and answered, or the user chose in Settings. Never asked again.
        public static let asked = "launchAtLoginPromptAsked"
        /// Bool, read only: written by ≤ 3.1.0 after its silent first-launch enable.
        public static let legacyAutoEnabled = "didRegisterLaunchAtLogin"
    }

    public static let usesBeforeAsking = 5

    /// The decision itself, free of storage.
    public static func shouldAsk(uses: Int, asked: Bool, legacyAutoEnabled: Bool, enabled: Bool) -> Bool {
        uses >= usesBeforeAsking && !asked && !legacyAutoEnabled && !enabled
    }

    // MARK: Calm moment

    /// Seconds after the capture that made it due before the card may appear: the user is often
    /// still pasting, dragging the thumbnail or annotating right after a shot.
    public static let settleSeconds: TimeInterval = 3
    /// No key pressed for this long: the card never pops up mid-typing (it doesn't take focus
    /// either way; this is about not distracting).
    public static let typingQuietSeconds: TimeInterval = 2
    /// How long the app keeps waiting for a calm moment after a capture; the next capture tries again.
    public static let giveUpSeconds: TimeInterval = 120

    /// What `isCalmMoment` looks at, read by the app once a second while the question is due.
    public struct Moment: Equatable {
        public var secondsSinceCapture: TimeInterval
        public var secondsSinceKeyPress: TimeInterval
        public var mouseButtonDown: Bool
        /// A selection overlay, countdown, record strip or recording is up.
        public var captureOrRecordingActive: Bool
        /// One of our own windows (editor, Settings, History…) is in front: the user is working in it.
        public var appIsActive: Bool

        public init(secondsSinceCapture: TimeInterval, secondsSinceKeyPress: TimeInterval,
                    mouseButtonDown: Bool, captureOrRecordingActive: Bool, appIsActive: Bool) {
            self.secondsSinceCapture = secondsSinceCapture
            self.secondsSinceKeyPress = secondsSinceKeyPress
            self.mouseButtonDown = mouseButtonDown
            self.captureOrRecordingActive = captureOrRecordingActive
            self.appIsActive = appIsActive
        }
    }

    /// A moment when the card can't interrupt anything: the capture has settled, nothing of ours is
    /// in use, no drag is in progress and the user isn't typing.
    public static func isCalmMoment(_ m: Moment) -> Bool {
        m.secondsSinceCapture >= settleSeconds && m.secondsSinceKeyPress >= typingQuietSeconds
            && !m.mouseButtonDown && !m.captureOrRecordingActive && !m.appIsActive
    }

    // MARK: Storage

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var uses: Int { defaults.integer(forKey: Key.uses) }
    public var asked: Bool { defaults.bool(forKey: Key.asked) }
    private var legacyAutoEnabled: Bool { defaults.bool(forKey: Key.legacyAutoEnabled) }

    /// Everything but the launch-at-login status, so callers can skip reading that (an XPC call
    /// to the system) until the question could actually be due.
    public var couldAsk: Bool {
        Self.shouldAsk(uses: uses, asked: asked, legacyAutoEnabled: legacyAutoEnabled, enabled: false)
    }

    public func shouldAsk(enabled: Bool) -> Bool {
        Self.shouldAsk(uses: uses, asked: asked, legacyAutoEnabled: legacyAutoEnabled, enabled: enabled)
    }

    /// Records one completed capture. Returns whether it counted: nothing more is counted once
    /// the threshold is reached or the question can no longer come (asked, or a ≤ 3.1.0 user).
    @discardableResult
    public func recordUse() -> Bool {
        guard !asked, !legacyAutoEnabled, uses < Self.usesBeforeAsking else { return false }
        defaults.set(uses + 1, forKey: Key.uses)
        return true
    }

    public func markAsked() {
        defaults.set(true, forKey: Key.asked)
    }
}
