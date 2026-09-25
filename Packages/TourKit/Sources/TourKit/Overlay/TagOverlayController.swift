import AppKit

/// The on-screen tour tag (spec §14.3, the owner's mock): a red outline box around the real control,
/// a red tag bubble joined to it by a leader line, and a light dim over the rest of the host window.
///
/// Two borderless panels, children of the host window so they move, hide and z-order with it:
/// - **decor** (dim + box + leader line) ignores the mouse — clicks land on the real controls under it,
///   which is what makes Try steps work;
/// - **tag** (the bubble) is the only part that takes clicks.
/// Neither can become key or main, and both are non-activating, so the host keeps key status and
/// the user's first responder — also over non-activating panels (record strip, recording pill).
/// An anchor in the menu bar (the status item) gets top-level panels instead, with the tag below it.
///
/// Keys (local monitor, only for the host window, never swallowing anything else): Return = Next on
/// Explain steps, Esc = Skip tour — both ignored while a text view is being edited (`TagKeys`).
/// Call `hide()` before dropping the controller.
@MainActor
public final class TagOverlayController: TourTagPresenting {
    public var onNext: (() -> Void)?
    public var onSkipStep: (() -> Void)?
    public var onSkipTour: (() -> Void)?

    /// The overlay's on-screen window numbers — for a screen capture's exclusion list, so the tag
    /// never ends up in the user's own screenshot or recording.
    public var windowNumbers: [Int] { [decor, tagPanel].filter(\.isVisible).map(\.windowNumber) }

    /// Every tour-tag window on screen right now, from any overlay. Screenshot and recording filters
    /// exclude these so a tag never ends up in the user's own capture.
    public static var allWindowNumbers: [Int] {
        NSApp.windows.compactMap { $0 as? TagPanel }.filter(\.isVisible).map(\.windowNumber)
    }

    /// Probes only: parks the overlay's windows at this level (just above the desktop, behind every
    /// real window) so headless probes never cover the owner's screen. Never set by the app.
    static var probeLevel: NSWindow.Level?

    /// Corner radius of a titled window's frame, for the dim's outline. Measured on macOS 26: 16 pt,
    /// 26 pt with an `NSToolbar` (none of the app's windows has one); macOS 14/15: 10 pt.
    static func titledWindowCornerRadius(hasToolbar: Bool) -> CGFloat {
        if #available(macOS 26, *) { return hasToolbar ? 26 : 16 }
        return 10
    }

    let decor = TagPanel(clickThrough: true)
    let tagPanel = TagPanel(clickThrough: false)
    let decorView = TagDecorView()
    let bubble = TagBubbleView()

    private weak var host: NSWindow?
    private weak var anchor: NSView?
    private var isExplain = true
    private var isDone = false
    private var isMenuBarHost = false
    private var tagSize = NSSize.zero
    private var laidOut: (anchor: CGRect, host: CGRect, tag: NSSize)?
    private var keyMonitor: Any?
    private var resizeObserver: NSObjectProtocol?
    private var followTimer: Timer?

    public init() {
        decor.contentView = decorView
        tagPanel.contentView = bubble
        bubble.onPrimary = { [weak self] in self?.primaryPressed() }
        bubble.onSkipTour = { [weak self] in self?.onSkipTour?() }
    }

    // MARK: - TourTagPresenting

    public func show(step: TourStep, body: String, number: Int, total: Int, anchor: NSView, host: NSWindow) {
        if self.host !== host { detach() }
        self.host = host
        self.anchor = anchor
        isExplain = step.kind == .explain
        isDone = false
        tagSize = bubble.configure(title: step.title, body: body, number: number, total: total,
                                   isExplain: isExplain)
        attach(to: host)
        laidOut = nil
        refresh()
        announce(TagStyle.announcement(title: step.title, body: body, number: number, total: total))
    }

    public func showCompleted() {
        guard host != nil else { return }
        isDone = true
        tagSize = bubble.showDone()
        laidOut = nil
        refresh()
        announce(TagStyle.completedTitle)
    }

    public func hide() {
        detach()
        orderOutWindows()
        host = nil
        anchor = nil
        laidOut = nil
    }

    // MARK: - Following the host and the anchor

