import Foundation

/// Decides whether a finished capture should hand keyboard focus back to the
/// app that was frontmost when the capture started.
///
/// BetterScreenshot has to activate itself so the borderless selection overlay
/// can receive Escape (and show its crosshair). That leaves the user's real
/// app unfocused, so we reactivate it afterwards — unless we *were* the app
/// they were using, or there is nothing to go back to.
public enum FocusRestore {
    public static func shouldRestore(previousBundleID: String?, ownBundleID: String?) -> Bool {
        guard let previousBundleID else { return false }
        return previousBundleID != ownBundleID
    }
}
