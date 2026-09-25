import AppKit
import ScreenCaptureKit
import CaptureKit
import OverlayKit
import EditorKit

@MainActor
final class CaptureCoordinator {
    private let service = CaptureService()
    private let settings: SettingsStore
    private let overlay = SelectionOverlayController()
    // Shared with RecordingCoordinator so screenshot and recording overlays
    // stack together at the corner instead of overlapping.
    private let quickAccess: QuickAccessStackController
    private let hud = HUDController()
    private let pins = PinPanelController()

    /// Filled in by Plan 3 to present the annotation editor. Nil = stub.
    var editorPresenter: ((CGImage) -> Void)?

    /// Set by the app delegate; presents the one-button permission setup window.
    var presentSetup: (() -> Void)?

    /// Set by the app delegate; nil until then (history silently skipped).
    var history: HistoryService?

    private var editorController: EditorWindowController?

    /// The last app that was frontmost before one of our overlays took focus,
    /// so focus can be handed back after a capture. Outlives a single capture
    /// on purpose — see `rememberFrontmostApp()`.
    private var previousApp: NSRunningApplication?

    func presentEditor(_ image: CGImage) {
        let controller = EditorWindowController(image: image, defaultStyle: settings.editorStyle,
                                                recentColors: settings.editorRecentColors)
        controller.onCopy = { [weak self] img in self?.copy(img) }
        controller.onSave = { [weak self] img in self?.save(img) }
        controller.onAddToStack = { [weak self] img in self?.keepInStack(img) }
        controller.onStyleChanged = { [weak self] style in
            self?.settings.editorStyle = style
            self?.settings.persistEditorStyle()
        }
        controller.onRecentColorsChanged = { [weak self] colors in
            self?.settings.editorRecentColors = colors
            self?.settings.persistEditorRecentColors()
        }
        editorController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Drops an edited image into the bottom-right Quick Access stack, treating
    /// it like a fresh capture: it is recorded to history and shown with the
    /// normal Copy/Edit/Pin/Save/drag actions.
    func keepInStack(_ image: CGImage) {
        let historyID = history?.recordScreenshot(image)
        presentOverlay(image, sourceRect: nil, historyID: historyID)
    }

    init(settings: SettingsStore, quickAccess: QuickAccessStackController) {
        self.settings = settings
        self.quickAccess = quickAccess
    }

    func captureArea() {
        rememberFrontmostApp()
        guard ensurePermission() else { return }
        overlay.present { [weak self] result in
            guard let self else { return }
            guard let result else { self.restoreFrontmostApp(); return }
            Task { await self.run(.area(rect: result.globalRect, displayID: result.displayID),
                                  sourceRect: result.globalRect) }
        }
    }

    func captureFullscreen() {
        rememberFrontmostApp()
        guard ensurePermission() else { return }
        Task { await run(.fullscreen(displayID: CGMainDisplayID())) }
    }

    func captureFrontWindow() {
        rememberFrontmostApp()
        guard ensurePermission() else { return }
        Task { if let id = await frontmostWindowID() { await run(.window(windowID: id)) } }
    }

    /// Capture Text (OCR + QR): drag a region; the recognized text — or a QR
    /// code's payload, which wins — lands on the clipboard. HUD confirms.
    func captureText() {
        rememberFrontmostApp()
        guard ensurePermission() else { return }
        // Load Vision's text model while the user drags — cold start is 0.5–1s.
        Task.detached(priority: .userInitiated) { TextRecognizer.warmUp() }
        overlay.present { [weak self] result in
            guard let self else { return }
            guard let result else { self.restoreFrontmostApp(); return }
            Task { await self.runCaptureText(result) }
        }
    }

    private func runCaptureText(_ result: SelectionResult) async {
        do {
            let image = try await service.capture(
                .area(rect: result.globalRect, displayID: result.displayID))
            // Vision's perform() blocks — keep it off the main actor.
            let pointWidth = result.globalRect.width
            let recognition = try await Task.detached {
                try TextRecognizer.recognize(in: image, pointWidth: pointWidth)
            }.value
            if let payload = recognition.clipboardString {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(payload, forType: .string)
            }
            hud.show(recognition.hudMessage, symbol: "text.viewfinder", on: screen(for: result.displayID))
        } catch {
            NSLog("Capture Text failed: \(error)")
            hud.show("Capture Text failed", symbol: "exclamationmark.triangle", on: screen(for: result.displayID))
        }
        // Focus goes back last, so the recognized text can be pasted straight
        // into the app the user was already in.
        restoreFrontmostApp()
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        } ?? NSScreen.main
    }