    private func attach(to host: NSWindow) {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
                return consumed ? nil : event
            }
        }
        if resizeObserver == nil {
            // Live resize moves the anchor every frame; the timer alone would lag behind.
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: host, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        if followTimer == nil {
            // Catches everything that has no notification: the anchor moving inside the window,
            // going hidden, the host moving (child windows follow by themselves; the side may flip).
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            followTimer = timer
        }
    }

    private func detach() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
        followTimer?.invalidate()
        followTimer = nil
        orderOutWindows()
    }

    private func orderOutWindows() {
        for w in [tagPanel, decor] {
            w.parent?.removeChildWindow(w)
            w.orderOut(nil)
        }
    }

    /// Re-lays out when the anchor or host moved or resized; hides while the anchor can't be seen.
    func refresh() {
        guard let host, let anchor, host.isVisible, !host.isMiniaturized, anchor.window === host,
              !anchor.isHiddenOrHasHiddenAncestor, anchor.bounds.width > 0, anchor.bounds.height > 0
        else {
            if decor.isVisible || tagPanel.isVisible { orderOutWindows() }
            laidOut = nil
            return
        }
        let anchorRect = host.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        if let l = laidOut, l.anchor == anchorRect, l.host == host.frame, l.tag == tagSize,
           decor.isVisible, tagPanel.isVisible { return }
        laidOut = (anchorRect, host.frame, tagSize)

        let centre = CGPoint(x: anchorRect.midX, y: anchorRect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(centre) } ?? host.screen ?? NSScreen.main
        isMenuBarHost = Self.isMenuBarHost(host, screen: screen)
        let vertical = TagLayout.prefersVertical(containerSize: anchor.superview?.bounds.size ?? .zero)
        // A borderless host (record strip, pill, status item) is small: keep the tag off it entirely.
        let p = TagLayout.place(anchor: anchorRect, tagSize: tagSize,
                                visible: screen?.visibleFrame ?? host.frame,
                                order: TagLayout.order(verticalFirst: vertical),
                                keepOut: host.styleMask.contains(.titled) ? nil : host.frame,
                                screen: screen?.frame)

        // The decor spans the host (for the dim), the box and the tag (for the leader line).
        var frame = p.outer.union(p.tag)
        if !isMenuBarHost { frame = frame.union(host.frame) }
        frame = frame.insetBy(dx: -2, dy: -2).integral
        let o = frame.origin
        func local(_ r: CGRect) -> CGRect { r.offsetBy(dx: -o.x, dy: -o.y) }
        func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - o.x, y: p.y - o.y) }
        decorView.dim = isMenuBarHost ? nil : (local(host.frame), Self.cornerRadius(of: host))
        decorView.box = local(p.box)
        decorView.outer = local(p.outer)
        decorView.leader = p.leader.map { (local($0.from), local($0.to)) }
        decor.setFrame(frame, display: false)
        decorView.frame = NSRect(origin: .zero, size: frame.size)
        decorView.needsDisplay = true
        tagPanel.setFrame(p.tag, display: true)
        orderIn(host: host)
    }

    private func orderIn(host: NSWindow) {
        if isMenuBarHost {
            // The status bar window: top-level panels just above the menu bar.
            for w in [decor, tagPanel] {
                w.parent?.removeChildWindow(w)
                w.level = Self.probeLevel ?? max(host.level, .statusBar)
                w.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .canJoinAllSpaces, .stationary]
                if !w.isVisible { w.orderFrontRegardless() }
            }
            return
        }
        // Both or neither: re-adding one alone could put the dim above the tag.
        if [decor, tagPanel].contains(where: { $0.parent !== host || !$0.isVisible }) {
            for w in [tagPanel, decor] { w.parent?.removeChildWindow(w) }
            for w in [decor, tagPanel] {   // decor first, then the tag above it
                w.level = Self.probeLevel ?? host.level
                w.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
                host.addChildWindow(w, ordered: .above)
            }
        }
        if let level = Self.probeLevel {
            for w in [decor, tagPanel] where w.level != level { w.level = level }
        }
    }

    // MARK: - Actions and keys

    private func primaryPressed() {
        if isExplain { onNext?() } else { onSkipStep?() }
    }

    /// True when the key was ours (and is swallowed).
    func handleKey(_ event: NSEvent) -> Bool {
        guard let host, tagPanel.isVisible, !isDone,
              event.window === host || isMenuBarHost else { return false }
        let editing = (event.window?.firstResponder as? NSTextView)?.isEditable == true
        guard let action = TagKeys.action(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                          isRepeat: event.isARepeat, isExplainStep: isExplain,
                                          isEditingText: editing) else { return false }
        switch action {
        case .next: onNext?()
        case .skipTour: onSkipTour?()
        }
        return true
    }

    private func announce(_ text: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    // MARK: - Host shape

    /// The status item's window (or any untitled window sitting in the menu bar).
    static func isMenuBarHost(_ window: NSWindow, screen: NSScreen?) -> Bool {
        if String(describing: type(of: window)).contains("StatusBar") { return true }
        guard let screen, !window.styleMask.contains(.titled) else { return false }
        return screen.visibleFrame.maxY < screen.frame.maxY
            && window.frame.minY >= screen.visibleFrame.maxY - 1
    }

    /// The host's corner radius, so the dim doesn't spill past its rounded corners: the system
    /// radius for titled windows; for borderless panels (record strip, pill) the radius of the
    /// rounded background view filling their content.
    static func cornerRadius(of window: NSWindow) -> CGFloat {
        if window.styleMask.contains(.titled) { return titledWindowCornerRadius(hasToolbar: window.toolbar != nil) }
        var view = window.contentView
        for _ in 0..<3 {
            guard let v = view else { break }
            if let r = v.layer?.cornerRadius, r > 0 { return r }
            view = v.subviews.first { $0.frame.size == v.bounds.size }
        }
        return 0
    }
}
