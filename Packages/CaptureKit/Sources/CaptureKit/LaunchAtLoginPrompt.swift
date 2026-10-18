import Foundation

/// Where `LaunchAtLoginPrompt` keeps its state: the app's `UserDefaults.standard`; tests use an
/// in-memory store, so a test run never writes a preferences file.
public protocol LaunchAtLoginPromptStorage {
    func integer(forKey defaultName: String) -> Int
    func bool(forKey defaultName: String) -> Bool
    func set(_ value: Int, forKey defaultName: String)
    func set(_ value: Bool, forKey defaultName: String)
}

extension UserDefaults: LaunchAtLoginPromptStorage {}

/// When BetterScreenshot asks "Open BetterScreenshot at login?" (a small card,
/// `App/MenuBar/LaunchAtLoginPromptController.swift`). Same rules as MacStats and JVoice.
///
/// Rules: count each completed screenshot capture (area, window, full screen or Capture Text that
/// produced an image; a cancelled selection or a failed capture isn't one). Once
/// `usesBeforeAsking` are recorded, ask at the next calm moment (`isCalmMoment`). It is answered
/// at most once ever, never asked when launch at login is already on, and never asked of users of
/// ≤ 3.1.0, whose first launch turned it on by itself (that build wrote `didRegisterLaunchAtLogin`):
/// they either still have it, or turned it off on purpose. A choice made with the Settings switch
/// also counts as answered. A card left unanswered goes away by itself after
/// `unansweredHideSeconds` and comes back after a later capture, at most `maxShowings` times in
/// all; after the last one it counts as answered "no".
///
/// All state is in the standard defaults under the `Key` names (docs/sparkle-updates/README.md).
public struct LaunchAtLoginPrompt {
    public enum Key {
        /// Int: completed captures counted so far (stops at `usesBeforeAsking`).
        public static let uses = "launchAtLoginPromptUses"
        /// Bool: the question was answered (or ignored `maxShowings` times), or the user chose in
        /// Settings, or launch at login was found on. Never asked again.
        public static let asked = "launchAtLoginPromptAsked"
        /// Int: times the card was shown and went away unanswered.
        public static let unansweredShowings = "launchAtLoginPromptUnansweredShowings"
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
        /// The menu-bar menu is open (menu tracking; `appIsActive` and the mouse buttons don't show it).
        public var menuIsOpen: Bool

        public init(secondsSinceCapture: TimeInterval, secondsSinceKeyPress: TimeInterval,
                    mouseButtonDown: Bool, captureOrRecordingActive: Bool, appIsActive: Bool,
                    menuIsOpen: Bool) {
            self.secondsSinceCapture = secondsSinceCapture
            self.secondsSinceKeyPress = secondsSinceKeyPress
            self.mouseButtonDown = mouseButtonDown
            self.captureOrRecordingActive = captureOrRecordingActive
            self.appIsActive = appIsActive
            self.menuIsOpen = menuIsOpen
        }
    }

    /// A moment when the card can't interrupt anything: the capture has settled, nothing of ours is
    /// in use, no drag is in progress and the user isn't typing.
    public static func isCalmMoment(_ m: Moment) -> Bool {
        m.secondsSinceCapture >= settleSeconds && m.secondsSinceKeyPress >= typingQuietSeconds
            && !m.mouseButtonDown && !m.captureOrRecordingActive && !m.appIsActive && !m.menuIsOpen
    }

    // MARK: The flow, one step at a time (the app's controller only carries these out)

    /// What to do right after a counted capture.
    public enum AfterCapture: Equatable {
        /// Not due, or the card is already up.
        case nothing
        /// Due: look for a calm moment (`waitStep`, once a second).
        case startWaiting
        /// Launch at login is on already: never ask (`markAsked`), so no capture checks again.
        case alreadyEnabled
    }

    /// `isEnabled` reads the system's status (an XPC call), so it is only called when the question
    /// could be due.
    public static func afterCapture(couldAsk: Bool, cardVisible: Bool, isEnabled: () -> Bool) -> AfterCapture {
        guard couldAsk, !cardVisible else { return .nothing }
        return isEnabled() ? .alreadyEnabled : .startWaiting
    }

    /// One tick of the wait for a calm moment.
    public enum WaitStep: Equatable {
        /// Not calm yet: check again in a second.
        case keepWaiting
        /// `giveUpSeconds` passed since the capture: stop; the next capture starts a new wait.
        case giveUp
        /// Calm, still due, launch at login still off: show the card.
        case show
        /// Answered meanwhile (the Settings switch): stop.
        case noLongerDue
        /// Turned on meanwhile (System Settings): stop and never ask (`markAsked`).
        case alreadyEnabled
    }

    /// `couldAsk` and `isEnabled` are re-read right before showing, because either can change
    /// while the app waits; `isEnabled` (an XPC call) only once the moment is calm.
    public static func waitStep(_ m: Moment, couldAsk: Bool, isEnabled: () -> Bool) -> WaitStep {
        if m.secondsSinceCapture >= giveUpSeconds { return .giveUp }
        guard isCalmMoment(m) else { return .keepWaiting }
        guard couldAsk else { return .noLongerDue }
        return isEnabled() ? .alreadyEnabled : .show
    }

    // MARK: An unanswered card

    /// An unanswered question card goes away by itself after this long on screen, like a macOS
    /// banner, so it never sits over a presentation or a shared screen.
    public static let unansweredHideSeconds: TimeInterval = 25
    /// Shown at most this many times without an answer; after the last it counts as "no".
    public static let maxShowings = 3

    /// Whether the unanswered card should go now: after `unansweredHideSeconds`, but not while the
    /// pointer is on it (the user is about to click).
    public static func shouldHideUnanswered(secondsShown: TimeInterval, pointerOnCard: Bool) -> Bool {
        secondsShown >= unansweredHideSeconds && !pointerOnCard
    }

    // MARK: Storage

    private let storage: LaunchAtLoginPromptStorage

    public init(storage: LaunchAtLoginPromptStorage = UserDefaults.standard) {
        self.storage = storage
    }

    public var uses: Int { storage.integer(forKey: Key.uses) }
    public var asked: Bool { storage.bool(forKey: Key.asked) }
    public var unansweredShowings: Int { storage.integer(forKey: Key.unansweredShowings) }
    private var legacyAutoEnabled: Bool { storage.bool(forKey: Key.legacyAutoEnabled) }

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
        storage.set(uses + 1, forKey: Key.uses)
        return true
    }

    public func markAsked() {
        storage.set(true, forKey: Key.asked)
    }

    /// The card went away unanswered (`shouldHideUnanswered`). It stays due, so a later capture
    /// brings it back, until this was the `maxShowings`th time: then it counts as answered.
    /// Returns whether that was the last showing.
    @discardableResult
    public func recordUnansweredShowing() -> Bool {
        let showings = unansweredShowings + 1
        storage.set(showings, forKey: Key.unansweredShowings)
        guard showings >= Self.maxShowings else { return false }
        markAsked()
        return true
    }
}