    private func run(_ target: CaptureTarget, sourceRect: CGRect? = nil) async {
        do {
            let image = try await service.capture(target)
            handle(image, sourceRect: sourceRect)
        } catch {
            NSLog("Capture failed: \(error)")
            hud.show("Capture failed", symbol: "exclamationmark.triangle")
            restoreFrontmostApp()
        }
    }

    private func handle(_ image: CGImage, sourceRect: CGRect?) {
        // Silent bookkeeping first, so even copy-only captures are recoverable.
        let historyID = history?.recordScreenshot(image)
        if settings.settings.playSound { CaptureSound.play() }
        switch settings.settings.afterCapture {
        case .copyOnly:    copy(image)
        case .saveOnly:    save(image)
        case .copyAndSave: copy(image); save(image)
        case .showOverlay: presentOverlay(image, sourceRect: sourceRect, historyID: historyID)
        }
        // The Quick Access card is a .nonactivatingPanel, so handing focus back
        // here leaves it on screen and clickable.
        restoreFrontmostApp()
    }

    private func presentOverlay(_ image: CGImage, sourceRect: CGRect?, historyID: UUID?) {
        let nsImage = NSImage(cgImage: image,
                              size: NSSize(width: image.width, height: image.height))
        guard let screen = NSScreen.main else { copy(image); save(image); return }
        let actions = QuickAccessActions(
            onCopy: { [weak self] in self?.copy(image); self?.hud.show("Copied", symbol: "doc.on.doc") },
            // The overlay's download button always lands in the macOS screenshot folder.
            onSave: { [weak self] in self?.save(image, to: SettingsStore.systemScreenshotLocation()) },
            onAnnotate: { [weak self] in self?.annotate(image) },
            fileURLForDrag: { TempImageWriter.writePNG(image, fileName: FileNamer.fileName(for: Date(), ext: "png")) })
        let corner = settings.settings.overlayCorner
        // visibleFrame excludes the Dock and menu bar, so the overlay sits above
        // the Dock instead of being tucked into the very bottom corner behind it.
        let frame = screen.visibleFrame
        quickAccess.present(image: nsImage, actions: actions,
                            autoDismissSeconds: settings.settings.overlayAutoDismissSeconds,
                            corner: corner, screenFrame: frame, margin: 24,
                            onDismissed: { [weak self] reason in
            // ✕-close and eviction are "accidental" — deliberate actions aren't restorable.
            if reason == .closed || reason == .evicted {
                self?.history?.noteOverlayClosed(historyID: historyID)
            }
        })
    }

    /// Re-presents a Quick Access card for a history entry (Restore Recently Closed).
    func presentOverlayFromHistory(_ image: CGImage, historyID: UUID) {
        presentOverlay(image, sourceRect: nil, historyID: historyID)
    }

    /// Plan 3 replaces the stub body via `editorPresenter`.
    func annotate(_ image: CGImage) {
        if let present = editorPresenter { present(image) }
        else { NSLog("Annotate requested — editor arrives in Plan 3") }
    }

