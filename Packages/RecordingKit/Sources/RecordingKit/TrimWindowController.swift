import AppKit
import AVKit
import TourKit

/// The video editor for an MP4 recording (opened from the Quick Access card's ✂ or
/// History's Trim…): a preview over a cut timeline in a dark HUD card, then an action
/// bar. Split at the playhead, delete segments, drag segment edges, per-segment speed
/// and mute, undo / redo; the preview plays only what's kept. Nothing touches the file
/// until an export: Save as Copy ("<name> (trimmed).mp4", closes), Export as GIF
/// ("<name> (edited).gif", stays open) or Replace Original (atomic swap, then reloads
/// the result for review / more edits).
/// Guided tour: the "Video editor" tour (TourKit `VideoEditorTours.swift`) starts once the
/// recording has loaded (`surfaceShown`); anchors `video.*`, events `video.split` /
/// `video.segmentDeleted`; the title bar's ⓘ replays it and lists the keys below.
@MainActor
public final class TrimWindowController: NSWindowController, NSWindowDelegate {
    public private(set) var url: URL
    /// A copy was written (the window has closed).
    public var onSavedCopy: ((URL) -> Void)?
    /// A GIF of the edit was written next to the original (the window stays open).
    public var onExportedGIF: ((URL) -> Void)?
    /// The original file was replaced in place (the window stays open).
    public var onReplaced: ((URL) -> Void)?
    /// Export failed — the message is ready for a HUD / label.
    public var onFailed: ((String) -> Void)?
    /// The window closed (any reason) — release the controller.
    public var onClosed: (() -> Void)?

    // Preview
    private let playerView = PreviewPlayerView()
    private let player = AVPlayer()
    private lazy var seeker = ChaseSeeker(player)
    /// Plain playback of the whole source, shown while an edge is dragged so the
    /// preview follows the handle.
    private var sourceSeeker: ChaseSeeker?
    private var asset: AVURLAsset?
    private var timeObserver: Any?
    private var playingObservation: NSKeyValueObservation?

