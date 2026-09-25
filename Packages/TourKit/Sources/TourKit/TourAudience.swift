/// Who tours are offered to — spec §14.9 ("only for new users … that has to be made sure of").
/// Decided once, on the first launch of a build with tours, before the app writes anything; stored
/// under `TourPreferenceKey.audience` and never recomputed. When in doubt the answer is `.existing`:
/// a missed new user is harmless, a nagged existing user is not.
public enum TourAudience: String, Sendable {
    case new, existing

    /// The stored value: absent → nil (not classified yet); "new" → `.new`; anything else → `.existing`.
    public init?(stored: String?) {
        guard let stored else { return nil }
        self = stored == TourAudience.new.rawValue ? .new : .existing
    }

    /// Everything the classifier looks at. The app gathers these (`TourCoordinator`); this type stays pure.
    public struct Signals: Equatable, Sendable {
        /// Keys in the app's own persistent preferences domain (`com.betterscreenshot.mac`) — never the
        /// global domain.
        public var preferenceKeys: Set<String>
        /// `~/Library/Application Support/BetterScreenshot/` exists and has anything in it (or couldn't be
        /// read — the gatherer reports doubt as `true`).
        public var supportFolderHasContent: Bool
        /// Screen Recording is already granted at this launch (a fresh install never has it).
        public var screenRecordingGranted: Bool
        /// The running app's bundle id. Anything but `TourAudience.knownBundleIdentifier` means we can't
        /// trust what we read, so the user counts as existing.
        public var bundleIdentifier: String?

        public init(preferenceKeys: Set<String>, supportFolderHasContent: Bool,
                    screenRecordingGranted: Bool, bundleIdentifier: String?) {
            self.preferenceKeys = preferenceKeys
            self.supportFolderHasContent = supportFolderHasContent
            self.screenRecordingGranted = screenRecordingGranted
            self.bundleIdentifier = bundleIdentifier
        }
    }

    public static let knownBundleIdentifier = "com.betterscreenshot.mac"

    /// Keys that don't show the app was used: the tour keys themselves. Every other key counts —
    /// including AppKit's own (`NSStatusItem …`, `NSWindow Frame …`), which it only writes after the
    /// app ran. (A fresh domain is empty at the top of `applicationDidFinishLaunching`; the app reads
    /// only its own domain, so global-domain keys never appear in `preferenceKeys`.)
    public static let ignoredKeys: Set<String> = TourPreferenceKey.all

    /// `.existing` if any one signal says the app was used before; `.new` only if none does.
    public static func classify(_ signals: Signals) -> TourAudience {
        guard signals.bundleIdentifier == knownBundleIdentifier else { return .existing }
        if !signals.preferenceKeys.subtracting(ignoredKeys).isEmpty { return .existing }
        if signals.supportFolderHasContent { return .existing }
        if signals.screenRecordingGranted { return .existing }
        return .new
    }
}

/// Every UserDefaults key the tour system persists (spec §14.4 + §14.9). Nothing else is stored.
public enum TourPreferenceKey {
    /// String, "new" | "existing". Written once, before anything else at the first launch with tours.
    public static let audience = "tourAudience"
    /// Bool. True once a new user answered "Want a quick tour?" (or closed the window on it).
    public static let questionAnswered = "tourQuestionAnswered"
    /// Bool. Absent = false. True only after "Show Me Around" or the Settings checkbox.
    public static let firstUseToursEnabled = "firstUseToursEnabled"
    /// Dictionary tour id (`TourID.rawValue`) → Int catalog version seen (finished or skipped).
    public static let seen = "toursSeen"
    /// Dictionary tour id → Int step index to resume at.
    public static let paused = "toursPaused"

    public static let all: Set<String> = [audience, questionAnswered, firstUseToursEnabled, seen, paused]
}
