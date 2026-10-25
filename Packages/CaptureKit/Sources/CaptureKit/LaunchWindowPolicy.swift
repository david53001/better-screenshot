import Foundation

/// Which window BetterScreenshot opens when it starts (a Dock app since 3.3.0). Opened at login, it
/// stays out of the way — only the Dock icon; opened by the user (Finder, Launchpad, Spotlight, `open`,
/// a Sparkle relaunch) it shows Settings, so the launch visibly did something. Onboarding comes first
/// either way, exactly as before: the one-button setup while Screen Recording is missing, the Welcome
/// page right after the permission relaunch or for a new user who hasn't been asked about the tour.
public enum LaunchWindowPolicy {
    public enum Window: Equatable {
        case none
        case settings
        /// Onboarding's `.needsPermission` page.
        case setup
        /// Onboarding's `.allSet` ("You're all set!") page.
        case welcome
    }

    /// `relaunchedAfterGrant` consumes a one-time flag, so it is only asked once the permission is in
    /// (as before); `opensWelcome` only when that flag wasn't set.
    public static func window(permissionGranted: Bool, launchedAsLoginItem: Bool,
                              relaunchedAfterGrant: () -> Bool, opensWelcome: () -> Bool) -> Window {
        guard permissionGranted else { return .setup }
        if relaunchedAfterGrant() || opensWelcome() { return .welcome }
        return launchedAsLoginItem ? .none : .settings
    }
}
