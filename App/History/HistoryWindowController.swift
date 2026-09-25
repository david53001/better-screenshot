import AppKit
import SwiftUI
import HistoryKit
import TourKit

/// Closures the History window needs from the capture layer (annotate/pin
/// reuse CaptureCoordinator's existing flows).
struct HistoryWindowActions {
    var annotate: (CGImage) -> Void
    var pin: (CGImage) -> Void
    var trim: (URL) -> Void
}

/// Owns the single History window — a normal titled window like Settings,
/// hosted via NSHostingController (the SettingsWindowController pattern).
@MainActor
final class HistoryWindowController {
    private var window: NSWindow?
    private let history: HistoryService
    private let actions: HistoryWindowActions

    init(history: HistoryService, actions: HistoryWindowActions) {
        self.history = history
        self.actions = actions
    }

    func show() {
        if window == nil { window = makeWindow() }
        if let window { WindowPlacer.place(window, rememberAs: "history") }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)   // ★ after makeKey, matching SettingsWindowController
        // The History tour's first time (spec §14.3); a no-op unless tours are on.
        if let window { TourEvents.surfaceShown(.history, in: window) }
    }

    /// Builds the window (not shown). Internal so probes can show it behind the owner's windows.
    func makeWindow() -> NSWindow {
        let view = HistoryView(history: history, actions: actions)
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.title = "History"
        w.setContentSize(NSSize(width: 700, height: 500))
        w.isReleasedWhenClosed = false
        InfoButton.install(in: w, tour: .history, shortcuts: Self.infoShortcuts)
        return w
    }

    /// The ⓘ's list: the grid's modifier clicks (History has no plain key shortcuts).
    static let infoShortcuts: [(keys: String, action: String)] = [
        (keys: "⌘-click", action: "Add to or remove from the selection"),
        (keys: "⇧-click", action: "Select everything in between"),
        (keys: "Double-click", action: "Open (screenshots open in the editor)"),
        (keys: "Right-click", action: "More actions"),
    ]
}

