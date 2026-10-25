import AppKit
import Combine
import CaptureKit
import DesignKit
import HistoryKit
import OverlayKit
import TourKit

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
    private var tours: TourCoordinator!
    private let hud = HUDController()
    private var opacityWatch: AnyCancellable?
    private var opacityDemo: OpacityDemo!
    private var loginPrompt: LaunchAtLoginPromptController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if SPARKLE_E2E_TEST
        // The throwaway build of scripts/sparkle-e2e-test.sh runs next to the user's real copy: it
        // only starts the updater — no menus, hotkeys, native-shortcut changes, history,
        // temp-file sweeps or onboarding window, which would touch the real app's shared state.
        NSApp.setActivationPolicy(.accessory)
        Updates.shared.start()
        #else
        // At login the app only takes its place in the Dock; any other launch shows a window (below).
        // Read first: the launch's Apple Event is only current while this method runs.
        let launchedAsLoginItem = LaunchAtLogin.launchedAsLoginItem
        // False when macOS relaunched us to restore the session ("Reopen windows when logging back in"),
        // which may not carry the login-item flag.
        let launchIsDefault = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        NSLog("BetterScreenshot launch: login item %d, default launch %d",
              launchedAsLoginItem ? 1 : 0, launchIsDefault ? 1 : 0)
        // Settings → Appearance → Opacity drives every DesignKit surface, live.
        // The Settings tour's demo previews values without saving them (`SettingsStore.opacityPreview`).
        opacityWatch = settings.$settings.map(\.uiOpacity).combineLatest(settings.$opacityPreview)
            .map { saved, preview in preview ?? saved }.removeDuplicates()
            .sink { UIOpacity.shared.value = $0 }
        // Guided tours (v3 spec §14.9): decide once, for good, whether this is a new user — before
        // anything below writes a preference (window frames, Sparkle's keys…) that would look like
        // earlier use. Existing users are never asked and never get a tour by themselves.
        TourCoordinator.classifyAudienceIfNeeded(
            screenRecordingGranted: PermissionManager.hasScreenRecordingPermission)
        // A regular Dock app since 3.3.0 (no LSUIElement): Dock icon, main menu, Dock menu (MenuBarController).
        tours = TourCoordinator(
            // The tag overlay, with its windows kept out of screen recordings (TourTagRecordingGate).
            makePresenter: { RecordingSafeTagPresenter() },
            shortcutText: { [weak self] name in
                guard let action = HotkeyAction(rawValue: name) else { return nil }
                return HotkeyCheatSheet.keys(for: action, in: self?.settings.bindings ?? .defaults)
                    ?? TourText.unboundShortcut
            })
        tours.notify = { [weak self] message in self?.hud.show(message, symbol: "questionmark.circle") }
        tours.install()
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
        recordingCoordinator.onStateChange = { [weak self] recording, elapsed in   // elapsed: the badge text
            self?.menuBar.setRecording(recording, badge: elapsed)
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
                    self.applyBindings()   // also refreshes the menu's shortcuts and its refused-combo list
                }
            })
        let tourSettings = TourSettingsActions(
            isEnabled: { [weak self] in self?.tours.firstUseToursEnabled ?? false },
            setEnabled: { [weak self] on in self?.tours.firstUseToursEnabled = on },
            resetAll: { [weak self] in self?.tours.resetAllTours() })
        settingsWindow = SettingsWindowController(store: settings, shortcuts: shortcuts,
                                                  clearHistory: { [weak self] in
            self?.history.clearAll()
        }, tours: tourSettings)
        menuBar = MenuBarController(coordinator: coordinator, settingsWindow: settingsWindow)
        menuBar.onReplayTour = { [weak self] tour in self?.tours.replay(tour, in: nil) }
        menuBar.onResetTours = { [weak self] in
            guard let self else { return }
            self.tours.resetAllTours()
            // With first-use tours off nothing starts by itself — the HUD says how to turn them on.
            self.hud.show(TourRules.resetConfirmation(firstUseToursEnabled: self.tours.firstUseToursEnabled),
                          symbol: "arrow.counterclockwise")
        }
        menuBar.onToggleRecording = { [weak self] in self?.recordingCoordinator.toggle() }
        menuBar.onOpenHistory = { [weak self] in self?.historyWindow.show() }
        menuBar.onRestoreRecentlyClosed = { [weak self] in self?.restoreRecentlyClosed() }
        menuBar.onPauseResume = { [weak self] in self?.recordingCoordinator.pauseResume() }
        menuBar.canRestore = { [weak self] in self?.history.canRestore ?? false }

        // "Check for Updates…" in the menu, Settings → Updates, and the daily background check.
        Updates.shared.start()
        // "Open BetterScreenshot at login?", once, after the 5th completed screenshot.
        loginPrompt = LaunchAtLoginPromptController()
        loginPrompt.isCaptureOrRecordingActive = { [weak self] in
            guard let self else { return false }
            return self.coordinator.isSelecting || self.recordingCoordinator.isBusy
        }
        loginPrompt.isMenuOpen = { [weak self] in self?.menuBar.isMenuOpen ?? false }
        menuBar.offersLoginQuestion = { [weak self] in self?.loginPrompt.offersMenuItem ?? false }
        menuBar.onAskLoginQuestion = { [weak self] in self?.loginPrompt.askFromMenu() }
        loginPrompt.quickAccessCorner = { [weak self] in self?.settings.settings.overlayCorner ?? .bottomRight }
        coordinator.onCaptureCompleted = { [weak self] in self?.loginPrompt.captureCompleted() }
        // Opened at login although our SMAppService login item is off: the user set it up another way
        // (the Dock's Options ▸ Open at Login, a Login Items entry) — they've answered, never ask.
        if launchedAsLoginItem, !LaunchAtLogin.isEnabled { LaunchAtLoginPrompt().markAsked() }

        // One-button first-run setup (Screen Recording is the only permission).
        onboarding = OnboardingController(bindings: { [weak self] in self?.settings.bindings ?? .defaults })
        onboarding.shouldAskTourQuestion = { [weak self] in self?.tours.shouldAskQuestion ?? false }
        onboarding.onTourAnswer = { [weak self] showMeAround, window in
            self?.tours.answerQuestion(showMeAround: showMeAround, in: window)
        }
        // Its job is done once the Welcome tour ends: don't leave it behind the Quick Access/Editor tours.
        tours.onFinished = { [weak self] id in
            if id == .welcome { self?.onboarding.close() }
        }
        // The Settings tour's Opacity step demonstrates the setting on the real windows.
        opacityDemo = OpacityDemo(store: settings)
        tours.onStepShown = { [weak self] anchor in self?.opacityDemo.setRunning(anchor == OpacityDemo.anchor) }
        coordinator.presentSetup = { [weak self] in self?.onboarding.show(.needsPermission) }
        recordingCoordinator.presentSetup = { [weak self] in self?.onboarding.show(.needsPermission) }
        // Help & Tours can open these windows so a requested tour starts; the rest wait for the user.
        tours.openSurface = { [weak self] surface in
            guard let self else { return false }
            switch surface {
            case .welcome:
                self.onboarding.show(PermissionManager.hasScreenRecordingPermission ? .allSet : .needsPermission)
            case .settings: self.settingsWindow.show()
            case .history: self.historyWindow.show()
            default: return false
            }
            return true
        }
        switch LaunchWindowPolicy.window(
            permissionGranted: PermissionManager.hasScreenRecordingPermission,
            launchedAsLoginItem: launchedAsLoginItem, launchIsDefault: launchIsDefault,
            relaunchedAfterGrant: { OnboardingController.consumeRelaunchFlag() },
            opensWelcome: { tours.shouldOpenWelcomeOnLaunch(permissionGranted: true) }) {   // new user, unasked
        case .setup: onboarding.show(.needsPermission)
        case .welcome: onboarding.show(.allSet)
        case .settings: settingsWindow.show()
        case .none: break
        }
        // Launch at login is no longer switched on silently at first launch (≤ 3.1.0 did, flag
        // `didRegisterLaunchAtLogin`, now only read): `loginPrompt` asks once, after 5 captures.
        applyBindings()
        // Stop macOS's native ⌘⇧3/⌘⇧4/⌘⇧5 from also firing (double screenshot/recording). Restored on quit.
        SystemScreenshotShortcuts.disableNativeShortcuts()
        #endif
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
        menuBar.refreshKeyEquivalents(settings.bindings, unregistered: failed)
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

    /// Clicking the Dock icon (or opening the app again from Finder): unhides a hidden app, brings it forward
    /// when one of our windows is up, puts a minimized one back, else opens Settings
    /// (`LaunchWindowPolicy.reopen`). The floating panels (Quick Access, pins, recording controls, HUD)
    /// don't count as windows here.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        #if !SPARKLE_E2E_TEST
        let windows = NSApp.windows.filter { !($0 is NSPanel) && $0.styleMask.contains(.titled) }
        switch LaunchWindowPolicy.reopen(isHidden: NSApp.isHidden,
                                         hasVisibleWindow: windows.contains { $0.isVisible },
                                         hasMinimizedWindow: windows.contains { $0.isMiniaturized }) {
        case .unhide: NSApp.unhide(nil); return false
        case .bringForward: return true
        case .restoreMinimized: windows.first { $0.isMiniaturized }?.deminiaturize(nil); return false
        case .settings: settingsWindow.show(); return false
        }
        #else
        return true
        #endif
    }

    /// The Dock icon's right-click menu: every capture, recording and app action (`MenuBarController`).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        #if SPARKLE_E2E_TEST
        return nil
        #else
        return menuBar?.dockMenu()
        #endif
    }

    /// Closing the last window never quits: the capture shortcuts keep working. ⌘Q quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        #if !SPARKLE_E2E_TEST   // the e2e build never restores the native shortcuts the real copy turned off
        recordingCoordinator?.stopForTermination()
        SystemScreenshotShortcuts.restoreNativeShortcuts()
        #endif
    }
}
