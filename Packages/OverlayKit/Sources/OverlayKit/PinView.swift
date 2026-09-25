import AppKit

/// The pinned screenshot's content view: drag anywhere to move, drag the
/// bottom-right hotspot or scroll to resize (aspect-locked, 0.25×–3×),
/// double-click to copy, hover for the ✕ close button, right-click for
/// Copy/Save/Close. NSView is an NSObject, so it safely owns its tracking area.
final class PinView: NSView {
    private let image: NSImage
    private let naturalSize: CGSize          // 1× point size; zoom-clamp baseline
    private let actions: PinActions
    private let onClose: () -> Void

    private let closeButton = NSButton()
    /// Dark HUD circle behind the ✕ so it reads on light pins too; shown on hover.
    private let closeBacking = HUDStyle.makeBackground(frame: NSRect(x: 0, y: 0, width: 22, height: 22),
                                                       cornerRadius: 11, blending: .withinWindow)
    private enum DragMode { case none, move, resize }
    private var dragMode: DragMode = .none
    private var dragStartMouse = CGPoint.zero    // screen coords
    private var dragStartFrame = CGRect.zero
    private static let resizeHotspot: CGFloat = 16

    init(image: NSImage, naturalSize: CGSize, actions: PinActions,
         onClose: @escaping () -> Void) {
        self.image = image
        self.naturalSize = naturalSize
        self.actions = actions
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close pin")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .bold))
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.setAccessibilityLabel("Close pin")
        closeButton.toolTip = "Close pin"
        closeButton.contentTintColor = HUDStyle.primaryText
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.frame = closeBacking.bounds
        closeButton.autoresizingMask = [.width, .height]
        closeBacking.addSubview(closeButton)
        closeBacking.isHidden = true
        addSubview(closeBacking)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }

    override func layout() {
        super.layout()
        closeBacking.frame = NSRect(x: 6, y: bounds.height - 28, width: 22, height: 22)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { closeBacking.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeBacking.isHidden = true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStartMouse = NSEvent.mouseLocation
        dragStartFrame = window.frame
        let local = convert(event.locationInWindow, from: nil)
        let inHotspot = local.x > bounds.width - Self.resizeHotspot
            && local.y < Self.resizeHotspot
        dragMode = inHotspot ? .resize : .move
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragStartMouse.x
        let dy = mouse.y - dragStartMouse.y
        switch dragMode {
        case .move:
            window.setFrameOrigin(NSPoint(x: dragStartFrame.origin.x + dx,
                                          y: dragStartFrame.origin.y + dy))
        case .resize:
            // Bottom-right drag: aspect follows the horizontal axis.
            let targetW = max(40, dragStartFrame.width + dx)
            let f = PinGeometry.zoomedFrame(current: dragStartFrame,
                                            naturalSize: naturalSize,
                                            factor: targetW / dragStartFrame.width)
            // Anchor the top-left corner while resizing from bottom-right.
            window.setFrame(NSRect(x: dragStartFrame.minX,
                                   y: dragStartFrame.maxY - f.height,
                                   width: f.width, height: f.height), display: true)
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        // Double-click on mouseUp (standard NSView pattern) so a tiny drift
        // between the two clicks doesn't turn into a window micro-drag.
        if event.clickCount == 2 { actions.onCopy() }
        dragMode = .none
    }

    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }
        let factor = 1 + event.scrollingDeltaY * 0.005
        guard factor > 0.05 else { return }
        let f = PinGeometry.zoomedFrame(current: window.frame,
                                        naturalSize: naturalSize, factor: factor)
        window.setFrame(f, display: true)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy Image", action: #selector(copyTapped),
                     keyEquivalent: "").target = self
        menu.addItem(withTitle: "Save Image", action: #selector(saveTapped),
                     keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close Pin", action: #selector(closeTapped),
                     keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func copyTapped() { actions.onCopy() }
    @objc private func saveTapped() { actions.onSave() }
    @objc private func closeTapped() { onClose() }
}
