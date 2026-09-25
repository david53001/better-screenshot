import AppKit
import Combine
import SwiftUI
import CaptureKit
import TourKit

/// Owns the single Settings window. Replaces the SwiftUI `Settings` scene, whose
/// private `showSettingsWindow:` opener silently broke on macOS 14 for
/// LSUIElement apps.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: SettingsStore
    private let shortcuts: ShortcutActions
    private let clearHistory: () -> Void
    private let tours: TourSettingsActions
    /// Keeps the ⓘ's Keyboard Shortcuts list in step with rebinds made in this window.
    private var bindingsWatch: AnyCancellable?

    init(store: SettingsStore, shortcuts: ShortcutActions, clearHistory: @escaping () -> Void,
         tours: TourSettingsActions) {
        self.store = store
        self.shortcuts = shortcuts
        self.clearHistory = clearHistory
        self.tours = tours
    }

    func show() {
        if window == nil { window = makeWindow() }
        if let window { WindowPlacer.place(window) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)   // ★ after makeKey, matching OnboardingController
        // The Settings tour's first time (spec §14.3); a no-op unless tours are on.
        if let window { TourEvents.surfaceShown(.settings, in: window) }
    }

    /// Builds the window (not shown). Internal so probes can show it behind the owner's windows.
    func makeWindow() -> NSWindow {
        let view = SettingsView(store: store, shortcuts: shortcuts, clearHistory: clearHistory,
                                tours: tours)
        let hosting = NSHostingController(rootView: view)
        hosting.view.appearance = NSAppearance(named: .darkAqua)
        let w = NSWindow(contentViewController: hosting)
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.title = "Settings"
        w.appearance = NSAppearance(named: .darkAqua)
        w.titlebarAppearsTransparent = true
        w.backgroundColor = .black
        w.isReleasedWhenClosed = false

        let maxH = (NSScreen.main?.visibleFrame.height ?? 900) * 0.98
        let fittingHeight = hosting.view.fittingSize.height
        let height = fittingHeight > 0 ? min(fittingHeight, maxH) : maxH
        w.setContentSize(NSSize(width: 960, height: height))

        // ⓘ: Replay Tour + the capture shortcuts this window edits, as currently bound.
        let info = InfoButton.install(in: w, tour: .settings, shortcuts: Self.infoShortcuts(store.bindings))
        bindingsWatch = store.$bindings.sink { [weak info] bindings in
            info?.shortcuts = Self.infoShortcuts(bindings)
        }
        return w
    }

    /// The ⓘ's Keyboard Shortcuts list: every bound action (as the Keyboard Shortcuts card shows it),
    /// then the one key the card itself uses.
    static func infoShortcuts(_ bindings: HotkeyBindings) -> [(keys: String, action: String)] {
        HotkeyAction.allCases.compactMap { action in
            bindings.combo(for: action).map { (keys: $0.displayString, action: action.title) }
        } + [(keys: "Esc", action: "Cancel changing a shortcut")]
    }
}