    /// Pins the image as a floating panel — at its original on-screen location
    /// when known, else centered on the main screen.
    func pin(_ image: CGImage, near sourceRect: CGRect? = nil) {
        guard image.width > 0, image.height > 0 else { return }
        let screen = sourceRect.flatMap { r in NSScreen.screens.first { $0.frame.intersects(r) } }
            ?? NSScreen.main
        guard let screen else { return }
        let nsImage = NSImage(cgImage: image,
                              size: NSSize(width: image.width, height: image.height))
        let style = PinStyle(cornerRadius: CGFloat(settings.settings.pinCornerRadius),
                             shadow: settings.settings.pinShadow)
        let actions = PinActions(
            onCopy: { [weak self] in
                self?.copy(image)
                // Re-resolve at click time: the original display may be gone.
                let liveScreen = NSScreen.screens.first { $0 === screen } ?? NSScreen.main
                self?.hud.show("Copied", symbol: "doc.on.doc", on: liveScreen)
            },
            onSave: { [weak self] in self?.save(image) })
        pins.pin(image: nsImage,
                 pixelSize: CGSize(width: image.width, height: image.height),
                 sourceRect: sourceRect, on: screen, style: style, actions: actions)
    }

    func pinFromClipboard() {
        guard let ns = NSPasteboard.general.readObjects(forClasses: [NSImage.self],
                                                        options: nil)?.first as? NSImage,
              let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            hud.show("No image on clipboard", symbol: "exclamationmark.triangle", on: NSScreen.main)
            return
        }
        pin(cg)
    }

    var clipboardHasImage: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    private func copy(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        let nsImage = NSImage(); nsImage.addRepresentation(rep)
        NSPasteboard.general.clearContents()
        // Image data first (so image-targets paste the picture), plus a real PNG
        // file so file-targets — a terminal/Claude Code you paste into — get a
        // usable path. TempFileService sweeps the file once it passes the
        // "Keep cached files for" window.
        var objects: [NSPasteboardWriting] = [nsImage]
        if let url = TempImageWriter.writePNG(image,
                                              fileName: FileNamer.fileName(for: Date(), ext: "png")) {
            objects.append(url as NSURL)
        }
        NSPasteboard.general.writeObjects(objects)
    }

    private func save(_ image: CGImage, to directory: URL? = nil) {
        let dir = directory ?? settings.saveDirectory
        let isPNG = settings.settings.format == .png
        let format: ImageFormat = isPNG ? .png : .jpg(quality: 0.9)
        guard let data = ImageEncoder.encode(image, as: format) else {
            hud.show("Couldn't save — image encoding failed", symbol: "exclamationmark.triangle")
            return
        }
        let name = FileNamer.fileName(for: Date(), ext: isPNG ? "png" : "jpg")
        do {
            // The chosen folder may have been deleted/renamed since it was set.
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent(name))
        } catch {
            NSLog("Save failed: \(error)")
            hud.show("Couldn't save screenshot", symbol: "exclamationmark.triangle")
        }
    }

    private func ensurePermission() -> Bool {
        if PermissionManager.hasScreenRecordingPermission { return true }
        presentSetup?()   // one-button setup window owns the whole grant flow
        return false
    }

    /// Remembers who had focus before the selection overlay activates us.
    /// Recording ourselves is skipped two different ways: while our own
    /// overlay is already up (a second capture hotkey — keep the real target),
    /// and when the capture was started from one of our own windows, where
    /// there is nothing to hand focus back to.
    private func rememberFrontmostApp() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        guard front.bundleIdentifier != Bundle.main.bundleIdentifier else {
            if !overlay.isPresenting { previousApp = nil }
            return
        }
        previousApp = front
    }

    /// Hands focus back to that app. The remembered app is deliberately *not*
    /// cleared: re-activating an already-active app is a no-op, and keeping it
    /// means a second capture hotkey pressed while our own selection overlay
    /// is already up still has somewhere to return to.
    private func restoreFrontmostApp() {
        guard let app = previousApp else { return }
        guard FocusRestore.shouldRestore(previousBundleID: app.bundleIdentifier,
                                         ownBundleID: Bundle.main.bundleIdentifier) else { return }
        app.activate()
    }

    private func frontmostWindowID() async -> CGWindowID? {
        let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        return content?.windows.first(where: { $0.isOnScreen && $0.title?.isEmpty == false })?.windowID
    }
}