    // Timeline card
    private let timeline = CutTimelineView()
    private let timelineScroll = TimelineScrollView()
    private let playButton = TrimWindowController.iconButton("play.fill", tip: "Play (Space)", size: 15)
    private let timeLabel = NSTextField(labelWithString: "0:00.0 / 0:00.0")
    private let splitButton = TrimWindowController.textButton("Split", symbol: "scissors",
        tip: "Split the segment at the playhead (S or ⌘B)")
    private let deleteButton = TrimWindowController.textButton("Delete", symbol: "trash",
        tip: "Delete the selected (yellow) segment (⌫)")
    private let undoButton = TrimWindowController.textButton(nil, symbol: "arrow.uturn.backward", tip: "Undo (⌘Z)")
    private let redoButton = TrimWindowController.textButton(nil, symbol: "arrow.uturn.forward", tip: "Redo (⇧⌘Z)")
    private let zoomOutButton = TrimWindowController.iconButton("minus.magnifyingglass",
                                                                tip: "Zoom out the timeline", size: 12)
    private let zoomInButton = TrimWindowController.iconButton("plus.magnifyingglass",
                                                               tip: "Zoom in the timeline", size: 12)
    private let zoomSlider = NSSlider(value: 1, minValue: 1, maxValue: 12, target: nil, action: nil)
    private let segmentTitle = NSTextField(labelWithString: "")
    private let segmentRange = NSTextField(labelWithString: "")
    private let speedLabel = NSTextField(labelWithString: "Speed")
    private let speedControl = NSSegmentedControl(labels: CutList.speeds.map(CutTimelineView.speedLabel),
                                                  trackingMode: .selectOne, target: nil, action: nil)
    private let segmentMuteBox = NSButton(checkboxWithTitle: "Mute segment", target: nil, action: nil)
    private let hintLabel = NSTextField(labelWithString: "")
    /// Export progress: its own slot at the right end of the hint line, so nothing moves.
    private let progressBar = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "")
    private var card: NSView?

    // Error state (the file can't be opened): replaces the preview and the card.
    private let errorView = NSView()
    private let errorTitle = NSTextField(labelWithString: "")
    private let errorMessage = NSTextField(wrappingLabelWithString: "")
    private let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)

    // Action bar
    private let keptLabel = NSTextField(labelWithString: "Loading…")
    private let muteBox = NSButton(checkboxWithTitle: "Mute whole video", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let replaceButton = NSButton(title: "Replace Original", target: nil, action: nil)
    private lazy var copyButton: NSComboButton = {
        let menu = NSMenu()
        let gif = NSMenuItem(title: "Export as GIF", action: #selector(exportGIF), keyEquivalent: "")
        gif.target = self
        gif.toolTip = "Save the edit as an animated GIF next to the original (10 fps, up to 960 px wide)"
        menu.addItem(gif)
        return AnchoredComboButton(title: "Save as Copy", menu: menu, target: self, action: #selector(saveCopy))
    }()

    // Model
    private var history = CutHistory(CutList(duration: 0))
    private var cuts: CutList { history.current }
    /// The working copy while an edge is dragged (committed as one undo step on release).
    private var dragList: CutList?
    private var selected = 0
    private var loaded = false
    private var loadFailed = false
    private var isExporting = false
    /// A new preview is being built — the player's reported times are stale until it lands.
    private var rebuilding = false
    /// Shown instead of the kept-duration label until the next edit.
    private var note: String?
    private var loadTask: Task<Void, Never>?
    private var rebuildTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    /// The tour has been told this window is up (once, after the first successful load).
    private var announcedToTours = false

    /// The ⓘ's Keyboard Shortcuts list (`handleKey` + the buttons' key equivalents).
    static let shortcuts: [(keys: String, action: String)] = [
        ("Space", "Play or pause"),
        ("← →", "Step one frame"),
        ("S or ⌘B", "Split at the playhead"),
        ("⌫", "Delete the selected part"),
        ("I", "Set the in point (cuts what's before)"),
        ("O", "Set the out point (cuts what's after)"),
        ("⌘Z", "Undo"),
        ("⇧⌘Z", "Redo"),
    ]

    public init(url: URL) {
        self.url = url
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 780, height: 560)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.09, alpha: 1)
        super.init(window: window)
        window.delegate = self
        buildUI()
        InfoButton.install(in: window, tour: .videoEditor, shortcuts: Self.shortcuts)
        window.initialFirstResponder = timeline
        load()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildUI() {
        guard let content = window?.contentView else { return }
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.player = player
        playerView.onClick = { [weak self] in self?.togglePlay() }
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.tourAnchor = "video.preview"

        let card = buildCard()
        self.card = card
        let bar = buildActionBar()
        buildErrorView()
        content.addSubview(playerView)
        content.addSubview(card)
        content.addSubview(bar)
        content.addSubview(errorView)
        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: content.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: bar.topAnchor),
            playerView.topAnchor.constraint(equalTo: content.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: card.topAnchor, constant: -12),
            playerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            card.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            card.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -12),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 52),
        ])
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.playerTimeChanged(time.seconds) }
        }
        playingObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshPlayButton() }
        }
    }

    /// The dark HUD card: transport row · timeline · selected-segment row · hint line.
    private func buildCard() -> NSView {
        let card = NSVisualEffectView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.appearance = NSAppearance(named: .vibrantDark)
        card.material = .hudWindow
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor

        // Transport + edit row.
        playButton.target = self; playButton.action = #selector(togglePlay)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.textColor = NSColor(white: 1, alpha: 0.85)
        timeLabel.toolTip = "Playhead / length of the edit"
        timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 116).isActive = true
        splitButton.target = self; splitButton.action = #selector(splitAtPlayhead)
        splitButton.keyEquivalent = "b"; splitButton.keyEquivalentModifierMask = [.command]
        deleteButton.target = self; deleteButton.action = #selector(deleteSelected)
        undoButton.target = self; undoButton.action = #selector(undo)
        undoButton.keyEquivalent = "z"; undoButton.keyEquivalentModifierMask = [.command]
        redoButton.target = self; redoButton.action = #selector(redo)
        redoButton.keyEquivalent = "z"; redoButton.keyEquivalentModifierMask = [.command, .shift]
        zoomSlider.target = self; zoomSlider.action = #selector(zoomChanged)
        zoomSlider.isContinuous = true
        zoomSlider.controlSize = .small
        zoomSlider.toolTip = "Timeline zoom"
        zoomSlider.widthAnchor.constraint(equalToConstant: 110).isActive = true
        zoomOutButton.target = self; zoomOutButton.action = #selector(zoomOut)
        zoomInButton.target = self; zoomInButton.action = #selector(zoomIn)
        let row1 = Self.row([playButton, timeLabel, Self.gap(10), splitButton, deleteButton, Self.divider(),
                             undoButton, redoButton, Self.flexible(), zoomOutButton, zoomSlider, zoomInButton],
                            spacing: 8)

        // Timeline.
        timelineScroll.documentView = timeline
        timelineScroll.drawsBackground = false
        timelineScroll.hasHorizontalScroller = true
        timelineScroll.scrollerStyle = .overlay
        timelineScroll.horizontalScrollElasticity = .none
        timelineScroll.verticalScrollElasticity = .none
        timelineScroll.translatesAutoresizingMaskIntoConstraints = false
        timelineScroll.heightAnchor.constraint(equalToConstant: 74).isActive = true
        // The visible part of the timeline (the document view is wider when zoomed in).
        timelineScroll.tourAnchor = "video.timeline"
        timeline.toolTip = "Click to move the playhead and pick a segment · drag a yellow edge to trim · right-click for speed and mute"
        timeline.onScrub = { [weak self] t in self?.scrub(to: t) }
        timeline.onSelect = { [weak self] i in self?.select(i) }
        timeline.onEdgeDrag = { [weak self] i, edge, t, phase in self?.edgeDrag(i, edge, t, phase) }
        timeline.menuForSegment = { [weak self] i in self?.segmentMenu(i) }

        // Selected segment row.
        segmentTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        segmentTitle.textColor = NSColor(white: 1, alpha: 0.9)
        segmentRange.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        segmentRange.textColor = NSColor(white: 1, alpha: 0.5)
        segmentRange.toolTip = "Where this segment comes from in the original recording"
        speedLabel.font = .systemFont(ofSize: 11)
        speedLabel.textColor = NSColor(white: 1, alpha: 0.6)
        speedControl.controlSize = .small
        speedControl.target = self; speedControl.action = #selector(speedPicked)
        speedControl.toolTip = "Play this segment faster (sped-up segments start muted)"
        for i in 0..<speedControl.segmentCount { speedControl.setWidth(40, forSegment: i) }
        segmentMuteBox.controlSize = .small
        segmentMuteBox.font = .systemFont(ofSize: 11)
        segmentMuteBox.target = self; segmentMuteBox.action = #selector(segmentMuteToggled)
        segmentMuteBox.toolTip = "Silence this segment's audio (the rest keeps its sound)"
        let row2 = Self.row([segmentTitle, segmentRange, Self.gap(14), speedLabel, speedControl, Self.gap(10),
                             segmentMuteBox, Self.flexible()], spacing: 8)
        row2.tourAnchor = "video.segment"

        // Hint line.
        let info = NSImageView(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))!)
        info.contentTintColor = NSColor(white: 1, alpha: 0.45)
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = NSColor(white: 1, alpha: 0.55)
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        progressBar.style = .bar
        progressBar.controlSize = .small
        progressBar.minValue = 0; progressBar.maxValue = 1
        progressBar.widthAnchor.constraint(equalToConstant: 160).isActive = true
        progressBar.isHidden = true
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        progressLabel.textColor = NSColor(white: 1, alpha: 0.6)
        progressLabel.alignment = .right
        progressLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true
        progressLabel.isHidden = true
        let row3 = Self.row([info, hintLabel, Self.flexible(), progressBar, progressLabel], spacing: 6)
        // The bar and its percentage never change the row's height.
        row3.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let stack = NSStackView(views: [row1, timelineScroll, row2, row3])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(8, after: row2)
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        for v in [row1, timelineScroll, row2, row3] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])
        return card
    }

    private func buildActionBar() -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.state = .active
        bar.translatesAutoresizingMaskIntoConstraints = false
        let hairline = NSBox()
        hairline.boxType = .separator
        hairline.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(hairline)

        keptLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        keptLabel.textColor = .secondaryLabelColor
        keptLabel.lineBreakMode = .byTruncatingTail
        keptLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        keptLabel.toolTip = "Length of the saved video / length of the recording"
        muteBox.target = self; muteBox.action = #selector(muteAllToggled)
        muteBox.toolTip = "Save without any sound"
        cancelButton.target = self; cancelButton.action = #selector(cancel)
        cancelButton.bezelStyle = .rounded
        cancelButton.toolTip = "Close without saving"
        copyButton.toolTip = "Save the edit as a new file next to the original — the ▾ menu exports a GIF"
        copyButton.tourAnchor = "video.saveCopy"
        replaceButton.tourAnchor = "video.replace"
        replaceButton.target = self; replaceButton.action = #selector(replaceOriginal)
        replaceButton.bezelStyle = .rounded
        // Accent look without a Return shortcut: replacing the file shouldn't be one
        // stray keypress away.
        replaceButton.bezelColor = .controlAccentColor

        let row = Self.row([keptLabel, Self.gap(4), muteBox, Self.flexible(), cancelButton, copyButton,
                            replaceButton], spacing: 10)
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: bar.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    /// Icon, title, what went wrong and what to do — centred where the preview and the
    /// card would be.
    private func buildErrorView() {
        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle",
                                              accessibilityDescription: "Error")!
            .withSymbolConfiguration(.init(pointSize: 34, weight: .regular))!)
        icon.contentTintColor = NSColor(white: 1, alpha: 0.6)
        errorTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        errorTitle.textColor = .white
        errorTitle.alignment = .center
        errorMessage.font = .systemFont(ofSize: 12)
        errorMessage.textColor = NSColor(white: 1, alpha: 0.6)
        errorMessage.alignment = .center
        errorMessage.preferredMaxLayoutWidth = 400
        revealButton.bezelStyle = .rounded
        revealButton.target = self; revealButton.action = #selector(revealInFinder)
        revealButton.toolTip = "Select the file in a Finder window"
        let stack = NSStackView(views: [icon, errorTitle, errorMessage, revealButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(18, after: errorMessage)
        stack.translatesAutoresizingMaskIntoConstraints = false
        errorView.translatesAutoresizingMaskIntoConstraints = false
        errorView.isHidden = true
        errorView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: errorView.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: errorView.widthAnchor, constant: -48),
            errorMessage.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
        ])
    }

    @objc private func revealInFinder() { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    // MARK: - Loading

    /// (Re)loads `url` — also used after Replace Original, with `noteAfter`.
    private func load(noteAfter: String? = nil) {
        window?.title = "Edit Video — \(url.lastPathComponent)"
        loaded = false; loadFailed = false
        rebuildTask?.cancel(); thumbnailTask?.cancel()
        timeline.resetThumbnails()
        player.replaceCurrentItem(with: nil)
        let asset = AVURLAsset(url: url)
        self.asset = asset
        sourceSeeker = nil
        refreshChrome()
        loadTask = Task { [weak self] in
            do {
                let duration = try await asset.load(.duration).seconds
                guard let track = try await asset.loadTracks(withMediaType: .video).first,
                      duration.isFinite, duration > 0 else { throw TrimExporter.ExportError.noVideoTrack }
                let size = try await track.load(.naturalSize).applying(try await track.load(.preferredTransform))
                guard let self, !Task.isCancelled else { return }
                self.history = CutHistory(CutList(duration: duration))
                self.timeline.aspect = size.height != 0 ? abs(size.width / size.height) : 16 / 10
                self.loaded = true
                self.note = noteAfter.map { "\($0) · \(TrimRange.timestamp(duration))" }
                self.didChangeCuts(select: 0, playhead: 0)
                self.loadThumbnails(asset: asset, duration: duration)
                self.announceToTours()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.loadFailed = true
                self.refreshChrome()
            }
        }
    }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        announceToTours()
    }

    /// Starts the video editor tour (first use / replay) once the window is up *and* the recording
    /// has loaded — never over "Loading…" or the can't-open state. Once per window.
    private func announceToTours() {
        guard loaded, !announcedToTours, let window, window.isVisible else { return }
        announcedToTours = true
        TourEvents.surfaceShown(.videoEditor, in: window)
    }

    /// Filmstrip frames (`FilmstripFrames`: dense enough that fully zoomed-in tiles don't
    /// repeat a frame), loaded in the background, coarse to fine.
    private func loadThumbnails(asset: AVAsset, duration: Double) {
        let screenWidth = (window?.screen ?? NSScreen.main)?.visibleFrame.width ?? 1440
        let count = FilmstripFrames.count(duration: duration,
                                          timelineWidth: screenWidth * CGFloat(zoomSlider.maxValue),
                                          tileWidth: timeline.minimumTileWidth)
        let times = FilmstripFrames.times(duration: duration, count: count)
            .map { CMTime(seconds: $0, preferredTimescale: 600) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Tiles are ≤ 160 × 50 pt; 200 px keeps them sharp at 2× without holding
        // hundreds of large frames.
        generator.maximumSize = CGSize(width: 200, height: 200)
        let tolerance = CMTime(seconds: duration / Double(count) / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        thumbnailTask = Task { [weak self] in
            for await result in generator.images(for: times) {
                guard !Task.isCancelled else { return }
                if case .success(let requested, let image, _) = result {
                    self?.timeline.addThumbnail(time: requested.seconds, image: image)
                }
            }
        }
    }

    // MARK: - Preview

    /// Rebuilds the preview from the current cut list and parks the playhead at `t`.
    private func rebuildPreview(playhead t: Double) {
        guard let asset else { return }
        let cuts = self.cuts
        rebuilding = true
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            do {
                let composition = try await CutComposition.make(asset: asset, cuts: cuts, muteAll: false)
                let video = cuts.segments.contains { $0.speed != 1 }
                    ? try await CutComposition.videoComposition(for: composition, source: asset) : nil
                guard let self, !Task.isCancelled else { return }
                let item = AVPlayerItem(asset: composition)
                item.videoComposition = video
                item.audioTimePitchAlgorithm = .spectral
                self.player.replaceCurrentItem(with: item)
                self.seeker.seek(t)
                self.rebuilding = false
            } catch {
                self?.rebuilding = false
            }
        }
    }

    private func playerTimeChanged(_ t: Double) {
        // Ignore the stale times reported while a seek / rebuild / edge drag is pending.
        guard loaded, t.isFinite, seeker.isIdle, !rebuilding, dragList == nil else { return }
        timeline.playhead = min(max(t, 0), cuts.keptDuration)
        refreshTimeLabel()
        if player.rate != 0 { keepPlayheadVisible() } else { refreshChrome() }
    }

    private func scrub(to t: Double) {
        guard loaded, dragList == nil else { return }
        timeline.playhead = t
        seeker.seek(t)
        refreshTimeLabel()
        refreshChrome()
    }

    @objc private func togglePlay() {
        guard loaded, !isExporting else { return }
        if player.rate != 0 {
            player.pause()
        } else {
            if timeline.playhead >= cuts.keptDuration - 0.05 { timeline.playhead = 0; seeker.seek(0) }
            player.play()
        }
    }

    private func refreshPlayButton() {
        let playing = player.timeControlStatus != .paused
        playButton.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill",
                                   accessibilityDescription: playing ? "Pause" : "Play")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        playButton.toolTip = playing ? "Pause (Space)" : "Play (Space)"
    }

    private func step(_ frames: Int) {
        guard loaded else { return }
        player.pause()
        player.currentItem?.step(byCount: frames)
    }

    private func keepPlayheadVisible() {
        let visible = timelineScroll.contentView.bounds
        let x = timeline.playheadX
        guard x < visible.minX + 8 || x > visible.maxX - 8 else { return }
        let target = min(x - visible.width * 0.15, timeline.bounds.width - visible.width)
        timelineScroll.contentView.scroll(to: NSPoint(x: max(target, 0), y: 0))
        timelineScroll.reflectScrolledClipView(timelineScroll.contentView)
    }

    // MARK: - Edits

    /// Applies one undoable edit; `select` / `playhead` are read from the edited list. False when
    /// nothing changed (beeps).
    @discardableResult
    private func perform(_ edit: (inout CutList) -> Bool, select: (CutList) -> Int,
                         playhead: (CutList) -> Double) -> Bool {
        guard loaded, !isExporting, dragList == nil else { return false }
        guard history.apply(edit) else { NSSound.beep(); return false }
        note = nil
        didChangeCuts(select: select(cuts), playhead: playhead(cuts))
        return true
    }

    private func didChangeCuts(select: Int, playhead: Double) {
        selected = min(max(select, 0), cuts.segments.count - 1)
        timeline.cuts = cuts
        timeline.selected = selected
        let t = min(max(playhead, 0), cuts.keptDuration)
        timeline.playhead = t
        rebuildPreview(playhead: t)
        refreshTimeLabel()
        refreshChrome()
    }

    private var playheadSource: Double { cuts.sourceTime(forOutput: timeline.playhead) }

    @objc private func splitAtPlayhead() {
        let s = playheadSource, t = timeline.playhead
        // The left half stays selected, so "split, move, split, ⌫" removes the middle.
        if perform({ $0.split(atSource: s) },
                   select: { ($0.segmentIndex(containingSource: s) ?? 1) - 1 }, playhead: { _ in t }) {
            TourEvents.post(.action("video.split"))
        }
    }

    @objc private func deleteSelected() {
        let i = selected, start = cuts.outputStart(of: i)
        if perform({ $0.remove(at: i) }, select: { _ in i }, playhead: { _ in start }) {
            TourEvents.post(.action("video.segmentDeleted"))
        }
    }

    private func setIn() {
        let s = playheadSource
        perform({ $0.trimBefore(source: s) }, select: { _ in 0 }, playhead: { _ in 0 })
    }

    private func setOut() {
        let s = playheadSource
        perform({ $0.trimAfter(source: s) }, select: { $0.segments.count - 1 },
                playhead: { $0.keptDuration - 1.0 / 60 })
    }

    private func setSpeed(_ speed: Double, of i: Int) {
        let s = playheadSource
        perform({ $0.setSpeed(speed, of: i) }, select: { _ in i },
                playhead: { $0.outputTime(forSource: s) ?? $0.outputStart(of: i) })
    }

    private func setSegmentMuted(_ muted: Bool, of i: Int) {
        let t = timeline.playhead
        perform({ $0.setMuted(muted, of: i) }, select: { _ in i }, playhead: { _ in t })
    }

    @objc private func undo() { stepHistory { $0.undo() } }
    @objc private func redo() { stepHistory { $0.redo() } }

    private func stepHistory(_ step: (inout CutHistory) -> Bool) {
        guard loaded, !isExporting, dragList == nil else { return }
        let s = playheadSource
        guard step(&history) else { NSSound.beep(); return }
        note = nil
        didChangeCuts(select: selected, playhead: cuts.outputTime(forSource: s) ?? 0)
    }

    private func select(_ i: Int) {
        guard i != selected, cuts.segments.indices.contains(i) else { return }
        selected = i
        timeline.selected = i
        refreshChrome()
    }

    private func edgeDrag(_ i: Int, _ edge: CutTimelineView.Edge, _ t: Double,
                          _ phase: CutTimelineView.DragPhase) {
        guard loaded, !isExporting, cuts.segments.indices.contains(i) else { return }
        if phase == .began {
            player.pause()
            if sourceSeeker == nil, let asset {
                sourceSeeker = ChaseSeeker(AVPlayer(playerItem: AVPlayerItem(asset: asset)))
            }
            playerView.player = sourceSeeker?.player
        }
        var list = cuts
        _ = edge == .start ? list.setStart(t, of: i) : list.setEnd(t, of: i)
        let segment = list.segments[i]
        // The preview shows the first kept frame for a start edge, the last for an end edge.
        sourceSeeker?.seek(edge == .start ? segment.start : max(segment.start, segment.end - 1.0 / 60))
        guard phase == .ended else {
            dragList = list
            timeline.cuts = list
            selected = i; timeline.selected = i
            refreshTimeLabel()
            refreshChrome()
            return
        }
        dragList = nil
        playerView.player = player
        if list != cuts { note = nil }
        history.commit(list)
        let start = list.outputStart(of: i)
        didChangeCuts(select: i, playhead: edge == .start ? start : max(start, start + segment.outputLength - 1.0 / 60))
    }

    // MARK: - Segment controls

    @objc private func speedPicked() {
        guard CutList.speeds.indices.contains(speedControl.selectedSegment) else { return }
        setSpeed(CutList.speeds[speedControl.selectedSegment], of: selected)
    }

    @objc private func segmentMuteToggled() { setSegmentMuted(segmentMuteBox.state == .on, of: selected) }

    @objc private func muteAllToggled() {
        player.isMuted = muteBox.state == .on
        refreshChrome()
    }

    private func segmentMenu(_ i: Int) -> NSMenu? {
        guard loaded, !isExporting, cuts.segments.indices.contains(i) else { return nil }
        let segment = cuts.segments[i]
        let menu = NSMenu()
        menu.autoenablesItems = false
        let speed = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        let speeds = NSMenu()
        for s in CutList.speeds {
            let item = NSMenuItem(title: s == 1 ? "1× (normal)" : CutTimelineView.speedLabel(s),
                                  action: #selector(speedMenuPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s
            item.state = segment.speed == s ? .on : .off
            speeds.addItem(item)
        }
        speed.submenu = speeds
        menu.addItem(speed)
        let mute = NSMenuItem(title: "Mute Segment", action: #selector(segmentMenuMute), keyEquivalent: "")
        mute.target = self
        mute.state = segment.muted ? .on : .off
        mute.isEnabled = muteBox.state == .off
        menu.addItem(mute)
        menu.addItem(.separator())
        let split = NSMenuItem(title: "Split at Playhead", action: #selector(splitAtPlayhead), keyEquivalent: "b")
        split.target = self
        split.isEnabled = splitButton.isEnabled
        menu.addItem(split)
        let delete = NSMenuItem(title: "Delete Segment", action: #selector(deleteSelected),
                                keyEquivalent: "\u{8}")
        delete.keyEquivalentModifierMask = []
        delete.target = self
        delete.isEnabled = cuts.segments.count > 1
        menu.addItem(delete)
        return menu
    }

    @objc private func speedMenuPicked(_ item: NSMenuItem) {
        if let s = item.representedObject as? Double { setSpeed(s, of: selected) }
    }

    @objc private func segmentMenuMute() {
        guard cuts.segments.indices.contains(selected) else { return }
        setSegmentMuted(!cuts.segments[selected].muted, of: selected)
    }

    // MARK: - Zoom

    @objc private func zoomChanged() { applyZoom(zoomSlider.doubleValue) }
    @objc private func zoomOut() { applyZoom(zoomSlider.doubleValue / 1.5) }
    @objc private func zoomIn() { applyZoom(zoomSlider.doubleValue * 1.5) }

    /// Zooms the timeline, keeping the playhead where it is on screen.
    private func applyZoom(_ value: Double) {
        let zoom = min(max(value, zoomSlider.minValue), zoomSlider.maxValue)
        zoomSlider.doubleValue = zoom
        let clip = timelineScroll.contentView
        let onScreen = timeline.playheadX - clip.bounds.minX
        timelineScroll.zoom = CGFloat(zoom)
        let maxX = max(timeline.bounds.width - clip.bounds.width, 0)
        clip.scroll(to: NSPoint(x: min(max(timeline.playheadX - onScreen, 0), maxX), y: 0))
        timelineScroll.reflectScrolledClipView(clip)
        refreshChrome()
    }

    // MARK: - Keyboard

    public override func keyDown(with event: NSEvent) {
        if !handleKey(event) { super.keyDown(with: event) }
    }

    /// Plain-key shortcuts (the ⌘ ones are the buttons' key equivalents).
    private func handleKey(_ event: NSEvent) -> Bool {
        guard loaded, !isExporting else { return false }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        switch event.specialKey {
        case .leftArrow?: step(-1); return true
        case .rightArrow?: step(1); return true
        case .delete?, .deleteForward?: deleteSelected(); return true
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case " ": togglePlay()
        case "s": splitAtPlayhead()
        case "i": setIn()
        case "o": setOut()
        default: return false
        }
        return true
    }

    // MARK: - Chrome

    private func refreshTimeLabel() {
        let list = dragList ?? cuts
        timeLabel.stringValue = "\(TrimRange.timestamp(timeline.playhead)) / \(TrimRange.timestamp(list.keptDuration))"
    }

    private func refreshChrome() {
        let list = dragList ?? cuts
        let ready = loaded && !isExporting
        let s = playheadSource
        let canSplit = list.segments.contains {
            s >= $0.start + CutList.minimumSegment && s <= $0.end - CutList.minimumSegment
        }
        splitButton.isEnabled = ready && canSplit
        deleteButton.isEnabled = ready && list.segments.count > 1
        undoButton.isEnabled = ready && history.canUndo
        redoButton.isEnabled = ready && history.canRedo
        playButton.isEnabled = ready
        zoomSlider.isEnabled = loaded
        zoomOutButton.isEnabled = loaded && zoomSlider.doubleValue > zoomSlider.minValue
        zoomInButton.isEnabled = loaded && zoomSlider.doubleValue < zoomSlider.maxValue
        // Borderless icons keep their tint when disabled — dim them by hand.
        for b in [playButton, zoomOutButton, zoomInButton] {
            b.contentTintColor = NSColor(white: 1, alpha: b.isEnabled ? 0.85 : 0.3)
        }
        speedControl.isEnabled = ready
        segmentMuteBox.isEnabled = ready && muteBox.state == .off
        muteBox.isEnabled = ready
        copyButton.isEnabled = ready
        // Nothing to replace until the video differs from the file (e.g. right after
        // Replace Original, which reloads the result).
        let edited = cuts != CutList(duration: cuts.duration) || muteBox.state == .on
        replaceButton.isEnabled = ready && edited
        replaceButton.toolTip = edited || !loaded ? "Overwrite the original recording with the edit"
            : "Make an edit first — the original already matches this video"
        cancelButton.isEnabled = !isExporting

        errorView.isHidden = !loadFailed
        playerView.isHidden = loadFailed
        card?.isHidden = loadFailed
        if loadFailed {
            let missing = !FileManager.default.fileExists(atPath: url.path)
            errorTitle.stringValue = missing ? "This recording can't be found" : "This video can't be opened"
            errorMessage.stringValue = missing
                ? "It may have been moved, renamed or deleted. Close this window, then open the recording again from its new place."
                : "The file may be damaged or still being saved. Close this window and try again in a moment, or check the file in Finder."
            revealButton.isHidden = missing
            cancelButton.title = "Close"
            cancelButton.toolTip = "Close the editor"
        }

        if list.segments.indices.contains(selected) {
            let segment = list.segments[selected]
            segmentTitle.stringValue = "Segment \(selected + 1) of \(list.segments.count)"
            segmentRange.stringValue = "\(TrimRange.timestamp(segment.start)) – \(TrimRange.timestamp(segment.end))"
            speedControl.selectedSegment = CutList.speeds.firstIndex(of: segment.speed) ?? 0
            segmentMuteBox.state = segment.muted || muteBox.state == .on ? .on : .off
        }
        hintLabel.stringValue = hint(for: list)

        if loadFailed {
            keptLabel.stringValue = ""
        } else if !loaded {
            keptLabel.stringValue = "Loading…"
        } else if let note {
            keptLabel.stringValue = note
        } else if list == CutList(duration: list.duration) {
            keptLabel.stringValue = "Whole recording · \(TrimRange.timestamp(list.duration))"
        } else {
            keptLabel.stringValue = "\(TrimRange.timestamp(list.keptDuration)) kept of \(TrimRange.timestamp(list.duration))"
        }
    }

    private func hint(for list: CutList) -> String {
        if isExporting { return "Exporting — the original stays untouched until it's done." }
        if muteBox.state == .on { return "Mute whole video is on: the saved video will have no sound at all." }
        if list.segments.indices.contains(selected) {
            let segment = list.segments[selected]
            if segment.speed != 1 && segment.muted {
                return "Sped-up segments are muted so the audio doesn't sound rushed — untick Mute segment to keep it."
            }
            if segment.speed != 1 { return "Sped-up audio keeps its pitch but plays faster." }
        }
        if list.segments.count == 1 {
            return "Move the playhead, then press S (or ⌘B) to split · drag the yellow edges to trim · I / O set in / out"
        }
        return "Click a segment to select it · ⌫ deletes it · right-click for speed and mute · Space plays the edit"
    }

    // MARK: - Export

    @objc private func cancel() { close() }

    @objc private func saveCopy() {
        let (url, cuts, muted) = (self.url, self.cuts, muteBox.state == .on)
        runExport(determinate: TrimExporter.needsReencode(cuts),
                  failure: "Couldn't export the edit — original untouched") {
            try await TrimExporter.exportCopy(source: url, cuts: cuts, muted: muted, progress: $0)
        } done: { [weak self] copy in
            self?.onSavedCopy?(copy)
            self?.close()
        }
    }

    @objc private func replaceOriginal() {
        let (url, cuts, muted) = (self.url, self.cuts, muteBox.state == .on)
        runExport(determinate: TrimExporter.needsReencode(cuts),
                  failure: "Couldn't export the edit — original untouched") {
            try await TrimExporter.replaceOriginal(source: url, cuts: cuts, muted: muted, progress: $0)
            return url
        } done: { [weak self] url in
            guard let self else { return }
            // Back to plain playback of the result, ready for more edits.
            self.muteBox.state = .off
            self.player.isMuted = false
            self.cancelButton.title = "Done"
            self.cancelButton.toolTip = "Close the editor"
            self.load(noteAfter: "Edited ✓ original replaced")
            self.onReplaced?(url)
        }
    }

    @objc private func exportGIF() {
        let (url, cuts) = (self.url, self.cuts)
        runExport(determinate: true, failure: "Couldn't export the GIF — nothing was changed") {
            try await TrimExporter.exportGIF(source: url, cuts: cuts, progress: $0)
        } done: { [weak self] gif in
            self?.note = "GIF saved ✓ \(gif.lastPathComponent)"
            self?.refreshChrome()
            self?.onExportedGIF?(gif)
        }
    }

    private func runExport(determinate: Bool, failure: String,
                           _ work: @escaping (@escaping TrimExporter.Progress) async throws -> URL,
                           done: @escaping (URL) -> Void) {
        guard loaded, !isExporting else { return }
        isExporting = true
        player.pause()
        progressBar.isIndeterminate = !determinate
        progressBar.doubleValue = 0
        progressBar.isHidden = false
        progressLabel.isHidden = !determinate
        progressLabel.stringValue = "0%"
        if !determinate { progressBar.startAnimation(nil) }
        refreshChrome()
        let progress: TrimExporter.Progress = { [weak self] p in
            Task { @MainActor [weak self] in
                guard let self, self.isExporting, determinate else { return }
                self.progressBar.doubleValue = p
                self.progressLabel.stringValue = "\(Int((p * 100).rounded()))%"
            }
        }
        Task { @MainActor in
            do {
                let result = try await work(progress)
                finishExport()
                done(result)
            } catch {
                finishExport()
                note = failure
                refreshChrome()
                onFailed?(failure)
            }
        }
    }

    private func finishExport() {
        isExporting = false
        progressBar.stopAnimation(nil)
        progressBar.isHidden = true
        progressLabel.isHidden = true
        refreshChrome()
    }

    // MARK: - NSWindowDelegate

    public func windowShouldClose(_ sender: NSWindow) -> Bool { !isExporting }

    public func windowWillClose(_ notification: Notification) {
        loadTask?.cancel(); rebuildTask?.cancel(); thumbnailTask?.cancel()
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        playingObservation = nil
        playerView.player = nil
        sourceSeeker?.player.pause()
        onClosed?()
    }

    // MARK: - Control factories

    private static func iconButton(_ symbol: String, tip: String, size: CGFloat) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!
                            .withSymbolConfiguration(.init(pointSize: size, weight: .semibold))!,
                         target: nil, action: nil)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.contentTintColor = NSColor(white: 1, alpha: 0.85)
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        b.widthAnchor.constraint(equalToConstant: size + 14).isActive = true
        return b
    }

    /// A rounded push button: icon + short title, or icon only when `title` is nil.
    private static func textButton(_ title: String?, symbol: String, tip: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title ?? tip)!
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))!
        let b = title.map { NSButton(title: $0, image: image, target: nil, action: nil) }
            ?? NSButton(image: image, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.imagePosition = title == nil ? .imageOnly : .imageLeading
        b.imageHugsTitle = true
        b.toolTip = tip
        b.setAccessibilityLabel(title ?? tip)
        return b
    }

    private static func row(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private static func gap(_ width: CGFloat) -> NSView {
        let v = NSView()
        v.widthAnchor.constraint(equalToConstant: width).isActive = true
        return v
    }

    private static func flexible() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        v.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return v
    }

    private static func divider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor
        NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant: 1),
                                     v.heightAnchor.constraint(equalToConstant: 18)])
        return v
    }
}

