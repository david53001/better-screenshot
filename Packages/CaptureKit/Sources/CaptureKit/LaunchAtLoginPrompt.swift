import CoreGraphics
import Foundation

/// Where `LaunchAtLoginPrompt` keeps its state: the app's `UserDefaults.standard`; tests use an
/// in-memory store, so a test run never writes a preferences file.
public protocol LaunchAtLoginPromptStorage {
    func integer(forKey defaultName: String) -> Int
    func bool(forKey defaultName: String) -> Bool
    func double(forKey defaultName: String) -> Double
    func set(_ value: Int, forKey defaultName: String)
    func set(_ value: Bool, forKey defaultName: String)
    func set(_ value: Double, forKey defaultName: String)
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
/// `unansweredHideSeconds`. It only counts as a showing if the user could have seen it (`Showing`):
/// then it comes back after a later capture at least `reshowAfterSeconds` later (a relaunch, e.g.
/// after an automatic update, doesn't shorten that), at most `maxShowings` times in all; after the
/// last one it counts as answered "no". While it is due, the app's menus also offer it
/// (`offersMenuItem`): the card never takes focus, so that is its keyboard path.
///
/// All state is in the standard defaults under the `Key` names (docs/sparkle-updates/README.md).
public struct LaunchAtLoginPrompt {
    public enum Key {
        /// Int: completed captures counted so far (stops at `usesBeforeAsking`).
        public static let uses = "launchAtLoginPromptUses"
        /// Bool: the question was answered (or ignored `maxShowings` times), or the user chose in
        /// Settings, or launch at login was found on. Never asked again.
        public static let asked = "launchAtLoginPromptAsked"
        /// Int: times the card was seen and went away unanswered (`Showing.counts`).
        public static let unansweredShowings = "launchAtLoginPromptUnansweredShowings"
        /// Double: when the last such showing ended, in seconds since 1970 (0 = never).
        public static let lastShownAt = "launchAtLoginPromptLastShownAt"
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
        /// One of the app's menus is open (menu tracking; `appIsActive` and the mouse buttons don't show it).
        public var menuIsOpen: Bool
        /// The frontmost app is full screen, presenting or running a full-screen game
        /// (`fullScreenInFront`). AppKit does put the card on another app's full-screen Space
        /// (checked 2026-10-18, macOS 26.7.1), so this wait is what keeps it off.
        public var fullScreenInFront: Bool

        public init(secondsSinceCapture: TimeInterval, secondsSinceKeyPress: TimeInterval,
                    mouseButtonDown: Bool, captureOrRecordingActive: Bool, appIsActive: Bool,
                    menuIsOpen: Bool, fullScreenInFront: Bool) {
            self.secondsSinceCapture = secondsSinceCapture
            self.secondsSinceKeyPress = secondsSinceKeyPress
            self.mouseButtonDown = mouseButtonDown
            self.captureOrRecordingActive = captureOrRecordingActive
            self.appIsActive = appIsActive
            self.menuIsOpen = menuIsOpen
            self.fullScreenInFront = fullScreenInFront
        }
    }

    /// A moment when the card can't interrupt anything: the capture has settled, nothing of ours is
    /// in use, no drag is in progress, the user isn't typing and nothing full-screen is in front.
    public static func isCalmMoment(_ m: Moment) -> Bool {
        m.secondsSinceCapture >= settleSeconds && m.secondsSinceKeyPress >= typingQuietSeconds
            && !m.mouseButtonDown && !m.captureOrRecordingActive && !m.appIsActive && !m.menuIsOpen
            && !m.fullScreenInFront
    }

    /// An on-screen window, as `CGWindowListCopyWindowInfo` reports it (bounds and owner need no
    /// Screen Recording permission).
    public struct WindowInfo: Equatable {
        public var ownerPID: Int32
        /// `kCGWindowLayer`: 0 for normal windows, negative for the desktop, higher for panels.
        public var layer: Int
        /// Top-left origin on the primary screen (Quartz window coordinates).
        public var bounds: CGRect

        public init(ownerPID: Int32, layer: Int, bounds: CGRect) {
            self.ownerPID = ownerPID
            self.layer = layer
            self.bounds = bounds
        }
    }

    /// A display, as `NSScreen` reports it.
    public struct Screen: Equatable {
        /// `NSScreen.frame`: bottom-left origin, menu bar included.
        public var frame: CGRect
        /// `NSScreen.safeAreaInsets.top`: the notch row of a MacBook's built-in display, else 0.
        public var topInset: CGFloat

        public init(frame: CGRect, topInset: CGFloat = 0) {
            self.frame = frame
            self.topInset = topInset
        }
    }

