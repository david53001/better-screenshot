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

    /// Every item carries an SF Symbol. macOS 26 adds a gear to "Settings…" on its
    /// own, which pushed Settings and Quit out of line with the rest; with an icon on
    /// every item the titles line up on every macOS version.
    private static func icon(_ symbol: String) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    private func buildMenu() {
        let menu = NSMenu()
        @discardableResult
        func add(_ title: String, _ symbol: String, _ sel: Selector, _ action: HotkeyAction?,
                 key: String = "") -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: sel, keyEquivalent: key)
            item.target = self
            item.image = Self.icon(symbol)
            if let action { actionItems[action] = item }
            return item
        }
        add("Capture Area", "rectangle.dashed", #selector(area), .captureArea)
        add("Capture Window", "macwindow", #selector(window), .captureWindow)
        add("Capture Full Screen", "display", #selector(full), .captureFullscreen)
        add("Capture Text", "text.viewfinder", #selector(captureText), .captureText)
        recordItem = add("Record Screen…", "record.circle", #selector(toggleRecording), .record)
        let pause = add("Pause Recording", "pause.circle", #selector(togglePauseResume), .pauseResumeRecording)
        pause.isHidden = true
        pauseItem = pause
        menu.addItem(.separator())
        add("Pin from Clipboard", "pin", #selector(pinClipboard), .pinFromClipboard)
        menu.addItem(.separator())
        add("History…", "clock.arrow.circlepath", #selector(openHistory), .openHistory)
        add("Restore Recently Closed", "arrow.uturn.backward", #selector(restoreClosed), .restoreRecentlyClosed)
        menu.addItem(.separator())
        add("Settings…", "gearshape", #selector(openSettings), nil, key: ",")
        add("Quit", "power", #selector(quit), nil, key: "q")
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
        pauseItem?.image = Self.icon(paused ? "play.circle" : "pause.circle")
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
            recordItem?.image = Self.icon("stop.circle")
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                               accessibilityDescription: "BetterScreenshot")
            statusItem.button?.contentTintColor = nil
            statusItem.button?.title = ""
            recordItem?.title = "Record Screen…"
            recordItem?.image = Self.icon("record.circle")
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
