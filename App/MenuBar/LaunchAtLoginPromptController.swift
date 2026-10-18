import AppKit
import CaptureKit
import OverlayKit

/// "Open BetterScreenshot at login?" — asked after the 5th completed screenshot (rules, the
/// calm-moment test and every flow decision: CaptureKit `LaunchAtLoginPrompt`, unit-tested; same
/// behaviour as MacStats and JVoice; docs/sparkle-updates/README.md). Replaces ≤ 3.1.0's silent
/// first-launch enable. This class only carries the decisions out.
///
/// After a counted capture makes it due (`afterCapture`), it checks once a second (`waitStep`, for up
/// to `giveUpSeconds`) for a calm moment — the capture settled for 3 s, no key pressed for 2 s, no
/// mouse button down, the menu-bar menu closed, no selection / countdown / record strip /
/// recording, none of our windows in front — then shows a card in the top-right screen corner
/// (bottom-right when Quick Access uses the top-right corner). The card never takes focus, is left
/// out of every screenshot (`windowIDs`) and recording (its window is registered with
/// `TourTagRecordingGate`). Unanswered, it goes away after `unansweredHideSeconds` (not while the
/// pointer is on it) and comes back after a later capture, at most `maxShowings` times. Answers:
/// **No Thanks**, or **Open at Login** → `SMAppService.mainApp.register()`, then "will open at login"
/// (closes after 1.6 s), "One more step" + **Open Login Items** (`.requiresApproval`) or "Couldn't
/// turn it on." (error). The Settings switch re-reads the status on every change.
@MainActor
final class LaunchAtLoginPromptController {
    private let rules = LaunchAtLoginPrompt()
    /// Made on the first `show`, so users who are never asked never get the window.
    private var card: PromptCardController?
    private var waitTimer: Timer?
    private var lastCaptureAt = Date.distantPast
    private var closeTask: Task<Void, Never>?
    /// The card is up with the question (not a result line), since `askedAt`.
    private var asking = false
    private var askedAt = Date.distantPast
    private var unansweredTimer: Timer?
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
                guard let self, self.asking, self.rules.asked else { return }
                self.close()
            }
        }
    }

    /// A screenshot finished with an image (area, window, full screen, Capture Text). Cancelled
    /// selections and failed captures never get here.
    func captureCompleted() {
        rules.recordUse()
        lastCaptureAt = Date()
        switch LaunchAtLoginPrompt.afterCapture(couldAsk: rules.couldAsk, cardVisible: card?.isVisible ?? false,
                                                isEnabled: { LaunchAtLogin.isEnabled }) {
        case .nothing: break
        case .startWaiting: startWaiting()
        case .alreadyEnabled: rules.markAsked()   // never asked, and no capture reads the status again
        }
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
            menuIsOpen: isMenuOpen())
        switch LaunchAtLoginPrompt.waitStep(moment, couldAsk: rules.couldAsk, isEnabled: { LaunchAtLogin.isEnabled }) {
        case .keepWaiting: break
        case .giveUp, .noLongerDue: stopWaiting()
        case .alreadyEnabled: stopWaiting(); rules.markAsked()
        case .show: stopWaiting(); ask()
        }
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
        asking = true
        askedAt = Date()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkUnanswered() }
        }
        RunLoop.main.add(timer, forMode: .common)
        unansweredTimer = timer
    }

    /// Hides the question after `unansweredHideSeconds`, like a banner, so it never stays over a
    /// presentation or a shared screen; a later capture brings it back (`recordUnansweredShowing`).
    private func checkUnanswered() {
        guard asking, let card else { stopUnansweredTimer(); return }
        let pointerOnCard = card.window.frame.contains(NSEvent.mouseLocation)
        guard LaunchAtLoginPrompt.shouldHideUnanswered(secondsShown: Date().timeIntervalSince(askedAt),
                                                       pointerOnCard: pointerOnCard) else { return }
        rules.recordUnansweredShowing()
        close()
    }

    private func stopUnansweredTimer() {
        unansweredTimer?.invalidate()
        unansweredTimer = nil
    }

    private func openAtLogin() {
        asking = false
        stopUnansweredTimer()
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
        default:
            show(title: "Couldn't turn it on.",
                 message: "You can try again in Settings → Launch at login.",
                 actions: [.init("Done", primary: true) { [weak self] in self?.close() }])
        }
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
        stopUnansweredTimer()
        asking = false
        card?.hide()
    }
}
