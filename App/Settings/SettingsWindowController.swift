import AppKit
import SwiftUI

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

    init(store: SettingsStore, shortcuts: ShortcutActions, clearHistory: @escaping () -> Void,
         tours: TourSettingsActions) {
        self.store = store
        self.shortcuts = shortcuts
        self.clearHistory = clearHistory
        self.tours = tours
    }

    func show() {
        if window == nil {
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
            window = w
        }
        if let window { WindowPlacer.place(window) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)   // ★ after makeKey, matching OnboardingController
    }
}
