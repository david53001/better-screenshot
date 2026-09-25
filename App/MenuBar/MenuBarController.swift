import AppKit
import CaptureKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator: CaptureCoordinator
    private let settingsWindow: SettingsWindowController

    init(coordinator: CaptureCoordinator, settingsWindow: SettingsWindowController) {
        self.coordinator = coordinator
        self.settingsWindow = settingsWindow
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "BetterScreenshot")
        buildMenu()
    }

    private var actionItems: [HotkeyAction: NSMenuItem] = [:]
    private var recordItem: NSMenuItem?
    private var pauseItem: NSMenuItem?

    private func buildMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ sel: Selector, _ action: HotkeyAction?) {
            let item = menu.addItem(withTitle: title, action: sel, keyEquivalent: "")
            item.target = self
            if let action { actionItems[action] = item }
        }
        add("Capture Area", #selector(area), .captureArea)
        add("Capture Window", #selector(window), .captureWindow)
        add("Capture Full Screen", #selector(full), .captureFullscreen)
        add("Capture Text", #selector(captureText), .captureText)
        recordItem = menu.addItem(withTitle: "Record Screen…",
                                  action: #selector(toggleRecording), keyEquivalent: "")
        recordItem?.target = self
        if let recordItem { actionItems[.record] = recordItem }
        let pause = menu.addItem(withTitle: "Pause Recording",
                                 action: #selector(togglePauseResume), keyEquivalent: "")
        pause.target = self
        pause.isHidden = true
        pauseItem = pause
        if let pauseItem { actionItems[.pauseResumeRecording] = pauseItem }
        menu.addItem(.separator())
        add("Pin from Clipboard", #selector(pinClipboard), .pinFromClipboard)
        menu.addItem(.separator())
        add("History…", #selector(openHistory), .openHistory)
        add("Restore Recently Closed", #selector(restoreClosed), .restoreRecentlyClosed)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    /// Display-only: firing stays Carbon. Menus just show the current combos.
    func refreshKeyEquivalents(_ bindings: HotkeyBindings) {
        for (action, item) in actionItems {
            if let combo = bindings.combo(for: action) {
                item.keyEquivalent = combo.keyEquivalent
                item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: combo.cocoaModifierFlags)
            } else {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
            }
        }
    }

    @objc private func area() { coordinator.captureArea() }
    @objc private func window() { coordinator.captureFrontWindow() }
    @objc private func full() { coordinator.captureFullscreen() }
    @objc private func captureText() { coordinator.captureText() }
    @objc private func pinClipboard() { coordinator.pinFromClipboard() }
    var onToggleRecording: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onRestoreRecentlyClosed: (() -> Void)?
    var onPauseResume: (() -> Void)?
    /// Menu validation: false disables "Restore Recently Closed".
    var canRestore: (() -> Bool)?

    @objc private func toggleRecording() { onToggleRecording?() }
    @objc private func openHistory() { onOpenHistory?() }
    @objc private func restoreClosed() { onRestoreRecentlyClosed?() }
    @objc private func togglePauseResume() { onPauseResume?() }

    /// Pause/Resume item: shown only while recording/paused; title flips on state.
    func setPauseItem(active: Bool, paused: Bool) {
        pauseItem?.isHidden = !active
        pauseItem?.title = paused ? "Resume Recording" : "Pause Recording"
    }

    /// Red stop icon + elapsed timer while recording; normal icon otherwise.
    func setRecording(_ recording: Bool, elapsed: String?) {
        if recording {
            statusItem.button?.image = NSImage(systemSymbolName: "stop.circle.fill",
                                               accessibilityDescription: "Stop Recording")
            statusItem.button?.contentTintColor = .systemRed
            statusItem.button?.title = elapsed.map { " \($0)" } ?? ""
            statusItem.button?.imagePosition = .imageLeading
            statusItem.button?.font = .monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize, weight: .regular)
            recordItem?.title = "Stop Recording"
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                               accessibilityDescription: "BetterScreenshot")
            statusItem.button?.contentTintColor = nil
            statusItem.button?.title = ""
            recordItem?.title = "Record Screen…"
        }
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension MenuBarController: NSMenuItemValidation {
    nonisolated func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        MainActor.assumeIsolated {
            if menuItem.action == #selector(pinClipboard) { return coordinator.clipboardHasImage }
            if menuItem.action == #selector(restoreClosed) { return canRestore?() ?? false }
            return true
        }
    }
}
