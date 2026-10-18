import AppKit
import CaptureKit
import OverlayKit

/// "Open BetterScreenshot at login?" — asked after the 5th completed screenshot (rules, the
/// calm-moment test and every flow decision: CaptureKit `LaunchAtLoginPrompt`, unit-tested; same
/// behaviour as MacStats and JVoice; docs/sparkle-updates/README.md). Replaces ≤ 3.1.0's silent
/// first-launch enable. This class only reads the system state and carries the decisions out.
///
/// After a capture makes it due (`afterCapture`), it checks once a second (`waitStep`, for up to
/// `giveUpSeconds`) for a calm moment — the capture settled for 3 s, no key pressed for 2 s, no
/// mouse button down, the menu-bar menu closed, no selection / countdown / record strip /
/// recording, none of our windows in front, nothing full-screen in front (AppKit would put the
/// card on a full-screen Space; `LaunchAtLoginPrompt.fullScreenInFront`) — then shows a card in
/// the top-right screen corner (bottom-right when Quick Access uses the top-right corner). The card
/// never takes focus, is left out of every screenshot (`windowIDs`) and recording (its window is
/// registered with `TourTagRecordingGate`). Unanswered, it goes away after `unansweredHideSeconds`
/// (not while the pointer is on it); if the user could have seen it (`LaunchAtLoginPrompt.Showing`)
/// that counts as one of `maxShowings`, and it comes back after a later capture at least a day later
/// (relaunches included); if not, after a capture at least 10 minutes later. While the question is
/// due, the menu-bar menu also has **Open at Login…** (`askFromMenu`): the same question in a
/// standard alert, the card's keyboard path. Answers: **No Thanks**, or
/// **Open at Login** → `SMAppService.mainApp.register()`, then "will open at login" (closes after
/// 1.6 s), "One more step" + **Open Login Items** (`.requiresApproval`) or "Couldn't turn it on."
/// (error); those two also go away after `unansweredHideSeconds`. The Settings switch re-reads the
/// status on every change.
@MainActor
final class LaunchAtLoginPromptController {
    private let rules = LaunchAtLoginPrompt()
    /// Made on the first `show`, so users who are never asked never get the window.
    private var card: PromptCardController?
    private var waitTimer: Timer?
    private var lastCaptureAt = Date.distantPast
    private var closeTask: Task<Void, Never>?
    /// The question is up (not a result line): how much of it the user could have seen.
    private var showing: LaunchAtLoginPrompt.Showing?
    /// A result card that waits for a click ("One more step", "Couldn't turn it on.") is up since then.
    private var resultShownAt: Date?
    private var lastHideTick = Date()
    private var hideTimer: Timer?
    /// When the last showing that didn't count ended (`LaunchAtLoginPrompt.reshowAfterUnseenSeconds`).
    private var unseenShowingEndedAt: Date?
    private var settingsObserver: NSObjectProtocol?

    /// A selection overlay, countdown, record strip or recording is up (set by the app delegate).
    var isCaptureOrRecordingActive: () -> Bool = { false }
    /// The menu-bar menu is open (set by the app delegate from `MenuBarController.isMenuOpen`).
    var isMenuOpen: () -> Bool = { false }
    /// Settings → Quick Access Overlay → Screen corner, so the card doesn't sit on the thumbnails.
    var quickAccessCorner: () -> OverlayCorner = { .bottomRight }

    /// Card windows on screen, for the capture filters.
    static var windowIDs: Set<CGWindowID> {
        Set(PromptCardController.allWindowNumbers.map { CGWindowID($0) })
    }

