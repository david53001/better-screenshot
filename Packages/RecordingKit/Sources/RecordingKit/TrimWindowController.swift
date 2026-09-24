import AppKit
import AVKit

/// The recording trim window: an AVPlayerView in AVKit's native trim mode
/// (QuickTime-style yellow handles) over an action bar — range label · Mute audio ·
/// Adjust Trim · Cancel · Save as Copy · Replace Original.
///
/// AVKit's own Trim button only *records* the range; nothing touches the file until
/// Save as Copy (writes "<name> (trimmed).mp4" and closes) or Replace Original (swaps
/// the file in place and reloads the player so the result can be reviewed or trimmed again).
@MainActor
public final class TrimWindowController: NSWindowController, NSWindowDelegate {
    public private(set) var url: URL
    /// A copy was written (the window has closed).
    public var onSavedCopy: ((URL) -> Void)?
    /// The original file was replaced in place (the window stays open).
    public var onReplaced: ((URL) -> Void)?
    /// Export failed — the message is ready for a HUD / label.
    public var onFailed: ((String) -> Void)?
    /// The window closed (any reason) — release the controller.
    public var onClosed: (() -> Void)?

    private let playerView = AVPlayerView()
    private let rangeLabel = NSTextField(labelWithString: "")
    private let muteBox = NSButton(checkboxWithTitle: "Mute audio", target: nil, action: nil)
    private let adjustButton = NSButton(title: "Adjust Trim", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let copyButton = NSButton(title: "Save as Copy", target: nil, action: nil)
    private let replaceButton = NSButton(title: "Replace Original", target: nil, action: nil)
    private let spinner = NSProgressIndicator()

    private var duration: Double = 0
    private var range: TrimRange?
    private var isTrimming = false
    private var isExporting = false
    private var canTrim = false
    /// Enter AVKit trim mode as soon as the item is ready (off after Replace Original,
    /// which lands on plain playback of the result).
    private var trimWhenReady = true
    /// Shown instead of "Whole recording" once the original has been replaced.
    private var replacedNote = false
    private var statusObservation: NSKeyValueObservation?

    public init(url: URL) {
        self.url = url
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        load()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildUI() {
        guard let content = window?.contentView else { return }
        playerView.controlsStyle = .inline
        playerView.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSVisualEffectView()
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.translatesAutoresizingMaskIntoConstraints = false

        rangeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        rangeLabel.textColor = .secondaryLabelColor
        rangeLabel.lineBreakMode = .byTruncatingTail
        rangeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        adjustButton.target = self; adjustButton.action = #selector(adjustTrim)
        adjustButton.bezelStyle = .rounded
        cancelButton.target = self; cancelButton.action = #selector(cancel)
        cancelButton.bezelStyle = .rounded
        copyButton.target = self; copyButton.action = #selector(saveCopy)
        copyButton.bezelStyle = .rounded
        replaceButton.target = self; replaceButton.action = #selector(replaceOriginal)
        replaceButton.bezelStyle = .rounded
        // Accent look without a Return shortcut: AVKit's trim mode uses Return/Esc,
        // and replacing the file shouldn't be one stray keypress away.
        replaceButton.bezelColor = .controlAccentColor
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [rangeLabel, muteBox, spacer, spinner, adjustButton,
                                      cancelButton, copyButton, replaceButton])
        row.orientation = .horizontal
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(row)

        content.addSubview(playerView)
        content.addSubview(bar)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: content.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 52),
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
    }

    // MARK: - Player

