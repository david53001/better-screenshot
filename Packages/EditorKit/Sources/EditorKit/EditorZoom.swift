import AppKit

/// The canvas's scroll view: plain scrolling pans (NSScrollView's own behaviour);
/// ⌘ + scroll wheel and trackpad pinch are turned into zoom requests anchored on the pointer.
final class EditorScrollView: NSScrollView {
    /// (zoom factor, pointer location in window coordinates)
    var onZoomGesture: ((CGFloat, NSPoint) -> Void)?

    override func magnify(with event: NSEvent) {
        onZoomGesture?(1 + event.magnification, event.locationInWindow)
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), event.scrollingDeltaY != 0 else {
            return super.scrollWheel(with: event)
        }
        // A mouse wheel notch is ~1 line; a trackpad reports points. ~13% per notch.
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
        onZoomGesture?(exp(delta * 0.01), event.locationInWindow)
    }
}

/// Owns the canvas zoom: "Fit" (re-fits whenever the window or image size changes) or a fixed
/// magnification (fit … 800%). Zooming resizes the canvas inside the scroll view — the
/// canvas maps view ↔ image through `scale`, so drawing and hit-testing follow for free.
final class CanvasZoomController: NSObject {
    private let canvas: EditorCanvasView
    private let scrollView: EditorScrollView
    /// "Fit · 57% ▾" pull-down for the action bar.
    let popup = NSPopUpButton(frame: .zero, pullsDown: true)
    private(set) var isFit = true
    /// View points per image pixel.
    private(set) var magnification: CGFloat = 1

    init(canvas: EditorCanvasView, scrollView: EditorScrollView) {
        self.canvas = canvas
        self.scrollView = scrollView
        super.init()
        scrollView.onZoomGesture = { [weak self] factor, point in
            guard let self else { return }
            self.zoom(to: self.magnification * factor, anchorInWindow: point)
        }
        scrollView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewResized),
                                               name: NSView.frameDidChangeNotification, object: scrollView)
        buildPopup()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private var backingScale: CGFloat {
        scrollView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private var fitMagnification: CGFloat {
        let insets = scrollView.contentInsets
        let available = CGSize(width: scrollView.bounds.width - insets.left - insets.right,
                               height: scrollView.bounds.height - insets.top - insets.bottom)
        return ZoomMath.fitMagnification(imageSize: canvas.currentDocument().size, available: available,
                                         backingScale: backingScale)
    }

    var percent: CGFloat { ZoomMath.percent(magnification: magnification, backingScale: backingScale) }

    // MARK: - Commands (⌘0, ⌘1, ⌘+, ⌘−, the popup)

    func fit() {
        isFit = true
        refresh()
    }

    func actualSize() { zoom(to: ZoomMath.magnification(percent: 100, backingScale: backingScale)) }

    func zoom(in zoomIn: Bool) {
        let p = ZoomMath.steppedPercent(from: percent, zoomIn: zoomIn)
        zoom(to: ZoomMath.magnification(percent: p, backingScale: backingScale))
    }

    func zoom(toPercent p: CGFloat) { zoom(to: ZoomMath.magnification(percent: p, backingScale: backingScale)) }

    /// Re-applies the canvas size: after crop / undo changed the image size, or (in Fit mode)
    /// after the visible area changed. Cheap when nothing changed.
    func refresh() {
        if isFit { magnification = fitMagnification }
        applyCanvasSize()
        updateTitle()
    }

    /// Zooms to `m` (clamped), keeping the image point under `anchorInWindow` — or, for keys
    /// and the menu, under the centre of the view — in place.
    func zoom(to m: CGFloat, anchorInWindow: NSPoint? = nil) {
        let fit = fitMagnification
        let new = ZoomMath.clamp(m, fit: fit, backingScale: backingScale)
        let old = magnification
        let clip = scrollView.contentView
        // Canvas and clip view share coordinates (canvas at the origin, both flipped).
        let anchor = anchorInWindow.map { canvas.convert($0, from: nil) }
            ?? NSPoint(x: clip.bounds.midX, y: clip.bounds.midY)
        let visibleOrigin = clip.bounds.origin   // before resizing re-constrains it
        magnification = new
        isFit = ZoomMath.isFit(new, fit: fit)
        applyCanvasSize()
        let origin = ZoomMath.anchoredOrigin(anchor: anchor, visibleOrigin: visibleOrigin, from: old, to: new)
        clip.setBoundsOrigin(clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)
        updateTitle()
    }

    private func applyCanvasSize() {
        let s = canvas.currentDocument().size
        let size = NSSize(width: s.width * magnification, height: s.height * magnification)
        if canvas.frame.size != size { canvas.setFrameSize(size) }
    }

    @objc private func scrollViewResized() { if isFit { refresh() } }

    // MARK: - Popup

    private func buildPopup() {
        popup.bezelStyle = .rounded
        popup.controlSize = .small
        popup.toolTip = "Zoom — pinch, ⌘-scroll, ⌘+ / ⌘−, ⌘0 fits, ⌘1 is 100%"
        let menu = popup.menu!
        menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))  // pull-down title slot
        func add(_ title: String, _ key: String, _ action: Selector, tag: Int = 0) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = key.isEmpty ? [] : .command
            item.target = self
            item.tag = tag
            menu.addItem(item)
        }
        add("Zoom In", "+", #selector(menuZoomIn))
        add("Zoom Out", "-", #selector(menuZoomOut))
        menu.addItem(.separator())
        add("Fit to Window", "0", #selector(menuFit))
        add("Actual Size (100%)", "1", #selector(menuActual))
        menu.addItem(.separator())
        for p in [50, 200, 400, 800] { add("\(p)%", "", #selector(menuPercent(_:)), tag: p) }
        updateTitle()
    }

    private func updateTitle() {
        popup.item(at: 0)?.title = ZoomMath.label(percent: percent, isFit: isFit)
    }

    @objc private func menuZoomIn() { zoom(in: true) }
    @objc private func menuZoomOut() { zoom(in: false) }
    @objc private func menuFit() { fit() }
    @objc private func menuActual() { actualSize() }
    @objc private func menuPercent(_ sender: NSMenuItem) { zoom(toPercent: CGFloat(sender.tag)) }
}
