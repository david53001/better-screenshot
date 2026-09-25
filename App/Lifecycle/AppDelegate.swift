import AppKit
import CaptureKit
import HistoryKit
import OverlayKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    private var coordinator: CaptureCoordinator!
    private var recordingCoordinator: RecordingCoordinator!
    private var menuBar: MenuBarController!
    private var onboarding: OnboardingController!
    private var settingsWindow: SettingsWindowController!
    private var historyWindow: HistoryWindowController!
    private let hotKeys = HotKeyManager()
    private var history: HistoryService!
    private var tempFiles: TempFileService!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // One stack for screenshot AND recording thumbnails so they never overlap.
        let quickAccess = QuickAccessStackController()
        history = HistoryService(settings: settings)
        // Sweeps $TMPDIR/BetterScreenshot-* per the "Keep cached files for" setting,
        // starting with whatever earlier runs left behind.
        tempFiles = TempFileService(settings: settings)
        coordinator = CaptureCoordinator(settings: settings, quickAccess: quickAccess)
        coordinator.editorPresenter = { [weak coordinator] image in
            coordinator?.presentEditor(image)
        }
        recordingCoordinator = RecordingCoordinator(settings: settings, quickAccess: quickAccess)
        coordinator.history = history
        recordingCoordinator.history = history
        historyWindow = HistoryWindowController(history: history, actions: HistoryWindowActions(
            annotate: { [weak self] image in self?.coordinator.annotate(image) },
            pin: { [weak self] image in self?.coordinator.pin(image) },
            trim: { [weak self] url in self?.recordingCoordinator.presentTrim(url: url) }))
        recordingCoordinator.onStateChange = { [weak self] recording, elapsed in
            self?.menuBar.setRecording(recording, elapsed: elapsed)
        }
        recordingCoordinator.onPauseStateChange = { [weak self] active, paused in
            self?.menuBar.setPauseItem(active: active, paused: paused)
        }
        let shortcuts = ShortcutActions(
            update: { [weak self] combo, action in self?.updateBinding(combo, for: action) },
            restoreDefaults: { [weak self] in self?.restoreDefaultBindings() },
            recordingChanged: { [weak self] recording in
                guard let self else { return }
                if recording {
                    self.hotKeys.suspend()
                } else {
                    self.settings.failedActions = self.hotKeys.resume()
                }
            })
        settingsWindow = SettingsWindowController(store: settings, shortcuts: shortcuts,
                                                  clearHistory: { [weak self] in
            self?.history.clearAll()
        })
        menuBar = MenuBarController(coordinator: coordinator, settingsWindow: settingsWindow)
        menuBar.onToggleRecording = { [weak self] in self?.recordingCoordinator.toggle() }
        menuBar.onOpenHistory = { [weak self] in self?.historyWindow.show() }
        menuBar.onRestoreRecentlyClosed = { [weak self] in self?.restoreRecentlyClosed() }
        menuBar.onPauseResume = { [weak self] in self?.recordingCoordinator.pauseResume() }
        menuBar.canRestore = { [weak self] in self?.history.canRestore ?? false }

        // One-button first-run setup (Screen Recording is the only permission).
        onboarding = OnboardingController(bindings: { [weak self] in self?.settings.bindings ?? .defaults })
        coordinator.presentSetup = { [weak self] in self?.onboarding.show(.needsPermission) }
        recordingCoordinator.presentSetup = { [weak self] in self?.onboarding.show(.needsPermission) }
        if !PermissionManager.hasScreenRecordingPermission {
            onboarding.show(.needsPermission)
        } else if OnboardingController.consumeRelaunchFlag() {
            onboarding.show(.allSet)   // just relaunched after the grant
        }
        // Register as a login item once, by default. One-time so we never
        // fight a user who later disables it (Settings or System Settings).
        if !UserDefaults.standard.bool(forKey: "didRegisterLaunchAtLogin") {
            LaunchAtLogin.setEnabled(true)
            UserDefaults.standard.set(true, forKey: "didRegisterLaunchAtLogin")
        }
        applyBindings()
        // Stop macOS's native ⌘⇧4/⌘⇧5 from also firing (double screenshot/recording). Restored on quit.
        SystemScreenshotShortcuts.disableNativeShortcuts()
    }

    /// Register every bound hotkey; record failures and refresh menu shortcuts.
    @discardableResult
    private func applyBindings() -> Set<HotkeyAction> {
        let handlers: [HotkeyAction: () -> Void] = [
            .captureArea:       { [weak self] in Task { @MainActor in self?.coordinator.captureArea() } },
            .captureWindow:     { [weak self] in Task { @MainActor in self?.coordinator.captureFrontWindow() } },
            .captureFullscreen: { [weak self] in Task { @MainActor in self?.coordinator.captureFullscreen() } },
            .captureText:       { [weak self] in Task { @MainActor in self?.coordinator.captureText() } },
            .pinFromClipboard:  { [weak self] in Task { @MainActor in self?.coordinator.pinFromClipboard() } },
            .record:            { [weak self] in Task { @MainActor in self?.recordingCoordinator.toggle() } },
            .openHistory:           { [weak self] in Task { @MainActor in self?.historyWindow.show() } },
            .restoreRecentlyClosed: { [weak self] in Task { @MainActor in self?.restoreRecentlyClosed() } },
            .pauseResumeRecording:  { [weak self] in Task { @MainActor in self?.recordingCoordinator.pauseResume() } },
        ]
        let failed = hotKeys.apply(settings.bindings, handlers: handlers)
        settings.failedActions = failed
        menuBar.refreshKeyEquivalents(settings.bindings)
        return failed
    }

    /// Rebind transaction for the Shortcuts tab: validate, apply, revert on failure.
    /// Returns a user-facing error message, or nil on success.
    /// Guarantees only the edited action; a collateral registration failure of another action surfaces via `settings.failedActions`, not the return value.
    func updateBinding(_ combo: HotkeyCombo?, for action: HotkeyAction) -> String? {
        var candidate = settings.bindings
        if let combo {
            if let other = candidate.conflictingAction(for: combo, excluding: action) {
                return "Already used by \(other.title)"
            }
            candidate.set(combo, for: action)
        } else {
            candidate.clear(action)
        }
        let previous = settings.bindings
        settings.bindings = candidate
        let failed = applyBindings()
        if combo != nil, failed.contains(action) {
            settings.bindings = previous
            applyBindings()
            return "That shortcut is in use by another app or macOS."
        }
        settings.persist()
        return nil
    }

    func restoreDefaultBindings() {
        settings.bindings = .defaults
        applyBindings()
        settings.persist()
    }

    /// Re-presents the most recently ✕-closed/evicted Quick Access overlay
    /// from its history entry (screenshots: stored full-res image; recordings:
    /// saved file + stored thumbnail).
    private func restoreRecentlyClosed() {
        guard let entry = history.popRestorable() else { return }
        switch entry.kind {
        case .screenshot:
            guard let image = history.image(for: entry) else { return }
            coordinator.presentOverlayFromHistory(image, historyID: entry.id)
        case .recording:
            guard let url = history.savedFileURL(for: entry),
                  let image = history.thumbnail(for: entry) else { return }
            recordingCoordinator.presentCardFromHistory(url: url, image: image,
                                                        historyID: entry.id)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingCoordinator?.stopForTermination()
        SystemScreenshotShortcuts.restoreNativeShortcuts()
    }
}
