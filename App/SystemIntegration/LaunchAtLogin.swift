import AppKit
import ServiceManagement
import CaptureKit

/// "Launch at login" via SMAppService (the modern Login Items API).
/// SMAppService is the source of truth — no mirrored flag in UserDefaults —
/// so the Settings toggle stays correct even when the user flips it in
/// System Settings → General → Login Items instead.
///
/// BetterScreenshot never turns it on by itself: the user does, with the Settings switch or by
/// answering the one-time "Open BetterScreenshot at login?" card
/// (`App/MenuBar/LaunchAtLoginPromptController.swift`, rules in CaptureKit `LaunchAtLoginPrompt`).
/// Up to 3.1.0 the first launch registered silently (flag `didRegisterLaunchAtLogin`); that is gone,
/// and the flag is now only read, to keep from asking those users.
enum LaunchAtLogin {
    /// Posted after every `setEnabled`, so the Settings switch and the card show the real status.
    static let didChangeNotification = Notification.Name("BetterScreenshot.launchAtLoginDidChange")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registered, but the user switched it off under System Settings → General → Login Items
    /// (or macOS wants them to approve it there). Only they can turn it back on, in that pane.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// This launch is macOS opening the app at login (a login item, `SMAppService.mainApp` included):
    /// the open-application Apple Event says so, as LaunchAtLogin-Modern checks it. Only meaningful
    /// while `applicationDidFinishLaunching` runs (that event is the current one then).
    static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Turns launch at login on or off and returns the system's status afterwards (a failed call
    /// leaves the real status). Any explicit choice also counts as the answer to the one-time
    /// question, so the card never asks someone who already chose.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> SMAppService.Status {
        LaunchAtLoginPrompt().markAsked()
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Never fatal (e.g. an unsigned dev build can't register); the status shows the outcome.
            NSLog("LaunchAtLogin: failed to \(enabled ? "register" : "unregister"): \(error)")
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
        return SMAppService.mainApp.status
    }
}
