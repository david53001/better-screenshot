import AppKit

/// The Quick Access card's drag source: drags out a file (a temporary PNG for
/// screenshots, the saved file for recordings). The temp file is treated as
/// disposable — the app's temp sweep deletes it once it passes the user's
/// retention window — but it stays alive long enough for targets that read the
/// file lazily (a terminal you drop a path into and submit later, a chat you
/// upload-on-send).
///
/// A plain `NSView`, not an `NSImageView`: on macOS 26 `NSImageView` adds its own
/// aspect-fit image subview on top of every sublayer, which hid the card's
/// aspect-fill picture and its contrast scrim (doubled images on wide/tall
/// captures, illegible buttons on busy ones). `image` is only the drag preview;
/// this view never draws it — the owner puts the visible picture in a sublayer.
public final class DraggableImageView: NSView, NSDraggingSource {
    /// Drag-preview image only; not drawn.
    public var image: NSImage?
    public var fileURLProvider: (() -> URL?)?
    /// Called when a drag finishes. `true` if it was actually dropped somewhere.
    public var onDragEnded: ((Bool) -> Void)?

    private var mouseDownPoint: NSPoint?

    // NSImageView returned false here; a plain NSView returns true, which would let a
    // press on the card start a window drag instead of the file drag.
    public override var mouseDownCanMoveWindow: Bool { false }

    public func draggingSession(_ session: NSDraggingSession,
                                sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation { .copy }

    public override func mouseDown(with event: NSEvent) {
        // Record the start; only begin a drag once the pointer actually moves,
        // so a plain click on the thumbnail doesn't fire a zero-length drag.
        mouseDownPoint = event.locationInWindow
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - down.x, p.y - down.y) >= 4 else { return }
        mouseDownPoint = nil

        guard let url = fileURLProvider?() else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        if let img = image { item.setDraggingFrame(bounds, contents: img) }
        beginDraggingSession(with: [item], event: event, source: self)
    }

    public func draggingSession(_ session: NSDraggingSession,
                                endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let droppedSomewhere = operation != []
        // The dragged file is left on disk for a drop target that reads it lazily (a
        // terminal you paste a path into and submit a while later). The app's temp
        // sweep deletes it once it passes the user's retention window.
        onDragEnded?(droppedSomewhere)
    }
}
