import AppKit
import AVFoundation
import ScreenCaptureKit
import CaptureKit
import OverlayKit
import RecordingKit

/// Orchestrates the recording lifecycle: strip → engine + panels → save/convert.
@MainActor
final class RecordingCoordinator {
    private let settings: SettingsStore
    private let recorder = ScreenRecorder()
    private let strip: RecordStripController
    private let selection = SelectionOverlayController()
    private let bubble = CameraBubbleController()
    private let clicks = ClickHighlighter()
    private let keystrokes = KeystrokeOverlayController()
    private let countdown = CountdownOverlayController()
    private let windowPicker = WindowPickerController()
    private let hud = HUDController()
    private let controls = RecordingControlsController()
    // Shared with CaptureCoordinator: finished recordings join the same
    // bottom-corner thumbnail stack that screenshots use.
    private let quickAccess: QuickAccessStackController
    private var state = RecorderState.idle
    private var timer: Timer?
    private var isTerminating = false
    private var tempOutputURL: URL?
    /// The open trim window, if any (one at a time).
    private var trimController: TrimWindowController?
    // Live pill state for the current session (reset in arm()).
    private var micMuted = false
    private var soundMuted = false
    private var hasCamera = false
    /// A Switch window/area picker is up.
    private var switching = false
    /// What's being recorded and on which screen — updated by Switch, reused by Restart.
    private var activeTarget: (target: RecordingTarget, screen: NSScreen)?

    /// Set by the app delegate; presents the one-button permission setup window.
    var presentSetup: (() -> Void)?
    /// Menu-bar state: (recording?, elapsed string). Called on every change/tick.
    var onStateChange: ((Bool, String?) -> Void)?
    /// Drives the Pause/Resume menu item: (session active?, currently paused?).
    var onPauseStateChange: ((_ active: Bool, _ paused: Bool) -> Void)?
    /// Set by the app delegate; nil until then (history silently skipped).
    var history: HistoryService?

    init(settings: SettingsStore, quickAccess: QuickAccessStackController) {
        self.settings = settings
        self.quickAccess = quickAccess
        self.strip = RecordStripController(store: settings)
        strip.onFullScreen = { [weak self] in self?.beginFullScreen() }
        strip.onArea = { [weak self] in self?.beginAreaSelection() }
        strip.onWindow = { [weak self] in self?.beginWindowSelection() }
        strip.onCancel = { [weak self] in self?.cancelStrip() }
        controls.onStop = { [weak self] in self?.stopFromControls() }
        controls.onPauseResume = { [weak self] in self?.pauseResume() }
        controls.onToggleMic = { [weak self] in self?.toggleMicMute() }
        controls.onToggleSound = { [weak self] in self?.toggleSoundMute() }
        controls.onToggleCamera = { [weak self] in self?.toggleCamera() }
        controls.onSwitch = { [weak self] in self?.switchTarget() }
        controls.onRestart = { [weak self] in Task { await self?.restart() } }
        controls.onDiscard = { [weak self] in Task { await self?.discard() } }
        recorder.onStreamError = { [weak self] _ in
            Task { @MainActor in self?.streamFailed() }
        }
    }

    /// True while a capture session exists (recording OR paused) — keeps the
    /// menu-bar stop icon + timer visible through a pause.
    var isRecording: Bool {
        switch state { case .recording, .paused: return true; default: return false }
    }
    var isPaused: Bool { if case .paused = state { return true }; return false }

    /// The smart ⌘⇧5 entry point: idle → strip · armed → cancel · recording/paused → stop.
    func toggle() {
        switch state {
        case .idle: arm()
        case .armed: cancelStrip()
        case .recording, .paused: Task { await stop() }
        case .finishing: break   // busy — ignore
        }
    }

    /// Pause/resume the running recording. No-op outside `.recording`/`.paused`.
    func pauseResume() {
        switch state {
        case .recording:
            guard state.transition(.pause(Date())) else { return }
            recorder.pause()
            notify()
        case .paused:
            guard state.transition(.resume(Date())) else { return }
            recorder.resume()
            notify()
        default:
            break
        }
    }

