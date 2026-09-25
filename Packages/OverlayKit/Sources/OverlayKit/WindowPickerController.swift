import AppKit

/// A full-screen overlay (per display) that highlights the window under the
/// cursor and confirms a pick on click. Generic: it knows nothing about
/// CaptureKit — the caller injects a hit-test closure (global Cocoa point in →
/// hovered window id + global Cocoa frame + title out) and a pick handler.
/// Mirrors SelectionOverlayController's per-screen overlay + Esc handling and
/// QuickAccessStackController's injected-closure pattern.
public final class WindowPickerController {
    public typealias HitTest = (CGPoint) -> (id: UInt32, frame: CGRect, title: String?)?

    private var windows: [NSWindow] = []
    private var hitTest: HitTest?
    private var onPicked: ((UInt32?) -> Void)?

    public init() {}

    /// Present the picker on all screens. `onPicked(nil)` means cancelled (Esc /
    /// click on no window).
    public func present(hitTest: @escaping HitTest, onPicked: @escaping (UInt32?) -> Void) {
        if self.onPicked != nil { tearDown(); self.onPicked = nil; self.hitTest = nil } // re-entry guard
        self.hitTest = hitTest
        self.onPicked = onPicked
        for screen in NSScreen.screens {
            let view = WindowPickerView(frame: screen.frame, screenOrigin: screen.frame.origin)
            view.hitTest = hitTest
            view.onPick = { [weak self] id in self?.finish(id: id) }
            view.onCancel = { [weak self] in self?.finish(id: nil) }
            let window = KeyableOverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                                              backing: .buffered, defer: false, screen: screen)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)   // borderless: needed to receive Escape
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Dismiss an in-flight picker without firing `onPicked` (the caller's cancel
    /// path already handles state). No-op when nothing is presented.
    public func cancel() {
        guard onPicked != nil else { return }
        onPicked = nil
        hitTest = nil
        tearDown()
    }

    private func finish(id: UInt32?) {
        guard let cb = onPicked else { return }
        onPicked = nil
        hitTest = nil
        tearDown()
        cb(id)
    }

    private func tearDown() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

/// Draws the dim + hovered-window highlight for one screen.
private final class WindowPickerView: NSView {
    var hitTest: WindowPickerController.HitTest?
    var onPick: ((UInt32?) -> Void)?
    var onCancel: (() -> Void)?

    private let screenOrigin: CGPoint
    private var current: (id: UInt32, frame: CGRect, title: String?)?

    init(frame: NSRect, screenOrigin: CGPoint) {
        self.screenOrigin = screenOrigin
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let hovered = hitTest?(NSEvent.mouseLocation) ?? nil
        if hovered?.id != current?.id { current = hovered; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        if current != nil { current = nil; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) { onPick?(current?.id) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }   // Escape
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        bounds.fill()
        guard let current else { return }
        // Global Cocoa frame → this screen's view-local coordinates.
        let local = CGRect(x: current.frame.minX - screenOrigin.x,
                           y: current.frame.minY - screenOrigin.y,
                           width: current.frame.width, height: current.frame.height)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        local.fill()
        NSColor.controlAccentColor.setStroke()
        let stroke = NSBezierPath(rect: local); stroke.lineWidth = 3; stroke.stroke()

        guard let title = current.title, !title.isEmpty else { return }
        // Long titles are cut with "…" so the chip never runs past the window's edges.
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .paragraphStyle: para]
        let size = (title as NSString).size(withAttributes: attrs)
        guard let chip = OverlayLabelLayout.titleChip(window: local, textSize: size,
                                                      padding: 6, margin: 12) else { return }
        let cap = NSBezierPath(roundedRect: chip.chip, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.6).setFill()
        cap.fill()
        NSColor.white.withAlphaComponent(HUDStyle.borderAlpha).setStroke()
        cap.lineWidth = 1
        cap.stroke()
        (title as NSString).draw(with: chip.text, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                 attributes: attrs)
    }
}
