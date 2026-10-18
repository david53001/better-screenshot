import AppKit
import CaptureKit
import OverlayKit

/// "Open BetterScreenshot at login?" — asked once, after the 5th completed screenshot (rules and
/// the calm-moment test: CaptureKit `LaunchAtLoginPrompt`, unit-tested; same behaviour as MacStats
/// and JVoice; docs/sparkle-updates/README.md). Replaces ≤ 3.1.0's silent first-launch enable.
///
/// After a counted capture makes it due, it checks once a second (for up to `giveUpSeconds`) for a
/// calm moment — the capture settled for 3 s, no key pressed for 2 s, no mouse button down, no
/// selection / countdown / record strip / recording, none of our windows in front — then shows a
/// card in the top-right screen corner (bottom-right when Quick Access uses the top-right corner).
/// The card never takes focus, is left out of every screenshot (`windowIDs`) and recording (its
/// window is registered with `TourTagRecordingGate`), and stays until the user answers:
/// **No Thanks**, or **Open at Login** → `SMAppService.mainApp.register()`, then "will open at
/// login" (closes after 1.6 s), "One more step" + **Open Login Items** (`.requiresApproval`) or
/// "Couldn't turn it on." (error). The Settings switch re-reads the status on every change.
@MainActor
final class LaunchAtLoginPromptController {
    private let rules = LaunchAtLoginPrompt()
    private let card = PromptCardController()
    private var waitTimer: Timer?
    private var lastCaptureAt = Date.distantPast
    private var closeTask: Task<Void, Never>?
    /// The card is up with the question (not a result line).
    private var asking = false
    private var settingsObserver: NSObjectProtocol?

    /// A selection overlay, countdown, record strip or recording is up (set by the app delegate).
    var isCaptureOrRecordingActive: () -> Bool = { false }
    /// Settings → Quick Access Overlay → Screen corner, so the card doesn't sit on the thumbnails.
    var quickAccessCorner: () -> OverlayCorner = { .bottomRight }

    /// Card windows on screen, for the capture filters.
    static var windowIDs: Set<CGWindowID> {
        Set(PromptCardController.allWindowNumbers.map { CGWindowID($0) })
    }

    init() {
        // Kept out of display recordings from its first frame, like the tour tags.
        TourTagRecordingGate.shared.register([card.window])
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
        guard !card.isVisible, rules.couldAsk, !LaunchAtLogin.isEnabled else { return }
        startWaiting()
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
        let sinceCapture = Date().timeIntervalSince(lastCaptureAt)
        guard sinceCapture < LaunchAtLoginPrompt.giveUpSeconds else { stopWaiting(); return }
        let moment = LaunchAtLoginPrompt.Moment(
            secondsSinceCapture: sinceCapture,
            secondsSinceKeyPress: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
            mouseButtonDown: NSEvent.pressedMouseButtons != 0,
            captureOrRecordingActive: isCaptureOrRecordingActive(),
            appIsActive: NSApp.isActive)
        guard LaunchAtLoginPrompt.isCalmMoment(moment) else { return }
        stopWaiting()
        // Re-read: it may have been turned on in System Settings or Settings meanwhile.
        guard rules.couldAsk, !LaunchAtLogin.isEnabled else { return }
        ask()
    }

    private func ask() {
        asking = true
        show(title: "Open BetterScreenshot at login?",
             message: "Your capture shortcuts keep working after a restart. You can change this any time in Settings.",
             actions: [
                .init("No Thanks") { [weak self] in
                    self?.rules.markAsked()
                    self?.close()
                },
                .init("Open at Login", primary: true) { [weak self] in self?.openAtLogin() },
             ])
    }

    private func openAtLogin() {
        asking = false
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
        card.show(title: title, message: message, actions: actions, on: screen,
                  corner: quickAccessCorner() == .topRight ? .bottomRight : .topRight)
        TourTagRecordingGate.shared.sync()   // a first-time window now has a number
    }

    private func close() {
        closeTask?.cancel()
        asking = false
        card.hide()
    }
}
