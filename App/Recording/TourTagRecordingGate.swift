import AppKit
import ScreenCaptureKit
import TourKit

/// Keeps tour tags out of screen recordings — never, not even for one frame (owner, v3 spec §14).
///
/// A display recording's `SCContentFilter` leaves out windows by window number, and a window left out
/// stays left out while it's ordered out and back in (probed 2026-09-25). So:
/// - Every display filter is built by `displayFilter(_:content:alsoExcluding:)`, which leaves out **every
///   tag window that exists** — shown or not; the recorder fetches its content with
///   `onScreenWindowsOnly: false` so ordered-out tag windows are listed too.
/// - A tag window the filter doesn't cover (a tag shown for the very first time while recording) is kept
///   fully transparent (alpha 0) until the running stream's filter has been updated to leave it out:
///   the gate asks through `onNeedsExclusion`, the recorder rebuilds the filter and brackets the update
///   with `willUse` / `didUse`. Tag windows are registered the moment they're created
///   (`RecordingSafeTagPresenter`), so this holds from their very first frame on screen.
/// Window recordings (a single-window filter) never capture our own windows and don't use the gate.
@MainActor
final class TourTagRecordingGate {
    static let shared = TourTagRecordingGate()

    private struct Entry { weak var window: NSWindow? }
    private var entries: [Entry] = []
    /// A display recording is set up (its filter chosen) or running.
    private(set) var isActive = false
    /// Tag windows the chosen filter leaves out — while active, the only tag windows that may be seen.
    private var covered: Set<CGWindowID> = []
    /// Bumped by every filter choice; a `didUse` for an older one is ignored.
    private var token = 0
    /// Set by the recorder while its stream runs: rebuild the filter so it covers every tag window.
    var onNeedsExclusion: (() -> Void)?
    private var timer: Timer?

    /// Every tour-tag window, handed over as soon as it's created (before it's first ordered in).
    func register(_ windows: [NSWindow]) {
        entries.removeAll { $0.window == nil }
        for w in windows where !entries.contains(where: { $0.window === w }) { entries.append(Entry(window: w)) }
        sync()
    }

    /// Tag windows the window server knows about (shown at least once) — the ones a filter can leave out.
    var windowIDs: [CGWindowID] { entries.compactMap { $0.window.flatMap(Self.id) } }

    /// A filter for `display` without `alsoExcluding` and without every tag window listed in `content`,
    /// plus the tag windows it covers.
    func displayFilter(_ display: SCDisplay, content: SCShareableContent,
                       alsoExcluding: [SCWindow]) -> (filter: SCContentFilter, tags: Set<CGWindowID>) {
        let ids = Set(windowIDs)
        let tags = content.windows.filter { ids.contains($0.windowID) }
        return (SCContentFilter(display: display, excludingWindows: alsoExcluding + tags), Set(tags.map(\.windowID)))
    }

    /// A filter covering `tags` is chosen for a stream that isn't capturing yet (it starts with it).
    func use(_ tags: Set<CGWindowID>) {
        token += 1
        isActive = true
        covered = tags
        startTimer()
        sync()
    }

    /// Before a running stream switches to a filter covering `tags`: tag windows only the old filter
    /// covered are hidden now. Returns the token for `didUse`.
    func willUse(_ tags: Set<CGWindowID>) -> Int {
        token += 1
        covered.formIntersection(tags)
        sync()
        return token
    }

    /// The running stream now uses the filter from `willUse` (`token`): its tag windows may be seen.
    func didUse(_ tags: Set<CGWindowID>, token: Int) {
        guard isActive, token == self.token else { return }
        covered = tags
        sync()
    }

    /// The stream has stopped (or never started): every tag may be seen again.
    func end() {
        token += 1
        isActive = false
        covered = []
        onNeedsExclusion = nil
        timer?.invalidate()
        timer = nil
        sync()
    }

    /// Makes each tag window visible only when allowed; asks for a filter update when a hidden one is up.
    func sync() {
        var needsExclusion = false
        for w in entries.compactMap(\.window) {
            let allowed = !isActive || Self.id(w).map(covered.contains) == true
            let alpha: CGFloat = allowed ? 1 : 0
            if w.alphaValue != alpha { w.alphaValue = alpha }
            if !allowed, w.isVisible { needsExclusion = true }
        }
        if needsExclusion { onNeedsExclusion?() }
    }

    /// Re-checks a few times a second while active: a hidden tag window re-shown by its overlay (or a
    /// filter update that couldn't list it yet) is picked up without waiting for the next `show`.
    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private static func id(_ w: NSWindow) -> CGWindowID? { w.windowNumber > 0 ? CGWindowID(w.windowNumber) : nil }
}

/// The app's tour tag: TourKit's `TagOverlayController`, with its windows registered with
/// `TourTagRecordingGate` the moment they're created, so a tag never shows up in a screen recording.
@MainActor
final class RecordingSafeTagPresenter: TourTagPresenting {
    private let tag = TagOverlayController()
    private let gate: TourTagRecordingGate

    init(gate: TourTagRecordingGate? = nil) {
        self.gate = gate ?? .shared
        self.gate.register(tag.windows)
    }

    var onNext: (() -> Void)? {
        get { tag.onNext }
        set { tag.onNext = newValue }
    }
    var onSkipStep: (() -> Void)? {
        get { tag.onSkipStep }
        set { tag.onSkipStep = newValue }
    }
    var onSkipTour: (() -> Void)? {
        get { tag.onSkipTour }
        set { tag.onSkipTour = newValue }
    }

    func show(step: TourStep, body: String, number: Int, total: Int, anchor: NSView, host: NSWindow) {
        tag.show(step: step, body: body, number: number, total: total, anchor: anchor, host: host)
        gate.sync()   // a first-time window now has a number: get it covered at once
    }

    func showCompleted() { tag.showCompleted() }
    func hide() { tag.hide() }
    func updateProgress(number: Int, total: Int) { tag.updateProgress(number: number, total: total) }
}