    /// The floating pill's Stop: cancels during the countdown, stops once recording.
    private func stopFromControls() {
        switch state {
        case .armed: cancelStrip()
        case .recording, .paused: Task { await stop() }
        default: break
        }
    }

    private func arm() {
        guard PermissionManager.hasScreenRecordingPermission else {
            presentSetup?()
            return
        }
        guard state.transition(.arm) else { return }
        micMuted = false; soundMuted = false; switching = false
        recorder.setMicMuted(false); recorder.setSystemAudioMuted(false)
        hasCamera = AVCaptureDevice.default(for: .video) != nil
        let screen = NSScreen.screens.first {
            $0.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main
        if let screen { strip.show(on: screen) }
    }

    private func cancelStrip() {
        // ⌘⇧5 while the area-selection overlay / countdown is up: tear it down too.
        selection.cancel()
        countdown.cancel()
        windowPicker.cancel()
        controls.hide()
        strip.hide()
        state.transition(.reset)
    }

    private func beginFullScreen() {
        guard let screen = stripScreen() else { return }
        strip.hide()
        Task { await begin(target: .display(globalRect: nil), screen: screen) }
    }

    private func beginAreaSelection() {
        strip.hide()
        selection.present { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                guard let result,
                      let screen = NSScreen.screens.first(where: {
                          $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                              as? CGDirectDisplayID == result.displayID
                      }) else {
                    self.state.transition(.reset)
                    return
                }
                await self.begin(target: .display(globalRect: result.globalRect), screen: screen)
            }
        }
    }

    private func beginWindowSelection() {
        strip.hide()
        presentWindowPicker { [weak self] picked in
            guard let self else { return }
            guard let picked else { self.state.transition(.reset); self.notify(); return }
            let center = CGPoint(x: picked.frame.midX, y: picked.frame.midY)
            let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
            guard let screen else { self.state.transition(.reset); self.notify(); return }
            Task { await self.begin(target: .window(picked.id), screen: screen) }
        }
    }