/// NSComboButton ignores `setAccessibilityIdentifier` (it reads back ""), and that's where a tour
/// anchor lives (`tourAnchor`) — so this one keeps it itself. Otherwise a plain NSComboButton.
private final class AnchoredComboButton: NSComboButton {
    private var anchorID = ""
    override func accessibilityIdentifier() -> String { anchorID }
    override func setAccessibilityIdentifier(_ id: String?) { anchorID = id ?? "" }
}

/// The preview: no AVKit controls; a click toggles play / pause.
final class PreviewPlayerView: AVPlayerView {
    var onClick: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override var acceptsFirstResponder: Bool { false }
}

/// Keeps the timeline document as wide as the visible area × `zoom`.
final class TimelineScrollView: NSScrollView {
    var zoom: CGFloat = 1 { didSet { tile() } }
    override func tile() {
        super.tile()
        guard let doc = documentView else { return }
        let size = NSSize(width: max(contentSize.width, (contentSize.width * zoom).rounded()),
                          height: contentSize.height)
        if doc.frame.size != size { doc.setFrameSize(size) }
    }
}

/// Seeks a player frame-exactly without piling up stale seeks: while one runs, only
/// the latest requested time is kept (smooth scrubbing).
@MainActor
final class ChaseSeeker {
    let player: AVPlayer
    private var pending: CMTime?
    private var busy = false
    var isIdle: Bool { !busy && pending == nil }

    init(_ player: AVPlayer) { self.player = player }

    func seek(_ seconds: Double) {
        pending = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        if !busy { next() }
    }

    private func next() {
        guard let time = pending else { busy = false; return }
        pending = nil
        busy = true
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.next() } }
        }
    }
}