    /// `Moment.fullScreenInFront`: the frontmost app has a window (layer ≥ 0: not the desktop) that
    /// fills a screen —
    /// - exactly the screen's frame, menu bar included (a full-screen app on a display without a
    ///   notch, a presentation, a full-screen game), or
    /// - on a display with a notch (`topInset` > 0), the whole width down to the bottom edge,
    ///   starting just below the notch row: macOS keeps full-screen windows out of that row
    ///   (measured 2026-10-18 on a 1470×956 MacBook Air, inset 32: the window is (0, 33, 1470, 923)).
    /// A zoomed window stops at the menu bar *and* the Dock; the one look-alike is a zoomed window on
    /// a notched display with the Dock hidden, which only makes the card wait (accepted).
    /// `screens`: the primary screen first.
    public static func fullScreenInFront(frontmostPID: Int32?, windows: [WindowInfo], screens: [Screen]) -> Bool {
        guard let frontmostPID, let primary = screens.first?.frame else { return false }
        // Quartz window coordinates: top-left origin on the primary screen, y grows downwards.
        let areas = screens.map { screen -> (frame: CGRect, topInset: CGFloat) in
            let f = screen.frame
            return (CGRect(x: f.minX, y: primary.maxY - f.maxY, width: f.width, height: f.height), screen.topInset)
        }
        func fills(_ b: CGRect, _ area: (frame: CGRect, topInset: CGFloat)) -> Bool {
            let s = area.frame
            if b == s { return true }
            guard area.topInset > 0 else { return false }
            return b.minX == s.minX && b.width == s.width && b.maxY == s.maxY
                && b.minY > s.minY && b.minY <= s.minY + area.topInset + 2
        }
        return windows.contains { w in
            w.ownerPID == frontmostPID && w.layer >= 0 && areas.contains { fills(w.bounds, $0) }
        }
    }

    // MARK: The flow, one step at a time (the app's controller only carries these out)

    /// What to do right after a capture (`afterCapture`).
    public enum AfterCapture: Equatable {
        /// Not due, or the card is already up.
        case nothing
        /// Due, but the card was seen less than `reshowAfterSeconds` ago, or shown unseen less than
        /// `reshowAfterUnseenSeconds` ago.
        case tooSoon
        /// Due: look for a calm moment (`waitStep`, once a second).
        case startWaiting
        /// Launch at login is on already: marked asked, so no later capture checks again.
        case alreadyEnabled
    }

    /// A completed capture: records it (`recordUse`), then decides. `isEnabled` reads the system's
    /// status (an XPC call), so it is only called when the question could be due and isn't spaced
    /// out; found on, the question is marked asked. `unseenShowingEndedAt`: when the last showing
    /// that didn't count ended, in this launch.
    public func afterCapture(cardVisible: Bool, unseenShowingEndedAt: Date? = nil,
                             now: Date = Date(), isEnabled: () -> Bool) -> AfterCapture {
        recordUse()
        guard couldAsk, !cardVisible else { return .nothing }
        guard Self.mayShowAgain(secondsSinceLastShowing: secondsSinceLastShowing(now: now),
                                secondsSinceUnseenShowing: unseenShowingEndedAt.map { now.timeIntervalSince($0) })
        else { return .tooSoon }
        guard !isEnabled() else {
            markAsked()
            return .alreadyEnabled
        }
        return .startWaiting
    }

    /// One tick of the wait for a calm moment (`waitStep`).
    public enum WaitStep: Equatable {
        /// Not calm yet: check again in a second.
        case keepWaiting
        /// `giveUpSeconds` passed since the capture: stop; the next capture starts a new wait.
        case giveUp
        /// Calm, still due, launch at login still off: show the card.
        case show
        /// Answered meanwhile (the Settings switch): stop.
        case noLongerDue
        /// Turned on meanwhile (System Settings): stop; marked asked, never asked.
        case alreadyEnabled
    }

    /// `couldAsk` and `isEnabled` are re-read right before showing, because either can change
    /// while the app waits; `isEnabled` (an XPC call) only once the moment is calm.
    public func waitStep(_ m: Moment, isEnabled: () -> Bool) -> WaitStep {
        if m.secondsSinceCapture >= Self.giveUpSeconds { return .giveUp }
        guard Self.isCalmMoment(m) else { return .keepWaiting }
        guard couldAsk else { return .noLongerDue }
        guard !isEnabled() else {
            markAsked()
            return .alreadyEnabled
        }
        return .show
    }

    /// Whether the app's menus show **Open at Login…** (asks the same question in a standard,
    /// keyboard-reachable alert): while the question is due. `isEnabled` (an XPC call) is only read
    /// then; found on, the question is marked asked and the item goes.
    public func offersMenuItem(isEnabled: () -> Bool) -> Bool {
        guard couldAsk else { return false }
        guard !isEnabled() else {
            markAsked()
            return false
        }
        return true
    }

    // MARK: An unanswered card