    /// (Re)loads `url` into a fresh player — also used after Replace Original.
    private func load() {
        window?.title = "Trim — \(url.lastPathComponent)"
        range = nil
        canTrim = false
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        playerView.player = AVPlayer(playerItem: item)
        refreshChrome()
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in self?.itemStatusChanged(item) }
        }
    }

    private func itemStatusChanged(_ item: AVPlayerItem) {
        guard item === playerView.player?.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            statusObservation = nil
            duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
            canTrim = playerView.canBeginTrimming
            refreshChrome()
            if canTrim && trimWhenReady { beginTrimming() }
        case .failed:
            statusObservation = nil
            canTrim = false
            refreshChrome()
            rangeLabel.stringValue = "This recording can't be opened for trimming."
        default:
            break
        }
    }

    private func beginTrimming() {
        guard canTrim, !isTrimming else { return }
        isTrimming = true
        refreshChrome()
        playerView.beginTrimming { [weak self] result in
            Task { @MainActor in self?.trimmingEnded(result) }
        }
    }

    private func trimmingEnded(_ result: AVPlayerViewTrimResult) {
        isTrimming = false
        if result == .okButton, let item = playerView.player?.currentItem {
            // AVKit reports the handles as the item's playback end times (invalid = untouched end).
            let s = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime.seconds : 0
            let e = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime.seconds : duration
            let r = TrimRange.clamped(start: s, end: e, duration: duration)
            range = r.isNoOp(duration: duration) ? nil : r
        }
        refreshChrome()
    }

    private func refreshChrome() {
        let busy = isExporting || isTrimming
        adjustButton.isEnabled = canTrim && !busy
        copyButton.isEnabled = canTrim && !busy
        replaceButton.isEnabled = canTrim && !busy
        muteBox.isEnabled = canTrim && !isExporting
        cancelButton.isEnabled = !isExporting
        if isExporting { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        guard canTrim else { rangeLabel.stringValue = duration > 0 ? "This recording can't be trimmed." : "Loading…"; return }
        if isTrimming {
            rangeLabel.stringValue = "Drag the yellow handles, then press Trim"
        } else if let range {
            rangeLabel.stringValue = range.label(duration: duration)
        } else if replacedNote {
            rangeLabel.stringValue = "Trimmed ✓ original replaced · \(TrimRange.timestamp(duration))"
        } else {
            rangeLabel.stringValue = "Whole recording · \(TrimRange.timestamp(duration))"
        }
    }

    // MARK: - Actions

    @objc private func adjustTrim() {
        replacedNote = false
        beginTrimming()
    }

    @objc private func cancel() { close() }

    @objc private func saveCopy() {
        let muted = muteBox.state == .on
        export { [url, range, duration] in
            try await TrimExporter.exportCopy(source: url, cuts: range.map { CutList(range: $0, duration: duration) } ?? CutList(duration: duration), muted: muted)
        } done: { [weak self] newURL in
            self?.onSavedCopy?(newURL)
            self?.close()
        }
    }

    @objc private func replaceOriginal() {
        let muted = muteBox.state == .on
        export { [url, range, duration] in
            try await TrimExporter.replaceOriginal(source: url, cuts: range.map { CutList(range: $0, duration: duration) } ?? CutList(duration: duration), muted: muted)
            return url
        } done: { [weak self] url in
            guard let self else { return }
            // Back to plain playback of the trimmed file; Adjust Trim trims it again.
            self.muteBox.state = .off
            self.trimWhenReady = false
            self.replacedNote = true
            self.cancelButton.title = "Done"
            self.load()
            self.onReplaced?(url)
        }
    }

    private func export(_ work: @escaping () async throws -> URL, done: @escaping (URL) -> Void) {
        guard !isExporting else { return }
        isExporting = true
        playerView.player?.pause()
        refreshChrome()
        Task { @MainActor in
            do {
                let result = try await work()
                isExporting = false
                refreshChrome()
                done(result)
            } catch {
                isExporting = false
                refreshChrome()
                let message = "Couldn't export trimmed recording — original untouched"
                rangeLabel.stringValue = message
                onFailed?(message)
            }
        }
    }

    // MARK: - NSWindowDelegate

    public func windowShouldClose(_ sender: NSWindow) -> Bool { !isExporting }

    public func windowWillClose(_ notification: Notification) {
        playerView.player?.pause()
        playerView.player = nil
        onClosed?()
    }
}
