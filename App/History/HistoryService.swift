import AppKit
import ImageIO
import CaptureKit
import HistoryKit
import OverlayKit

/// App-side façade over HistoryKit: owns the store and the restore LIFO,
/// applies the settings toggle/cap, and publishes entries for the History
/// window. PNG encoding reuses CaptureKit's ImageEncoder so HistoryKit stays
/// dependency-free.
@MainActor
final class HistoryService: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let store: HistoryStore
    private var restoreStack = RestoreStack()
    private let settings: SettingsStore
    private let hud = HUDController()

    init(settings: SettingsStore) {
        self.settings = settings
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
            .appendingPathComponent("BetterScreenshot/History", isDirectory: true)
        self.store = HistoryStore(directory: base, cap: settings.settings.historyCap)
        self.entries = store.index.entries
    }

    // MARK: - Recording captures (silent bookkeeping; never blocks the flow)

    /// Adds a screenshot (every after-capture mode, including copy-only).
    /// Returns the entry id for restore tracking, or nil when history is off
    /// or the write failed.
    @discardableResult
    func recordScreenshot(_ image: CGImage) -> UUID? {
        guard settings.settings.historyEnabled else { return nil }
        guard let png = ImageEncoder.encode(image, as: .png) else { return nil }
        let entry = store.addScreenshot(pngData: png, cap: settings.settings.historyCap)
        entries = store.index.entries
        return entry?.id
    }

    /// Adds a finished recording (reference + thumbnail, no video copy).
    @discardableResult
    func recordRecording(fileURL: URL, thumbnailSource: NSImage) -> UUID? {
        guard settings.settings.historyEnabled else { return nil }
        guard let tiff = thumbnailSource.tiffRepresentation else { return nil }
        let entry = store.addRecording(filePath: fileURL.path, thumbnailSource: tiff,
                                       cap: settings.settings.historyCap)
        entries = store.index.entries
        return entry?.id
    }

    // MARK: - Restore Recently Closed

    /// Track a ✕-closed or evicted overlay for restore.
    func noteOverlayClosed(historyID: UUID?) {
        guard let historyID else { return }
        restoreStack.push(historyID)
    }

    var canRestore: Bool { !restoreStack.isEmpty }

    /// Pops the newest restorable entry still present in history.
    func popRestorable() -> HistoryEntry? {
        while let id = restoreStack.pop() {
            if let entry = store.entry(id: id) { return entry }
        }
        return nil
    }

    // MARK: - History window actions

    func delete(_ entries: [HistoryEntry]) {
        for entry in entries { store.remove(id: entry.id) }
        self.entries = store.index.entries
    }

    func clearAll() {
        store.clearAll()
        entries = store.index.entries
    }

    func thumbnail(for entry: HistoryEntry) -> NSImage? {
        NSImage(contentsOf: store.thumbURL(for: entry))
    }

    // MARK: - Cell details + empty state

    /// Cached per entry: the grid recreates cells as it scrolls.
    private var detailCache: [UUID: String] = [:]

    /// "1600 × 1000" for a screenshot (PNG header only), "0:42" for a recording.
    /// nil when the file is missing or unreadable (not cached, so it can recover).
    func detail(for entry: HistoryEntry) async -> String? {
        if let cached = detailCache[entry.id] { return cached }
        let text: String?
        switch entry.kind {
        case .screenshot:
            text = store.imageURL(for: entry).flatMap(Self.pixelSizeText)
        case .recording:
            guard let url = savedFileURL(for: entry), savedFileExists(entry) else { return nil }
            text = await MediaDuration.seconds(of: url).flatMap(MediaInfoText.duration)
        }
        if let text { detailCache[entry.id] = text }
        return text
    }

    private static func pixelSizeText(_ url: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return MediaInfoText.pixelSize(width: w, height: h)
    }

    /// What the window shows with no entries (uses the live Capture Area shortcut).
    var emptyState: HistoryEmptyState.Message {
        HistoryEmptyState.message(historyEnabled: settings.settings.historyEnabled,
                                  captureShortcut: settings.bindings.combo(for: .captureArea)?.displayString)
    }

    /// Full-resolution stored screenshot (nil for recordings).
    func image(for entry: HistoryEntry) -> CGImage? {
        guard let url = store.imageURL(for: entry),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    func savedFileURL(for entry: HistoryEntry) -> URL? { store.savedFileURL(for: entry) }
    func savedFileExists(_ entry: HistoryEntry) -> Bool { store.savedFileExists(entry) }

    /// The file to put on the pasteboard when this entry is dragged out:
    /// the history-owned PNG for screenshots, the user's saved file for
    /// recordings. Nil when the file is missing, so it is simply skipped.
    func dragURL(for entry: HistoryEntry) -> URL? {
        var url: URL?
        switch entry.kind {
        case .screenshot: url = store.imageURL(for: entry)
        case .recording:  url = store.savedFileURL(for: entry)
        }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Copy: image for screenshots, file URL for recordings. HUD confirms.
    func copyToClipboard(_ entry: HistoryEntry) {
        switch entry.kind {
        case .screenshot:
            guard let cg = image(for: entry) else { return }
            let rep = NSBitmapImageRep(cgImage: cg)
            let img = NSImage(); img.addRepresentation(rep)
            NSPasteboard.general.clearContents()
            // Image data first, plus the persistent stored PNG's file URL so
            // pasting into a terminal/Claude Code inserts a usable path.
            var objects: [NSPasteboardWriting] = [img]
            if let url = store.imageURL(for: entry) { objects.append(url as NSURL) }
            NSPasteboard.general.writeObjects(objects)
            hud.show("Copied", symbol: "doc.on.doc")
        case .recording:
            guard let url = savedFileURL(for: entry) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
            hud.show("File copied", symbol: "doc.on.doc")
        }
    }

    /// Multi-selection copy. One entry keeps the rich single-item behaviour
    /// (image data + file URL); several write file URLs, which is what Finder,
    /// Mail and chat apps accept for a multi-file paste.
    func copyToClipboard(_ entries: [HistoryEntry]) {
        guard entries.count != 1 else { copyToClipboard(entries[0]); return }
        let urls = entries.compactMap { dragURL(for: $0) }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
        hud.show("\(urls.count) files copied", symbol: "doc.on.doc")
    }

    /// Show in Finder targets the saved recording file, or the history-owned
    /// screenshot copy.
    func canReveal(_ entry: HistoryEntry) -> Bool {
        guard let url = revealURL(for: entry) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Reveals every selected file in one Finder window.
    func revealInFinder(_ entries: [HistoryEntry]) {
        let urls = entries.compactMap { revealURL(for: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func revealURL(for entry: HistoryEntry) -> URL? {
        store.savedFileURL(for: entry) ?? store.imageURL(for: entry)
    }
}
