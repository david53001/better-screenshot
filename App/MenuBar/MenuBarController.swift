import AppKit
import CaptureKit
import TourKit

/// The app's menus. BetterScreenshot is a Dock app since 3.3.0 (no status item): its **main menu**
/// (the menu bar at the top while it's in front — App · Capture · Edit · Window · Help) and its
/// **Dock menu** (right-click the Dock icon, `applicationDockMenu`) both carry every action of the old
/// status-item menu, through the same targets here.
@MainActor
final class MenuBarController: NSObject {
    private let coordinator: CaptureCoordinator
    private let settingsWindow: SettingsWindowController

    init(coordinator: CaptureCoordinator, settingsWindow: SettingsWindowController) {
        self.coordinator = coordinator
        self.settingsWindow = settingsWindow
        super.init()
        NSApp.mainMenu = makeMainMenu()
        // Any of our menus open (the main menu, a context menu): the launch-at-login card waits.
        for (name, open) in [(NSMenu.didBeginTrackingNotification, true), (NSMenu.didEndTrackingNotification, false)] {
            trackingObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isMenuOpen = open }
            })
        }
    }

    /// Main-menu items whose key equivalent shows a capture shortcut (`refreshKeyEquivalents`).
    private var actionItems: [HotkeyAction: NSMenuItem] = [:]
    private var bindings = HotkeyBindings.defaults
    /// Bound actions macOS refused to register (`HotKeyManager.apply`): only their menu item can fire them.
    private var unregistered: Set<HotkeyAction> = []
    private var isRecording = false
    private var isPaused = false
    private var trackingObservers: [NSObjectProtocol] = []

    /// One of our menus is being tracked. The one-time launch-at-login card waits for it to close
    /// (`LaunchAtLoginPromptController.isMenuOpen`). The Dock menu is the Dock's, so it can't be seen
    /// here — it opens at the bottom of the screen, far from the card.
    private(set) var isMenuOpen = false

    /// Every item carries an SF Symbol. macOS 26 adds a gear to "Settings…" on its
    /// own, which pushed Settings and Quit out of line with the rest; with an icon on
    /// every item the titles line up on every macOS version.
    private static func icon(_ symbol: String) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    @discardableResult
    private func add(_ title: String, _ symbol: String?, _ sel: Selector, to menu: NSMenu,
                     key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: sel, keyEquivalent: key)
        item.target = target ?? self
        item.image = symbol.flatMap(Self.icon)
        return item
    }

    /// Capture Area … Restore Recently Closed — the Capture menu and the top of the Dock menu.
    private func addCaptureItems(to menu: NSMenu, inMainMenu: Bool) {
        func add(_ title: String, _ symbol: String, _ sel: Selector, _ action: HotkeyAction) {
            let item = self.add(title, symbol, sel, to: menu)
            if inMainMenu { actionItems[action] = item }
        }
        add("Capture Area", "rectangle.dashed", #selector(area), .captureArea)
        add("Capture Window", "macwindow", #selector(window), .captureWindow)
        add("Capture Full Screen", "display", #selector(full), .captureFullscreen)
        add("Capture Text", "text.viewfinder", #selector(captureText), .captureText)
        add("Record Screen…", "record.circle", #selector(toggleRecording), .record)        // title: `refresh`
        add("Pause Recording", "pause.circle", #selector(togglePauseResume), .pauseResumeRecording)
        menu.addItem(.separator())
        add("Pin from Clipboard", "pin", #selector(pinClipboard), .pinFromClipboard)
        menu.addItem(.separator())
        add("History…", "clock.arrow.circlepath", #selector(openHistory), .openHistory)
        add("Restore Recently Closed", "arrow.uturn.backward", #selector(restoreClosed), .restoreRecentlyClosed)
    }

    /// Open at Login… (only while due) · Check for Updates… · Settings… — in the App menu and the Dock menu.
    private func addAppItems(to menu: NSMenu, settingsKey: String) {
        add("Open at Login…", "power.circle", #selector(askLoginQuestion), to: menu)
        add("Check for Updates…", "arrow.triangle.2.circlepath", #selector(checkForUpdates), to: menu)
        add("Settings…", "gearshape", #selector(openSettings), to: menu, key: settingsKey)
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        @discardableResult
        func top(_ title: String, _ build: (NSMenu) -> Void) -> NSMenu {
            let menu = NSMenu(title: title)
            build(menu)
            main.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = menu
            return menu
        }
        let app = top("BetterScreenshot") { m in
            add("About BetterScreenshot", "info.circle",
                #selector(NSApplication.orderFrontStandardAboutPanel(_:)), to: m, target: NSApp)
            m.addItem(.separator())
            addAppItems(to: m, settingsKey: ",")
            m.addItem(.separator())
            add("Hide BetterScreenshot", "eye.slash", #selector(NSApplication.hide(_:)), to: m, key: "h", target: NSApp)
            add("Hide Others", nil, #selector(NSApplication.hideOtherApplications(_:)), to: m, key: "h", target: NSApp)
                .keyEquivalentModifierMask = [.command, .option]
            add("Show All", nil, #selector(NSApplication.unhideAllApplications(_:)), to: m, target: NSApp)
            m.addItem(.separator())
            add("Quit BetterScreenshot", "power", #selector(NSApplication.terminate(_:)), to: m, key: "q", target: NSApp)
        }
        app.delegate = self   // refresh: Open at Login…, Check for Updates…
        top("Capture") { m in addCaptureItems(to: m, inMainMenu: true) }.delegate = self   // refresh: Record, Pause
        // Standard editing for the text fields in Settings and the editor (the editor's own ⌘Z/⌘⇧Z run first:
        // a key window gets key equivalents before the main menu does).
        top("Edit") { m in
            m.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
            m.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
            m.addItem(.separator())
            m.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            m.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            m.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            m.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
            m.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        }
        NSApp.windowsMenu = top("Window") { m in
            m.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
            m.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
            m.addItem(.separator())
            m.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
            m.addItem(.separator())
            m.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)),
                      keyEquivalent: "")
        }
        // Help: the Help & Tours items themselves.
        let help = Self.helpToursItem(target: self, replay: #selector(replayTour(_:)), reset: #selector(resetTours))
        help.title = "Help"
        help.image = nil   // a menu-bar title, not an icon
        help.submenu?.title = "Help"
        main.addItem(help)
        NSApp.helpMenu = help.submenu
        return main
    }

    /// The Dock icon's right-click menu, made fresh each time it opens (the Dock adds Options, Show All
    /// Windows, Hide and Quit itself). Its state is set here, not by menu validation.
    func dockMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addCaptureItems(to: menu, inMainMenu: false)
        menu.addItem(.separator())
        menu.addItem(Self.helpToursItem(target: self, replay: #selector(replayTour(_:)), reset: #selector(resetTours)))
        addAppItems(to: menu, settingsKey: "")
        for item in menu.items {
            refresh(item)
            item.isEnabled = isEnabled(item)
        }
        menu.items.filter(\.isHidden).forEach(menu.removeItem)   // e.g. Pause while not recording
        return menu
    }

    /// "Help & Tours ▸": Take the Welcome Tour · one "<Name> Tour" per other tour · Reset All Tours
    /// (v3 spec §14.3). Each tour item carries its `TourID` raw value as `representedObject`. Static so
    /// probes can build it without the app's menus.
    static func helpToursItem(target: AnyObject, replay: Selector, reset: Selector) -> NSMenuItem {
        let submenu = NSMenu(title: "Help & Tours")
        func add(_ title: String, _ symbol: String, _ action: Selector, _ tour: TourID?) {
            let item = submenu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = target
            item.image = icon(symbol)
            item.representedObject = tour?.rawValue
        }
        add("Take the Welcome Tour", TourID.welcome.menuSymbol, replay, .welcome)
        submenu.addItem(.separator())
        for tour in TourID.allCases where tour != .welcome {
            add(tour.menuTitle, tour.menuSymbol, replay, tour)
        }
        submenu.addItem(.separator())
        add("Reset All Tours", "arrow.counterclockwise", reset, nil)
        let parent = NSMenuItem(title: "Help & Tours", action: nil, keyEquivalent: "")
        parent.image = icon("questionmark.circle")
        parent.submenu = submenu
        return parent
    }

    /// The Capture menu shows the current combos. Firing stays Carbon (`HotKeyManager`), which takes the
    /// keystroke even while BetterScreenshot is in front; `fromCarbonHotkey` keeps a key equivalent from
    /// running the action a second time should AppKit ever see that keystroke too.
    func refreshKeyEquivalents(_ bindings: HotkeyBindings, unregistered: Set<HotkeyAction>) {
        self.bindings = bindings
        self.unregistered = unregistered
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

    /// The item was chosen by typing `action`'s registered Carbon combo — Carbon runs it already.
    private func fromCarbonHotkey(_ action: HotkeyAction) -> Bool {
        guard let event = NSApp.currentEvent, event.type == .keyDown, !unregistered.contains(action),
              let combo = bindings.combo(for: action) else { return false }
        return HotkeyCombo(keyCode: UInt32(event.keyCode),
                           cocoaModifierFlagsRaw: UInt(event.modifierFlags.rawValue)) == combo
    }

    private func perform(_ action: HotkeyAction, _ body: () -> Void) {
        if !fromCarbonHotkey(action) { body() }
    }

    @objc private func area() { perform(.captureArea) { coordinator.captureArea() } }
    /// From a menu, the window meant is the user's, not our Settings / History / editor window in front of it.
    @objc private func window() { perform(.captureWindow) { coordinator.captureFrontWindow(skippingOwnWindows: true) } }
    @objc private func full() { perform(.captureFullscreen) { coordinator.captureFullscreen() } }
    @objc private func captureText() { perform(.captureText) { coordinator.captureText() } }
    @objc private func pinClipboard() { perform(.pinFromClipboard) { coordinator.pinFromClipboard() } }
    @objc private func toggleRecording() { perform(.record) { onToggleRecording?() } }
    @objc private func openHistory() { perform(.openHistory) { onOpenHistory?() } }
    @objc private func restoreClosed() { perform(.restoreRecentlyClosed) { onRestoreRecentlyClosed?() } }
    @objc private func togglePauseResume() { perform(.pauseResumeRecording) { onPauseResume?() } }
    var onToggleRecording: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onRestoreRecentlyClosed: (() -> Void)?
    var onPauseResume: (() -> Void)?
    /// Menu validation: false disables "Restore Recently Closed".
    var canRestore: (() -> Bool)?

    /// "Open at Login…": shown while the one-time launch-at-login question is due, and what it does
    /// (`LaunchAtLoginPromptController.offersMenuItem` / `askFromMenu`, set by the app delegate).
    var offersLoginQuestion: (() -> Bool)?
    var onAskLoginQuestion: (() -> Void)?
    @objc private func askLoginQuestion() { onAskLoginQuestion?() }

    /// Help & Tours: run a tour (from its first step) / clear which tours were seen.
    var onReplayTour: ((TourID) -> Void)?
    var onResetTours: (() -> Void)?
    @objc private func replayTour(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tour = TourID(rawValue: raw) else { return }
        onReplayTour?(tour)
    }
    @objc private func resetTours() { onResetTours?() }

    /// Pause/Resume item: shown only while recording/paused; title flips on state (`refresh`).
    func setPauseItem(active: Bool, paused: Bool) {
        isPaused = active && paused
    }

    /// While recording, the elapsed time is the Dock icon's badge (the status item's red stop icon and
    /// timer before 3.3.0); Record Screen… reads Stop Recording.
    func setRecording(_ recording: Bool, elapsed: String?) {
        isRecording = recording
        let badge = recording ? (elapsed ?? "") : nil
        if NSApp.dockTile.badgeLabel != badge { NSApp.dockTile.badgeLabel = badge }
    }

    /// Titles and visibility that follow the app's state (`menuNeedsUpdate`, `dockMenu`).
    private func refresh(_ item: NSMenuItem) {
        switch item.action {
        case #selector(toggleRecording):
            item.title = isRecording ? "Stop Recording" : "Record Screen…"
            item.image = Self.icon(isRecording ? "stop.circle" : "record.circle")
        case #selector(togglePauseResume):
            item.isHidden = !isRecording
            item.title = isPaused ? "Resume Recording" : "Pause Recording"
            item.image = Self.icon(isPaused ? "play.circle" : "pause.circle")
        case #selector(askLoginQuestion):
            item.isHidden = !(offersLoginQuestion?() ?? false)
        case #selector(checkForUpdates):
            // Until the user has looked at it, a found update is named right in the menu.
            item.title = Updates.shared.actionTitle
        default: break
        }
    }

    private func isEnabled(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(pinClipboard): return coordinator.clipboardHasImage
        case #selector(restoreClosed): return canRestore?() ?? false
        case #selector(checkForUpdates): return Updates.shared.canCheckOrShow
        default: return true
        }
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
    /// Sparkle's window: the result of a check, or the update a background check found.
    @objc private func checkForUpdates() { Updates.shared.checkForUpdates() }
}

extension MenuBarController: NSMenuDelegate {
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { menu.items.forEach(refresh) }
    }
}

extension MenuBarController: NSMenuItemValidation {
    nonisolated func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        MainActor.assumeIsolated { isEnabled(menuItem) }
    }
}
