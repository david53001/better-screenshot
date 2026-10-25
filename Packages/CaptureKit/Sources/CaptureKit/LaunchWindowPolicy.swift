import Foundation

/// Which window BetterScreenshot opens when it starts (a Dock app since 3.3.0), and what a Dock click does.
/// Opened at login — as a login item, or relaunched by macOS's "Reopen windows when logging back in" (not
/// a default launch) — it stays out of the way: only the Dock icon. Opened by the user (Finder, Launchpad,
/// Spotlight, `open`, a Sparkle relaunch) it shows Settings, so the launch visibly did something.
/// Onboarding comes first either way, exactly as before: the one-button setup while Screen Recording is
/// missing, the Welcome page right after the permission relaunch or for a new user who hasn't been asked
/// about the tour.
public enum LaunchWindowPolicy {
    public enum Window: Equatable {
        case none
        case settings
        /// Onboarding's `.needsPermission` page.
        case setup
        /// Onboarding's `.allSet` ("You're all set!") page.
        case welcome
    }

    /// `launchIsDefault`: `NSApplication.launchIsDefaultUserInfoKey` — false when macOS launched the app to
    /// restore it (e.g. at login with "Reopen windows" ticked), which may not carry the login-item flag.
    /// `relaunchedAfterGrant` consumes a one-time flag, so it is only asked once the permission is in
    /// (as before); `opensWelcome` only when that flag wasn't set.
    public static func window(permissionGranted: Bool, launchedAsLoginItem: Bool, launchIsDefault: Bool = true,
                              relaunchedAfterGrant: () -> Bool, opensWelcome: () -> Bool) -> Window {
        guard permissionGranted else { return .setup }
        if relaunchedAfterGrant() || opensWelcome() { return .welcome }
        return launchedAsLoginItem || !launchIsDefault ? .none : .settings
    }

    public enum Reopen: Equatable {
        /// The app is hidden: unhide it (every window reports not visible while hidden).
        case unhide
        /// One of our windows is up: AppKit just brings the app forward.
        case bringForward
        /// Only minimized windows: put one back.
        case restoreMinimized
        /// No window at all: Settings.
        case settings
    }

    /// A Dock click, or opening the running app again. "Window" means a titled, non-panel one (the
    /// floating Quick Access / pin / recording panels don't count).
    public static func reopen(isHidden: Bool, hasVisibleWindow: Bool, hasMinimizedWindow: Bool) -> Reopen {
        if isHidden { return .unhide }
        if hasVisibleWindow { return .bringForward }
        return hasMinimizedWindow ? .restoreMinimized : .settings
    }
}