    init() {
        // A choice made in Settings while the card is up answers it (LaunchAtLogin marks it asked).
        settingsObserver = NotificationCenter.default.addObserver(
            forName: LaunchAtLogin.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.showing != nil, self.rules.asked else { return }
                self.close()
            }
        }
    }

    /// A screenshot finished with an image (area, window, full screen, Capture Text). Cancelled
    /// selections and failed captures never get here.
    func captureCompleted() {
        lastCaptureAt = Date()
        let step = rules.afterCapture(cardVisible: card?.isVisible ?? false,
                                      unseenShowingEndedAt: unseenShowingEndedAt,
                                      isEnabled: { LaunchAtLogin.isEnabled })
        if step == .startWaiting { startWaiting() }   // the rest needs nothing here (`afterCapture` marks asked)
    }

    private func startWaiting() {
        guard waitTimer == nil else { return }   // already waiting; lastCaptureAt moved on
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        waitTimer = timer
    }

    private func stopWaiting() {
        waitTimer?.invalidate()
        waitTimer = nil
    }

    private func tick() {
        let moment = LaunchAtLoginPrompt.Moment(
            secondsSinceCapture: Date().timeIntervalSince(lastCaptureAt),
            secondsSinceKeyPress: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
            mouseButtonDown: NSEvent.pressedMouseButtons != 0,
            captureOrRecordingActive: isCaptureOrRecordingActive(),
            appIsActive: NSApp.isActive,
            menuIsOpen: isMenuOpen(),
            fullScreenInFront: Self.frontmostAppCoversAScreen())
        switch rules.waitStep(moment, isEnabled: { LaunchAtLogin.isEnabled }) {
        case .keepWaiting: break
        case .giveUp, .noLongerDue, .alreadyEnabled: stopWaiting()   // `waitStep` marks asked if enabled
        case .show: stopWaiting(); ask()
        }
    }

    /// `LaunchAtLoginPrompt.fullScreenInFront` on the windows on screen now.
    private static func frontmostAppCoversAScreen() -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = list.compactMap { info -> LaunchAtLoginPrompt.WindowInfo? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { return nil }
            return .init(ownerPID: pid, layer: layer, bounds: bounds)
        }
        return LaunchAtLoginPrompt.fullScreenInFront(
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            windows: windows,
            screens: NSScreen.screens.map { .init(frame: $0.frame, topInset: $0.safeAreaInsets.top) })
    }

    private func ask() {
        show(title: "Open BetterScreenshot at login?",
             message: "Your capture shortcuts keep working after a restart. You can change this any time in Settings.",
             actions: [
                .init("No Thanks") { [weak self] in
                    self?.rules.markAsked()
                    self?.close()
                },
                .init("Open at Login", primary: true) { [weak self] in self?.openAtLogin() },
             ])
        showing = LaunchAtLoginPrompt.Showing()
        startHideTimer()
    }

    private func startHideTimer() {
        hideTimer?.invalidate()
        lastHideTick = Date()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private func stopHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    /// Hides a card nobody answers after `unansweredHideSeconds`, like a banner, so it never stays
    /// over a presentation or a shared screen. Only the question counts as a showing, and only if
    /// the user could have seen it (`cardHidUnanswered`).
    private func hideTick() {
        guard let card, showing != nil || resultShownAt != nil else { stopHideTimer(); return }
        let now = Date()
        let pointerOnCard = card.window.frame.contains(NSEvent.mouseLocation)
        if var current = showing {
            current.tick(seconds: now.timeIntervalSince(lastHideTick),
                         cardVisible: card.window.occlusionState.contains(.visible) && card.window.isOnActiveSpace,
                         secondsSinceInput: CGEventSource.secondsSinceLastEventType(
                            .combinedSessionState, eventType: Self.anyInputEvent))
            showing = current
            lastHideTick = now
            guard LaunchAtLoginPrompt.shouldHideUnanswered(secondsShown: current.secondsShown,
                                                           pointerOnCard: pointerOnCard) else { return }
            if !rules.cardHidUnanswered(current, now: now) { unseenShowingEndedAt = now }
            close()
        } else if let resultShownAt,
                  LaunchAtLoginPrompt.shouldHideUnanswered(secondsShown: now.timeIntervalSince(resultShownAt),
                                                           pointerOnCard: pointerOnCard) {
            close()
        }
    }

    /// `kCGAnyInputEventType` (not imported into Swift): any key, click, scroll or mouse move.
    private static let anyInputEvent = CGEventType(rawValue: ~0)!

    // MARK: The menu-bar path (keyboard)

    /// Whether the menu-bar menu shows **Open at Login…** (`LaunchAtLoginPrompt.offersMenuItem`).
    var offersMenuItem: Bool { rules.offersMenuItem(isEnabled: { LaunchAtLogin.isEnabled }) }

    /// **Open at Login…** in the menu-bar menu: the same question as the card, in a standard alert
    /// that takes focus — the user asked for it — so Return and Escape answer it and Full Keyboard
    /// Access and VoiceOver reach it. Closes the card if it's up (not counted as a showing).
    func askFromMenu() {
        close()
        stopWaiting()
        NSApp.activate(ignoringOtherApps: true)   // an accessory app: else the alert opens behind
        let question = NSAlert()
        question.messageText = "Open BetterScreenshot at login?"
        question.informativeText = "Your capture shortcuts keep working after a restart. You can change this any time in Settings."
        question.addButton(withTitle: "Open at Login")
        question.addButton(withTitle: "No Thanks").keyEquivalent = "\u{1b}"   // Escape
        guard question.runModal() == .alertFirstButtonReturn else {
            rules.markAsked()
            return
        }
        let result = NSAlert()
        switch LaunchAtLogin.setEnabled(true) {   // also marks it asked
        case .enabled:
            return
        case .requiresApproval:
            result.messageText = "One more step"
            result.informativeText = "Allow BetterScreenshot in Login Items to finish."
            result.addButton(withTitle: "Open Login Items")
            result.addButton(withTitle: "Done").keyEquivalent = "\u{1b}"
            if result.runModal() == .alertFirstButtonReturn { LaunchAtLogin.openSystemSettings() }
        default:
            result.messageText = "Couldn't turn it on."
            result.informativeText = "You can try again in Settings → Launch at login."
            result.addButton(withTitle: "Done")
            result.runModal()
        }
    }

    private func openAtLogin() {
        showing = nil
        stopHideTimer()
        switch LaunchAtLogin.setEnabled(true) {   // also marks it asked
        case .enabled:
            show(title: "BetterScreenshot will open at login.", message: nil, actions: [])
            closeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard !Task.isCancelled else { return }
                self?.close()
            }
        case .requiresApproval:
            show(title: "One more step",
                 message: "Allow BetterScreenshot in Login Items to finish.",
                 actions: [
                    .init("Done") { [weak self] in self?.close() },
                    .init("Open Login Items", primary: true) { [weak self] in
                        LaunchAtLogin.openSystemSettings()
                        self?.close()
                    },
                 ])
            showResultUntilHidden()
        default:
            show(title: "Couldn't turn it on.",
                 message: "You can try again in Settings → Launch at login.",
                 actions: [.init("Done", primary: true) { [weak self] in self?.close() }])
            showResultUntilHidden()
        }
    }

    /// A result card with buttons goes away by itself too (Settings shows the same state).
    private func showResultUntilHidden() {
        resultShownAt = Date()
        startHideTimer()
    }

    private func show(title: String, message: String?, actions: [PromptCardController.Action]) {
        closeTask?.cancel()
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let shown: PromptCardController
        if let existing = card {
            shown = existing
        } else {
            shown = PromptCardController()
            // Kept out of display recordings from its first frame, like the tour tags.
            TourTagRecordingGate.shared.register([shown.window])
            card = shown
        }
        shown.show(title: title, message: message, actions: actions, on: screen,
                  corner: quickAccessCorner() == .topRight ? .bottomRight : .topRight)
        TourTagRecordingGate.shared.sync()   // a first-time window now has a number
    }

    private func close() {
        closeTask?.cancel()
        stopHideTimer()
        showing = nil
        resultShownAt = nil
        card?.hide()
    }
}
