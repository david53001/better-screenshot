import AppKit
import Sparkle

/// Auto-updates via Sparkle 2 (docs/sparkle-updates/README.md). Same setup as MacStats and JVoice.
///
/// Configuration lives in `App/Info.plist`: `SUFeedURL` (the appcast attached to the latest
/// GitHub release), `SUPublicEDKey` (updates must be signed with the matching EdDSA key) and
/// `SUEnableAutomaticChecks` (check daily without first asking permission). The app is not
/// sandboxed, so Sparkle installs via its bundled `Autoupdate` / `Updater.app`; the framework's
/// XPC services (only for sandboxed apps) are removed by `scripts/build-app.sh`. The only network
/// traffic is the appcast + update download from GitHub (no system profile is sent).
///
/// BetterScreenshot is a menu-bar app, so scheduled checks use Sparkle's "gentle reminders": a
/// found update's window opens *behind* the user's windows instead of taking focus. So that it
/// isn't missed, the menu's "Check for Updates…" item reads "Update Available (X)…" and
/// Settings → Updates says "Version X is available." until the user looks at it; either one
/// brings Sparkle's window forward. (No notification: the app never asks for that permission.)
@MainActor
final class Updates: NSObject, ObservableObject {
    static let shared = Updates()

    /// Whether a check can start now (false while one is running), for the menu item and Settings.
    @Published private(set) var canCheck = false
    /// Set while a scheduled check has found an update the user hasn't looked at yet.
    @Published private(set) var pendingVersion: String?

    private var controller: SPUStandardUpdaterController!
    private var canCheckObservation: NSKeyValueObservation?

    private override init() {
        super.init()
        #if SPARKLE_E2E_TEST
        let updaterDelegate: SPUUpdaterDelegate? = self
        #else
        let updaterDelegate: SPUUpdaterDelegate? = nil
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: updaterDelegate,
                                                  userDriverDelegate: self)
    }

    /// Starts the updater (and its schedule). Called once at launch.
    func start() {
        controller.startUpdater()
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = value }
        }
    }

    /// "Check for Updates…" / "Show Update…": shows Sparkle's window with the result, or brings
    /// the waiting update's window forward.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)   // a menu-bar app: otherwise the window can open behind others
        controller.checkForUpdates(nil)
    }

    /// The menu item and the Settings button are usable: no check running, or one waits to be seen.
    var canCheckOrShow: Bool { canCheck || pendingVersion != nil }

    /// Settings → Updates → "Check automatically" (Sparkle stores it in our defaults as
    /// `SUEnableAutomaticChecks`; the Info.plist value is only the default).
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

extension Updates: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        guard !state.userInitiated else { return }
        let version = update.displayVersionString
        Task { @MainActor in self.pendingVersion = version }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.pendingVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.pendingVersion = nil }
    }
}

#if SPARKLE_E2E_TEST
/// Only in the throwaway build of `scripts/sparkle-e2e-test.sh` (`-DSPARKLE_E2E_TEST`): log each
/// step to stderr for the script, and install a downloaded update right away instead of on quit
/// (the script can't quit the app gracefully without an Apple-event permission prompt).
extension Updates: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        NSLog("SPARKLE-E2E found %@ (build %@)", item.displayVersionString, item.versionString)
    }

    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        NSLog("SPARKLE-E2E downloaded %@", item.versionString)
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        NSLog("SPARKLE-E2E installing %@", item.versionString)
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        NSLog("SPARKLE-E2E ready to install %@; installing now", item.versionString)
        immediateInstallHandler()
        return true
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        NSLog("SPARKLE-E2E aborted: %@", (error as NSError).description)
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                             error: Error?) {
        NSLog("SPARKLE-E2E cycle finished, error: %@", error.map { ($0 as NSError).description } ?? "none")
    }
}
#endif