    /// The hover-to-highlight window picker over every on-screen window except
    /// our own; `onPicked(nil)` = cancelled.
    private func presentWindowPicker(onPicked: @escaping (PickableWindow?) -> Void) {
        // CGWindowList bounds are top-left global; convert with the primary
        // display height (the screen whose origin is (0,0)).
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero }
                             ?? NSScreen.main)?.frame.height ?? 0
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let info = (CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let windows: [PickableWindow] = info.compactMap { dict in
            guard let id = dict[kCGWindowNumber as String] as? UInt32,
                  let layer = dict[kCGWindowLayer as String] as? Int,
                  let pidInt = dict[kCGWindowOwnerPID as String] as? Int,
                  let boundsValue = dict[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary)
            else { return nil }
            let title = dict[kCGWindowName as String] as? String
            return PickableWindow(id: id,
                                  frame: WindowPicking.cocoaFrame(fromTopLeft: bounds,
                                                                  primaryHeight: primaryHeight),
                                  title: title, layer: layer, ownerPID: pid_t(pidInt))
        }
        windowPicker.present(hitTest: { point in
            guard let w = WindowPicking.topmost(at: point, windows: windows,
                                                excludingPID: ownPID) else { return nil }
            return (id: w.id, frame: w.frame, title: w.title)
        }, onPicked: { id in
            onPicked(id.flatMap { id in windows.first { $0.id == id } })
        })
    }

    private func stripScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    private enum RecordingTarget {
        case display(globalRect: CGRect?)   // nil = full screen
        case window(CGWindowID)
    }

    /// Start the engine for `target` on `screen`. Single path for full-screen,
    /// area, and window recording.
    private func begin(target: RecordingTarget, screen: NSScreen) async {
        // A ⌘⇧5 cancel can land while the selection overlay or permission prompts
        // were up — only proceed if we're still armed.
        guard case .armed = state else { return }
        activeTarget = (target, screen)
        var config = settings.recording
        // GIFs are silent: don't open the mic (or ask for it) for a track that's thrown away.
        if config.format == .gif { config.microphone = false; config.systemAudio = false }
        // Shown before the content query so the pill is a known SCWindow we can exclude.
        controls.show(on: screen)
        notify()
        do {
            let content = try await shareableContent(containing: config.controlsInRecording
                                                     ? nil : controls.windowID)
            let scale = screen.backingScaleFactor
            let filter: SCContentFilter
            var sourceRect: CGRect?
            var pixelSize: CGSize
            let cameraAnchor: CGRect
            var systemAudioFilter: SCContentFilter?
            switch target {
            case .display(let globalRect):
                guard let displayID = screen.deviceDescription[
                        NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                      let display = content.displays.first(where: { $0.displayID == displayID })
                else { throw RecorderError.writerFailed }
                pixelSize = CGSize(width: CGFloat(display.width) * scale,
                                   height: CGFloat(display.height) * scale)
                if let globalRect {
                    // sourceRect: display-relative, top-left origin, points.
                    let local = CaptureGeometry.pixelRect(forGlobalRect: globalRect,
                                                          inDisplayFrame: screen.frame, scale: 1)
                    sourceRect = local
                    pixelSize = CGSize(width: local.width * scale, height: local.height * scale)
                }
                let hidden = config.controlsInRecording ? [] : content.windows.filter {
                    $0.windowID == controls.windowID
                }
                filter = SCContentFilter(display: display, excludingWindows: hidden)
                cameraAnchor = globalRect ?? screen.frame
            case .window(let windowID):
                guard let window = content.windows.first(where: { $0.windowID == windowID })
                else { throw RecorderError.writerFailed }
                pixelSize = CGSize(width: window.frame.width * scale,
                                   height: window.frame.height * scale)
                filter = SCContentFilter(desktopIndependentWindow: window)
                cameraAnchor = screen.frame   // camera bubble is screen-level (v1)
                // A window filter only hears that window's own process; take system
                // audio from the whole display so "All apps" means all apps.
                if config.systemAudio, let display = content.displays.first(where: {
                    $0.displayID == screen.deviceDescription[
                        NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                }) ?? content.displays.first {
                    systemAudioFilter = SCContentFilter(display: display, excludingWindows: [])
                }
            }

            // Even pixel dimensions keep H.264 encoders happy.
            pixelSize.width = (pixelSize.width / 2).rounded(.down) * 2
            pixelSize.height = (pixelSize.height / 2).rounded(.down) * 2

            if config.microphone, await MicCapturer.ensurePermission() == false {
                config.microphone = false
                hud.show("Mic access denied — recording without microphone", on: screen)
            }
            if config.camera, await CameraBubbleController.ensurePermission() {
                bubble.show(near: cameraAnchor, on: screen, diameter: config.cameraSize.diameter,
                            deviceID: config.cameraDeviceID)
            }
            if config.clickHighlights { clicks.start(on: screen) }
            if config.keystrokeOverlay { keystrokes.start(on: screen) }

            if config.countdownSeconds > 0 {
                await countdown.run(seconds: config.countdownSeconds, on: screen)
                // ⌘⇧5 during the countdown cancels (cancelStrip → reset). If we're
                // no longer armed, tear the panels back down and bail.
                guard case .armed = state else { tearDownPanels(); notify(); return }
            }

            let ext = "mp4"   // GIF converts after the fact
            let name = FileNamer.fileName(for: Date(), ext: ext, prefix: "Recording")
            let url = config.format == .gif
                ? FileManager.default.temporaryDirectory.appendingPathComponent(name)
                : settings.saveDirectory.appendingPathComponent(name)
            tempOutputURL = config.format == .gif ? url : nil

            // The chosen folder may have been deleted/renamed since it was set.
            try FileManager.default.createDirectory(at: settings.saveDirectory,
                                                    withIntermediateDirectories: true)
            try await recorder.start(filter: filter, pixelSize: pixelSize,
                                     sourceRect: sourceRect, config: config, outputURL: url,
                                     systemAudioFilter: systemAudioFilter)
            guard state.transition(.begin(Date())) else {
                // Cancelled (⌘⇧5) during engine startup: stop and discard.
                _ = try? await recorder.stop()
                try? FileManager.default.removeItem(at: url)
                tearDownPanels()
                notify()
                return
            }
            startTimer()
            notify()
        } catch {
            tearDownPanels()
            state.transition(.reset)
            hud.show("Couldn't start recording", on: screen)
            notify()
        }
    }

    private func stop() async {
        guard state.transition(.finish) else { return }
        controls.hide()
        stopTimer()
        notify()
        let config = settings.recording
        // GIF exports and MP4 fallbacks land in the save folder — make sure it exists.
        try? FileManager.default.createDirectory(at: settings.saveDirectory,
                                                 withIntermediateDirectories: true)
        do {
            let mp4 = try await recorder.stop()
            tearDownPanels()
            if config.format == .gif, !isTerminating {
                hud.show("Converting to GIF…")
                let gifName = FileNamer.fileName(for: Date(), ext: "gif", prefix: "Recording")
                let gifURL = settings.saveDirectory.appendingPathComponent(gifName)
                do {
                    try await GIFExporter.export(mp4: mp4, to: gifURL)
                    try? FileManager.default.removeItem(at: mp4)
                    await finishRecording(at: gifURL)
                } catch {
                    // Keep the MP4 so the recording isn't lost.
                    let mp4Name = FileNamer.fileName(for: Date(), ext: "mp4", prefix: "Recording")
                    let dest = settings.saveDirectory.appendingPathComponent(mp4Name)
                    try? FileManager.default.moveItem(at: mp4, to: dest)
                    await finishRecording(at: dest, showCard: false)
                    hud.show("Saved as MP4 (GIF conversion failed)")
                }
            } else if config.format == .gif {
                // Quitting: no time for conversion — keep the MP4 so nothing is lost.
                let mp4Name = FileNamer.fileName(for: Date(), ext: "mp4", prefix: "Recording")
                let dest = settings.saveDirectory.appendingPathComponent(mp4Name)
                try? FileManager.default.moveItem(at: mp4, to: dest)
                await finishRecording(at: dest, showCard: false)
            } else {
                await finishRecording(at: mp4, showCard: !isTerminating)
            }
        } catch {
            if let tempOutputURL { try? FileManager.default.removeItem(at: tempOutputURL) }
            tearDownPanels()
            hud.show("Recording failed")
        }
        state.transition(.reset)
        tempOutputURL = nil
        notify()
    }

    /// Best-effort stop for app termination. Spins the main run loop (instead of
    /// blocking on a semaphore, which would deadlock the MainActor task) so the
    /// async finalize can complete before the process exits.
    func stopForTermination() {
        guard isRecording else { return }
        isTerminating = true
        var done = false
        Task { @MainActor in
            await self.stop()
            done = true
        }
        let deadline = Date().addingTimeInterval(3)
        while !done && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private func streamFailed() {
        guard isRecording else { return }
        Task { await stop() }
    }

    private func tearDownPanels() {
        windowPicker.cancel()
        if switching { selection.cancel() }   // a Switch area… selection, not the start one
        controls.hide()
        bubble.hide()
        clicks.stop()
        keystrokes.stop()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.notify() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func notify() {
        onStateChange?(isRecording, state.elapsedString(now: Date()))
        onPauseStateChange?(isRecording, isPaused)
        controls.update(pillStatus())
    }

    // MARK: - Live pill (mute · camera · switch · restart · discard)

    private static let noMicTip = "Mic wasn't on when this recording started — there's no mic track to mute"
    private static let noSoundTip =
        "System audio wasn't on when this recording started — there's no system audio track to mute"
    private static let gifTip = "GIFs have no sound — there's no audio track to mute"

    private func pillStatus() -> RecordingControlsController.Status {
        let running = isRecording
        let rec = settings.recording
        // Audio tracks are fixed when the engine starts; during the countdown,
        // show what it's about to record (mic permission was settled by then).
        // GIFs record no audio at all (begin() drops both sources).
        let isGIF = rec.format == .gif
        let hasMic = running ? recorder.recordsMicrophone
            : !isGIF && rec.microphone && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let hasSound = running ? recorder.recordsSystemAudio : !isGIF && rec.systemAudio
        var s = RecordingControlsController.Status(elapsed: state.elapsedString(now: Date()),
                                                   paused: isPaused, running: running)
        s.mic = hasMic ? (micMuted ? .off : .on) : .unavailable(isGIF ? Self.gifTip : Self.noMicTip)
        s.sound = hasSound ? (soundMuted ? .off : .on) : .unavailable(isGIF ? Self.gifTip : Self.noSoundTip)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            s.camera = .unavailable("Camera access is off — allow BetterScreenshot in System Settings › "
                                    + "Privacy & Security › Camera")
        default:
            s.camera = !hasCamera ? .unavailable("No camera found") : bubble.isVisible ? .on : .off
        }
        switch activeTarget?.target {
        case .window: s.switchKind = .window
        case .display(let rect): s.switchKind = rect == nil ? nil : .area   // full screen: nothing to switch
        case nil: s.switchKind = nil
        }
        return s
    }

    /// Mute keeps the track and writes silence (ScreenRecorder + SilenceFill).
    private func toggleMicMute() {
        micMuted.toggle()
        recorder.setMicMuted(micMuted)
        notify()
    }

    private func toggleSoundMute() {
        soundMuted.toggle()
        recorder.setSystemAudioMuted(soundMuted)
        notify()
    }

    /// Hides/re-shows the bubble in place, or shows it for the first time even if
    /// the camera was off at start (it's recorded simply by being on screen).
    private func toggleCamera() {
        if bubble.exists {
            bubble.setHidden(bubble.isVisible)
            notify()
            return
        }
        guard let active = activeTarget else { return }
        Task {
            guard await CameraBubbleController.ensurePermission(), !bubble.exists,
                  activeTarget != nil else { notify(); return }
            let anchor: CGRect
            if case .display(let rect?) = active.target { anchor = rect } else { anchor = active.screen.frame }
            bubble.show(near: anchor, on: active.screen, diameter: settings.recording.cameraSize.diameter,
                        deviceID: settings.recording.cameraDeviceID)
            notify()
        }
    }

    /// Switch window… / Switch area…: pauses (so the picker overlay isn't
    /// recorded), reuses the start pickers, retargets the live stream, resumes.
    private func switchTarget() {
        guard isRecording, !switching, let active = activeTarget else { return }
        if case .display(nil) = active.target { return }
        let previousApp = NSWorkspace.shared.frontmostApplication
        let pausedForSwitch = !isPaused
        if pausedForSwitch { pauseResume() }
        switching = true
        // The pickers activate us to receive Escape; hand focus back afterwards.
        let finish = { [weak self] (app: NSRunningApplication?) in
            guard let self else { return }
            self.switching = false
            if pausedForSwitch, self.isPaused { self.pauseResume() }
            (app ?? previousApp)?.activate()
            self.notify()
        }
        switch active.target {
        case .window:
            presentWindowPicker { [weak self] picked in
                guard let self, let picked else { finish(nil); return }
                Task {
                    await self.retarget(toWindow: picked)
                    finish(NSRunningApplication(processIdentifier: picked.ownerPID))
                }
            }
        case .display:
            selection.present { [weak self] result in
                Task { @MainActor in
                    if let self, let result { await self.retarget(toArea: result) }
                    finish(nil)
                }
            }
        }
    }

    private func retarget(toWindow picked: PickableWindow) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == picked.id }),
                  let current = activeTarget else { throw RecorderError.notRecording }
            try await recorder.retarget(filter: SCContentFilter(desktopIndependentWindow: window),
                                        sourceRect: nil)
            let center = CGPoint(x: picked.frame.midX, y: picked.frame.midY)
            activeTarget = (.window(picked.id),
                            NSScreen.screens.first { $0.frame.contains(center) } ?? current.screen)
        } catch {
            hud.show("Couldn't switch — still recording the previous window", on: activeTarget?.screen)
        }
    }

    private func retarget(toArea result: SelectionResult) async {
        let config = settings.recording
        do {
            guard let screen = NSScreen.screens.first(where: {
                      $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                          as? CGDirectDisplayID == result.displayID }) else { throw RecorderError.notRecording }
            let content = try await shareableContent(containing: config.controlsInRecording
                                                     ? nil : controls.windowID)
            guard let display = content.displays.first(where: { $0.displayID == result.displayID })
            else { throw RecorderError.notRecording }
            // Same filter shape as begin(): the pill stays out of the video.
            let hidden = config.controlsInRecording ? [] : content.windows.filter {
                $0.windowID == controls.windowID
            }
            let local = CaptureGeometry.pixelRect(forGlobalRect: result.globalRect,
                                                  inDisplayFrame: screen.frame, scale: 1)
            try await recorder.retarget(filter: SCContentFilter(display: display, excludingWindows: hidden),
                                        sourceRect: local)
            activeTarget = (.display(globalRect: result.globalRect), screen)
        } catch {
            hud.show("Couldn't switch — still recording the previous area", on: activeTarget?.screen)
        }
    }

    /// Restart: throw away what's recorded so far and start again on the same
    /// target with the same settings (countdown included). The pill, camera
    /// bubble and overlays stay up; mute states carry over.
    private func restart() async {
        guard isRecording, let active = activeTarget, state.transition(.finish) else { return }
        stopTimer()
        let url = recorder.currentOutputURL
        _ = try? await recorder.stop()
        if let url { try? FileManager.default.removeItem(at: url) }
        tempOutputURL = nil
        state.transition(.reset)
        state.transition(.arm)
        notify()
        await begin(target: active.target, screen: active.screen)
    }

    /// Discard: stop and delete the file — no card, no history entry.
    private func discard() async {
        guard state.transition(.finish) else { return }
        let url = recorder.currentOutputURL
        controls.hide()
        stopTimer()
        notify()
        _ = try? await recorder.stop()
        if let url { try? FileManager.default.removeItem(at: url) }
        tearDownPanels()
        state.transition(.reset)
        tempOutputURL = nil
        hud.show("Recording discarded", on: activeTarget?.screen ?? NSScreen.main)
        notify()
    }

    /// On-screen shareable content. A just-ordered-in panel can take a moment to
    /// reach the window server's list, so when `windowID` must be present (to be
    /// excluded) retry briefly before giving up and recording without the exclusion.
    private func shareableContent(containing windowID: CGWindowID?) async throws -> SCShareableContent {
        var content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let windowID else { return content }
        for _ in 0..<5 where !content.windows.contains(where: { $0.windowID == windowID }) {
            try await Task.sleep(nanoseconds: 50_000_000)
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
        return content
    }

    /// Post-save tail for every finished recording: add it to capture history,
    /// then show the bottom-corner thumbnail card (suppressed while quitting
    /// and on GIF-fallback saves, which keep their explanatory HUD). Falls
    /// back to a HUD when no frame could be extracted (e.g. zero-length file).
    private func finishRecording(at url: URL, showCard: Bool = true) async {
        guard let image = await Self.thumbnail(for: url) else {
            if showCard { hud.show("Recording saved") }
            return
        }
        let historyID = history?.recordRecording(fileURL: url, thumbnailSource: image)
        if showCard { presentCard(for: url, image: image, historyID: historyID) }
    }

    /// Opens the trim window for an MP4 recording (Quick Access card or History).
    /// `restoreCard` runs once when the window closes, for any reason — the card path
    /// passes one that brings back the Quick Access card the ✂ button dismissed
    /// (History passes nil). Save as Copy still shows the copy's own card as well.
    func presentTrim(url: URL, restoreCard: (() -> Void)? = nil) {
        if let open = trimController {
            if open.url == url {
                // Another card for the same file was dismissed: bring it back too.
                if let restoreCard {
                    let previous = open.onClosed
                    open.onClosed = { previous?(); restoreCard() }
                }
                open.showWindow(nil); NSApp.activate(ignoringOtherApps: true); return
            }
            open.close()
        }
        let c = TrimWindowController(url: url)
        c.onSavedCopy = { [weak self] copy in
            Task { await self?.finishRecording(at: copy) }
        }
        c.onExportedGIF = { [weak self] gif in
            Task { await self?.finishRecording(at: gif) }
        }
        c.onReplaced = { [weak self] _ in self?.hud.show("Recording edited") }
        c.onFailed = { [weak self] message in self?.hud.show(message) }
        c.onClosed = { [weak self, weak c] in
            if self?.trimController === c { self?.trimController = nil }
            restoreCard?()
        }
        trimController = c
        if let window = c.window { WindowPlacer.place(window, rememberAs: "editVideo") }
        c.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Re-presents a card for a history entry (Restore Recently Closed).
    func presentCardFromHistory(url: URL, image: NSImage, historyID: UUID) {
        presentCard(for: url, image: image, historyID: historyID)
    }

    private func presentCard(for url: URL, image: NSImage, historyID: UUID?) {
        guard let screen = NSScreen.main else { return }
        let actions = QuickAccessActions(
            onCopy: { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
                self?.hud.show("File copied", symbol: "doc.on.doc")
            },
            onOpen: { NSWorkspace.shared.open(url) },
            onReveal: { NSWorkspace.shared.activateFileViewerSelecting([url]) },
            fileURLForDrag: { url },
            onTrim: url.pathExtension.lowercased() == "mp4"
                ? { [weak self] in
                    self?.presentTrim(url: url, restoreCard: { [weak self] in
                        self?.bringBackCard(for: url, historyID: historyID)
                    })
                } : nil)
        let corner = settings.settings.overlayCorner
        // visibleFrame excludes the Dock and menu bar, so the overlay sits above
        // the Dock instead of being tucked into the very bottom corner behind it.
        let frame = screen.visibleFrame
        Task { [weak self] in
            // "0:42 · MP4" badge, so a recording card doesn't look like a screenshot's.
            let badge = MediaInfoText.recordingBadge(seconds: await MediaDuration.seconds(of: url),
                                                     fileExtension: url.pathExtension)
            guard let self else { return }
            self.quickAccess.present(image: image, kind: .recording, actions: actions,
                                     autoDismissSeconds: self.settings.settings.overlayAutoDismissSeconds,
                                     corner: corner, screenFrame: frame, margin: 24, badge: badge,
                                     onDismissed: { [weak self] reason in
                if reason == .closed || reason == .evicted {
                    self?.history?.noteOverlayClosed(historyID: historyID)
                }
            })
        }
    }

    /// Re-presents the card the trim window replaced, with a fresh thumbnail — after
    /// Replace Original that's the trimmed file's first frame. Skipped if the file is gone.
    private func bringBackCard(for url: URL, historyID: UUID?) {
        Task { [weak self] in
            guard let image = await Self.thumbnail(for: url) else { return }
            self?.presentCard(for: url, image: image, historyID: historyID)
        }
    }

    /// First frame of the saved recording (GIFs decode directly; MP4s via
    /// AVAssetImageGenerator).
    private static func thumbnail(for url: URL) async -> NSImage? {
        if url.pathExtension.lowercased() == "gif" { return NSImage(contentsOf: url) }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        guard let cg = try? await generator.image(at: .zero).image else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