struct HistoryView: View {
    @ObservedObject var history: HistoryService
    let actions: HistoryWindowActions
    @State private var selection = HistorySelectionState()
    @State private var confirmingClear = false
    @State private var pendingBulkDelete: [HistoryEntry] = []

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12)]

    var body: some View {
        Group {
            if history.entries.isEmpty {
                let empty = history.emptyState
                ContentUnavailableView(empty.title, systemImage: "photo.on.rectangle.angled",
                                       description: Text(empty.detail))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tourAnchor("history.grid")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(history.entries) { entry in
                            HistoryCell(entry: entry, history: history,
                                        isSelected: selection.selected.contains(entry.id))
                                .overlay(HistoryItemInteraction(
                                    onClick: { modifier, clicks in
                                        handleClick(entry, modifier: modifier, clicks: clicks)
                                    },
                                    dragItems: { dragItems(startingAt: entry) }))
                                .contextMenu { contextItems(for: entry) }
                                // The History tour's "select a capture" steps point at the newest one.
                                .tourAnchor(entry.id == history.entries.first?.id ? "history.item" : "")
                        }
                    }
                    .padding(12)
                }
                .tourAnchor("history.grid")
            }
        }
        // No anchor while History is empty: the tour's "Actions" step would describe a selection that
        // can't exist, over disabled buttons.
        .safeAreaInset(edge: .bottom) { actionBar.tourAnchor(history.entries.isEmpty ? "" : "history.actions") }
        // Wide enough for every action-bar label at its full length (they never truncate).
        .frame(minWidth: Self.minWidth, minHeight: 360)
    }

    static let minWidth: CGFloat = 660

    /// The selected entries, in displayed order.
    private var selectedEntries: [HistoryEntry] {
        history.entries.filter { selection.selected.contains($0.id) }
    }

    /// The single selected entry, when the selection is exactly one.
    private var soleSelection: HistoryEntry? {
        selectedEntries.count == 1 ? selectedEntries[0] : nil
    }

    /// Context-menu and drag target: the whole selection when the clicked entry
    /// is part of it, otherwise just that entry — the Finder convention.
    private func targets(for entry: HistoryEntry) -> [HistoryEntry] {
        selection.selected.contains(entry.id) ? selectedEntries : [entry]
    }

    private func handleClick(_ entry: HistoryEntry, modifier: HistoryClickModifier, clicks: Int) {
        if clicks >= 2 {
            open(entry)
            return
        }
        selection = HistorySelection.click(on: entry.id, modifier: modifier,
                                           order: history.entries.map(\.id), state: selection)
        TourEvents.post(.action("history.selected"))
    }

    /// Evaluated when a drag actually starts: an unselected cell becomes the
    /// selection first, then every selected entry with a file on disk is dragged.
    private func dragItems(startingAt entry: HistoryEntry) -> [HistoryDragItem] {
        let next = HistorySelection.dragStart(on: entry.id,
                                              order: history.entries.map(\.id), state: selection)
        selection = next
        TourEvents.post(.action("history.dragged"))
        return history.entries
            .filter { next.selected.contains($0.id) }
            .compactMap { candidate in
                guard let url = history.dragURL(for: candidate) else { return nil }
                return HistoryDragItem(url: url, image: history.thumbnail(for: candidate))
            }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Text(countLabel)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Group {
                Button("Copy") { history.copyToClipboard(selectedEntries) }
                    .disabled(selectedEntries.isEmpty)
                Button("Annotate") { if let e = soleSelection { annotate(e) } }
                    .disabled(soleSelection?.kind != .screenshot)
                Button("Pin") { if let e = soleSelection { pin(e) } }
                    .disabled(soleSelection?.kind != .screenshot)
                Button("Edit Video…") { if let url = soleSelection.flatMap(trimmableURL) { actions.trim(url) } }
                    .disabled(soleSelection.flatMap(trimmableURL) == nil)
                Button("Show in Finder") { history.revealInFinder(selectedEntries) }
                    .disabled(!selectedEntries.contains { history.canReveal($0) })
                Button("Delete") { delete(selectedEntries) }
                    .disabled(selectedEntries.isEmpty)
            }
            .fixedSize()
            // Wiping the whole history is kept out of the row of everyday actions.
            Menu {
                Button("Clear All History…", role: .destructive) { confirmingClear = true }
                    .disabled(history.entries.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(10)
        .background(.bar)
        .confirmationDialog("Clear all capture history?",
                            isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear All History", role: .destructive) {
                selection = HistorySelectionState()
                history.clearAll()
            }
        } message: {
            Text("Removes every remembered capture and its stored copies. Saved recording files on disk are not deleted.")
        }
        .confirmationDialog("Delete \(pendingBulkDelete.count) captures?",
                            isPresented: Binding(get: { !pendingBulkDelete.isEmpty },
                                                 set: { if !$0 { pendingBulkDelete = [] } }),
                            titleVisibility: .visible) {
            let doomed = pendingBulkDelete
            Button("Delete \(doomed.count) Items", role: .destructive) {
                performDelete(doomed)
                pendingBulkDelete = []
            }
        } message: {
            Text("Removes them from history and deletes their stored copies. Saved recording files on disk are not deleted.")
        }
    }

    /// "12 items" normally; "3 of 12 selected" once more than one is picked.
    private var countLabel: String {
        let total = history.entries.count
        let picked = selectedEntries.count
        if picked > 1 { return "\(picked) of \(total) selected" }
        return "\(total) item\(total == 1 ? "" : "s")"
    }

    @ViewBuilder
    private func contextItems(for entry: HistoryEntry) -> some View {
        let group = targets(for: entry)
        Button(group.count > 1 ? "Copy \(group.count) Items" : "Copy") {
            history.copyToClipboard(targets(for: entry))
        }
        if entry.kind == .screenshot {
            Button("Annotate") { annotate(entry) }
            Button("Pin") { pin(entry) }
        }
        if group.count == 1, let url = trimmableURL(entry) {
            Button("Edit Video…") { actions.trim(url) }
        }
        if group.contains(where: { history.canReveal($0) }) {
            Button("Show in Finder") { history.revealInFinder(targets(for: entry)) }
        }
        Divider()
        Button(group.count > 1 ? "Delete \(group.count) Items" : "Delete", role: .destructive) {
            delete(targets(for: entry))
        }
    }

    /// Double-click: screenshots → editor, recordings → default player.
    private func open(_ entry: HistoryEntry) {
        switch entry.kind {
        case .screenshot: annotate(entry)
        case .recording:
            if let url = history.savedFileURL(for: entry) { NSWorkspace.shared.open(url) }
        }
    }

    /// The saved MP4 behind a recording entry, if it still exists (GIFs can't be trimmed).
    private func trimmableURL(_ entry: HistoryEntry) -> URL? {
        guard entry.kind == .recording, history.savedFileExists(entry),
              let url = history.savedFileURL(for: entry),
              url.pathExtension.lowercased() == "mp4" else { return nil }
        return url
    }

    private func annotate(_ entry: HistoryEntry) {
        guard let image = history.image(for: entry) else { return }
        actions.annotate(image)
    }

    private func pin(_ entry: HistoryEntry) {
        guard let image = history.image(for: entry) else { return }
        actions.pin(image)
    }

    private func delete(_ entries: [HistoryEntry]) {
        guard entries.count > 1 else { performDelete(entries); return }
        pendingBulkDelete = entries
    }

    private func performDelete(_ entries: [HistoryEntry]) {
        let ids = Set(entries.map(\.id))
        selection.selected.subtract(ids)
        if let anchor = selection.anchor, ids.contains(anchor) { selection.anchor = nil }
        history.delete(entries)
    }
}

private struct HistoryCell: View {
    let entry: HistoryEntry
    let history: HistoryService
    let isSelected: Bool
    /// "1600 × 1000" or "0:42", read once the cell appears.
    @State private var detail: String?

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let thumb = history.thumbnail(for: entry) {
                    Image(nsImage: thumb).resizable().scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(Color.gray.opacity(0.12))
            .overlay {
                // Recordings are told apart at a glance, not only by the tiny film icon.
                if entry.kind == .recording {
                    Image(systemName: "play.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.5))
                        .font(.system(size: 30))
                        .shadow(radius: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 4) {
                Image(systemName: entry.kind == .recording ? "film" : "camera")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Self.relative.localizedString(for: entry.date, relativeTo: Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if entry.kind == .recording && !history.savedFileExists(entry) {
                    Label("file missing", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 4)
                if let detail {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .task(id: entry.id) { detail = await history.detail(for: entry) }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
    }
}