    /// An unanswered card goes away by itself after this long on screen, like a macOS banner, so it
    /// never sits over a presentation or a shared screen. The "One more step" and "Couldn't turn it
    /// on" cards too (they don't count as showings: the question is answered).
    public static let unansweredHideSeconds: TimeInterval = 25
    /// Shown (and seen) at most this many times without an answer; after the last it counts as "no".
    public static let maxShowings = 3
    /// A showing only counts once the card was seen this long (`Showing.secondsSeen`).
    public static let minimumSecondsSeen: TimeInterval = 5
    /// After a counted showing, the card only comes back this much later, across relaunches too (an
    /// automatic update relaunches the app; that mustn't bring it back the same day).
    public static let reshowAfterSeconds: TimeInterval = 24 * 60 * 60
    /// After a showing that didn't count, it comes back on a capture this much later (not on the
    /// very next one: someone who never touches the mouse while it's up isn't shown it after every
    /// screenshot).
    public static let reshowAfterUnseenSeconds: TimeInterval = 10 * 60

    /// Whether the card should go now: after `unansweredHideSeconds`, but not while the pointer is
    /// on it (the user is about to click).
    public static func shouldHideUnanswered(secondsShown: TimeInterval, pointerOnCard: Bool) -> Bool {
        secondsShown >= unansweredHideSeconds && !pointerOnCard
    }

    /// Whether another showing may start now. `secondsSinceLastShowing`: since the last counted
    /// one ended, from the stored time (nil: none yet, ever); `secondsSinceUnseenShowing`: since the
    /// last uncounted one ended in this launch (nil: none). A negative time (the clock was set back)
    /// doesn't hold the card back.
    public static func mayShowAgain(secondsSinceLastShowing: TimeInterval?,
                                    secondsSinceUnseenShowing: TimeInterval? = nil) -> Bool {
        if let unseen = secondsSinceUnseenShowing, unseen >= 0, unseen < reshowAfterUnseenSeconds { return false }
        guard let seconds = secondsSinceLastShowing else { return true }
        return seconds < 0 || seconds >= reshowAfterSeconds
    }

    /// One showing of the question, followed by the app once a second while it is up, so that only
    /// a card the user could have seen counts: one that was on screen (on the active Space, not
    /// covered, the screen not locked or asleep) after the user had used the mouse or keyboard since
    /// it appeared (not a desk they walked away from).
    public struct Showing: Equatable {
        /// Wall-clock time on screen (for `shouldHideUnanswered`).
        public private(set) var secondsShown: TimeInterval = 0
        /// Time it was visible with the user there.
        public private(set) var secondsSeen: TimeInterval = 0

        /// The longest a single tick adds to `secondsSeen`: a tick that comes late (the Mac slept
        /// with the card up) says nothing about the time in between.
        public static let maxSecondsPerTick: TimeInterval = 2

        public init() {}

        /// - Parameters:
        ///   - seconds: since the previous tick (or since the card appeared).
        ///   - cardVisible: the card's window is on the active Space and not covered.
        ///   - secondsSinceInput: since the last key, click, scroll or mouse move, anywhere.
        public mutating func tick(seconds: TimeInterval, cardVisible: Bool, secondsSinceInput: TimeInterval) {
            secondsShown += seconds
            if cardVisible && secondsSinceInput < secondsShown {
                secondsSeen += min(seconds, Self.maxSecondsPerTick)
            }
        }

        /// Whether it counts towards `maxShowings`.
        public var counts: Bool { secondsSeen >= LaunchAtLoginPrompt.minimumSecondsSeen }
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

    /// Seconds since the last counted showing ended, or nil if there was none.
    public func secondsSinceLastShowing(now: Date = Date()) -> TimeInterval? {
        let last = storage.double(forKey: Key.lastShownAt)
        return last > 0 ? now.timeIntervalSince1970 - last : nil
    }

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

    /// The question card went away unanswered (`shouldHideUnanswered`). Only a showing the user
    /// could have seen (`Showing.counts`) is recorded (`recordUnansweredShowing`, and its time for
    /// `reshowAfterSeconds`); any other only delays the next one (`reshowAfterUnseenSeconds`, kept by
    /// the app for this launch). Returns whether it counted.
    @discardableResult
    public func cardHidUnanswered(_ showing: Showing, now: Date = Date()) -> Bool {
        guard showing.counts else { return false }
        storage.set(now.timeIntervalSince1970, forKey: Key.lastShownAt)
        recordUnansweredShowing()
        return true
    }

    /// One more unanswered showing. It stays due, so a later capture brings it back, until this was
    /// the `maxShowings`th time: then it counts as answered. Returns whether that was the last.
    @discardableResult
    public func recordUnansweredShowing() -> Bool {
        let showings = unansweredShowings + 1
        storage.set(showings, forKey: Key.unansweredShowings)
        guard showings >= Self.maxShowings else { return false }
        markAsked()
        return true
    }
}
