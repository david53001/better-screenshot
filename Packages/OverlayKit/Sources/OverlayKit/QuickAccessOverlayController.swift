import AppKit
import QuartzCore
import TourKit

public struct QuickAccessActions {
    public let onCopy: () -> Void
    public let onSave: () -> Void
    public let onAnnotate: () -> Void
    public let onOpen: () -> Void
    public let onReveal: () -> Void
    public let fileURLForDrag: () -> URL?
    /// Recordings only: opens the trim window. nil = no Trim button (e.g. GIFs).
    public let onTrim: (() -> Void)?
    public init(onCopy: @escaping () -> Void = {}, onSave: @escaping () -> Void = {},
                onAnnotate: @escaping () -> Void = {},
                onOpen: @escaping () -> Void = {}, onReveal: @escaping () -> Void = {},
                fileURLForDrag: @escaping () -> URL? = { nil },
                onTrim: (() -> Void)? = nil) {
        self.onCopy = onCopy; self.onSave = onSave
        self.onAnnotate = onAnnotate
        self.onOpen = onOpen; self.onReveal = onReveal
        self.fileURLForDrag = fileURLForDrag
        self.onTrim = onTrim
    }
}

/// What the overlay represents — drives the button row and drag semantics
/// (screenshots drag disposable temp PNGs; recordings drag the real saved file).
public enum QuickAccessKind {
    case screenshot
    case recording
}

/// Why a Quick Access overlay went away. `closed` (✕) and `evicted` (pushed
/// out by newer captures) are "accidental" — eligible for Restore Recently
/// Closed. `actionTaken` (save, annotate, pin, open, reveal, drag-out) is
/// deliberate and is not restorable.
public enum DismissReason: Equatable {
    case closed, evicted, actionTaken
}

/// A floating post-capture card. The captured image FILLS the rounded card
/// edge-to-edge; the action buttons float over the bottom of the image on a
/// tone-matched gradient scrim, and their glyphs auto-flip black/white for
/// legibility against whatever the picture is.
///
/// By default it is PERSISTENT: it never auto-dismisses. It goes away only when
/// the user clicks ✕, clicks Save (download), drags the thumbnail out to another
/// app, or opens the editor. Callers may opt into an auto-dismiss countdown
/// (`autoDismissSeconds`) that pauses while the mouse hovers the card and
/// restarts the full countdown on mouse-exit.
///
/// NSObject subclass so it is a first-class Obj-C target for the buttons.
public final class QuickAccessOverlayController: NSObject {
    private var panel: NSPanel?
    private var actions: QuickAccessActions?
    private var autoDismissSeconds: Int = 0
    private var autoDismissTimer: Timer?

    /// The card's content size (== panel size). Derived from the image aspect
    /// ratio via `QuickAccessCardSize`. Read by the stacking layer.
    public private(set) var contentSize: CGSize = .zero

    /// Fired exactly once whenever a visible overlay goes away (✕, save,
    /// drag-out, annotate, pin, or eviction) so a stack manager can compact
    /// and the app can track restorable closes.
    public var onDismissed: ((DismissReason) -> Void)?

    /// The card's panel while it's on screen (the guided tours attach their tag to it).
    public var window: NSWindow? { panel }

    public override init() { super.init() }

    /// Presents the overlay at the given screen origin (Cocoa bottom-left coords).
    /// `badge` is a short caption for the top-left corner ("0:42 · MP4" on a recording).
    public func present(image: NSImage, at origin: CGPoint,
                        kind: QuickAccessKind = .screenshot, actions: QuickAccessActions,
                        autoDismissSeconds: Int = 0, badge: String? = nil) {
        dismiss(reason: .evicted)
        self.actions = actions
        self.autoDismissSeconds = autoDismissSeconds

        // Size the card to the capture's pixel aspect ratio (full-bleed, no
        // letterbox). Fall back to the NSImage point size if there's no CGImage.
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let pxW = cg?.width ?? Int(image.size.width.rounded())
        let pxH = cg?.height ?? Int(image.size.height.rounded())
        let size = QuickAccessCardSize.contentSize(imagePixelWidth: pxW, imagePixelHeight: pxH)
        self.contentSize = size

        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Rounded card that clips the full-bleed image + overlaid controls.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.tourAnchor = "quickAccess.card"

        // Full-bleed image. The DraggableImageView owns the drag-to-export gesture
        // (a >4pt move starts the drag) but draws nothing itself: the picture is
        // the aspect-fill sublayer below, so the scrim and buttons stay on top of it.
        let thumb = DraggableImageView(frame: container.bounds)
        thumb.image = image                       // drag-preview source only
        thumb.wantsLayer = true
        thumb.layer?.masksToBounds = true
        thumb.fileURLProvider = actions.fileURLForDrag
        // Screenshots drag a self-deleting temp PNG; recordings drag the real
        // saved file, which must NOT be cleaned up after the drop.
        thumb.onDragEnded = { [weak self] droppedSomewhere in
            guard let self, droppedSomewhere else { return }
            self.tourEvent("dragged")
            // The Quick Access tour asks for this drag and carries on over the card.
            if !self.isShowingTour { self.dismiss(reason: .actionTaken) }
        }

        if let cg {
            let imageLayer = CALayer()
            imageLayer.frame = thumb.bounds
            imageLayer.contents = cg
            imageLayer.contentsGravity = .resizeAspectFill
            imageLayer.masksToBounds = true
            imageLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            thumb.layer?.addSublayer(imageLayer)
        }

        // Build the action row FIRST: the auto-contrast sample has to read the
        // pixels this row lands on, so its final frame must be known before the
        // image is sampled. Colours are applied further down, once the plan exists.
        var buttons: [QuickAccessIconButton] = []
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.spacing = 4

        func button(_ symbol: String, _ tip: String,
                    _ onClick: @escaping () -> Void) -> QuickAccessIconButton {
            let b = QuickAccessIconButton(symbol: symbol, tip: tip, onClick: onClick)
            buttons.append(b)
            return b
        }
        switch kind {
        case .screenshot:
            let copy = button("doc.on.doc", "Copy") { [weak self] in self?.copyAction() }
            let edit = button("pencil.tip.crop.circle", "Edit") { [weak self] in self?.annotateAction() }
            edit.tourAnchor = "quickAccess.edit"
            let save = button("square.and.arrow.down", "Save to screenshots") { [weak self] in self?.saveAction() }
            // Grouped only so the tour outlines Copy · Edit · Save without ✕; same 4 pt spacing as the row.
            let group = NSStackView(views: [copy, edit, save])
            group.spacing = stack.spacing
            group.tourAnchor = "quickAccess.actions"
            stack.addArrangedSubview(group)
        case .recording:
            stack.addArrangedSubview(button("doc.on.doc", "Copy file") { [weak self] in self?.copyAction() })
            if actions.onTrim != nil {
                stack.addArrangedSubview(button("scissors", "Edit video") { [weak self] in self?.trimAction() })
            }
            stack.addArrangedSubview(button("play.fill", "Open") { [weak self] in self?.openAction() })
            stack.addArrangedSubview(button("folder", "Show in Finder") { [weak self] in self?.revealAction() })
        }
        stack.addArrangedSubview(button("xmark", "Close") { [weak self] in self?.closeAction() })

        // Centre the row horizontally, anchored 9pt up from the bottom edge.
        let rowSize = stack.fittingSize
        let rowFrame = NSRect(x: (size.width - rowSize.width) / 2, y: 9,
                              width: rowSize.width, height: 30)
        stack.frame = rowFrame

        // Auto-contrast from the pixels actually behind the row — not the image's
        // own bottom strip, which aspect-fill may have cropped off screen. With no
        // CGImage there is nothing to read: 0/0 plans light glyphs at the minimum
        // scrim, which is what a dark shot got before.
        let extremes = cg.map { sampleBandExtremes($0, cardSize: size, rowFrame: rowFrame) }
            ?? QuickAccessContrast.BandExtremes(dark: 0, bright: 0)
        let plan = QuickAccessContrast.plan(for: extremes)
        let palette = plan.palette

        // Tone-matched scrim so glyphs stay legible over the picture: sits above
        // the image and below the buttons; a plain layer so it never intercepts
        // the drag or the button clicks. It fades in ABOVE the row and then HOLDS
        // plan.scrimAlpha flat from the row's top edge down to the card bottom:
        // the 4.5:1 guarantee is solved for a single alpha over the whole sampled
        // band, so the scrimmed area has to cover every pixel that was sampled.
        let fadeH: CGFloat = 28
        let scrimH = min(rowFrame.maxY + fadeH, size.height)
        let solidStart = max(0, (scrimH - rowFrame.maxY) / scrimH)
        let scrim = CAGradientLayer()
        scrim.frame = CGRect(x: 0, y: 0, width: size.width, height: scrimH)
        scrim.startPoint = CGPoint(x: 0.5, y: 1.0)   // location 0 → top of the scrim
        scrim.endPoint = CGPoint(x: 0.5, y: 0.0)     // location 1 → card bottom
        scrim.locations = [0.0, NSNumber(value: Double(solidStart)), 1.0]
        let sc: CGFloat = palette.scrimIsWhite ? 1.0 : 0.0
        let sa = CGFloat(plan.scrimAlpha)
        scrim.colors = [
            CGColor(srgbRed: sc, green: sc, blue: sc, alpha: 0.0),
            CGColor(srgbRed: sc, green: sc, blue: sc, alpha: sa),
            CGColor(srgbRed: sc, green: sc, blue: sc, alpha: sa),
        ]
        thumb.layer?.addSublayer(scrim)

        // Subtle top hairline (~15% white) for a crisp card edge.
        let hairline = CALayer()
        hairline.frame = CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)
        hairline.backgroundColor = CGColor(srgbRed: 1, green: 1, blue: 1,
                                           alpha: CGFloat(0x26) / 255.0)
        thumb.layer?.addSublayer(hairline)

        container.addSubview(thumb)

        // Overlaid, auto-contrasted action row. Buttons are subviews layered
        // above the image + scrim, so they receive clicks while the image below
        // still receives drags.
        buttons.forEach {
            $0.apply(glyph: Self.nsColor(argb: palette.glyphARGB),
                     hover: Self.nsColor(argb: palette.hoverARGB),
                     pressed: Self.nsColor(argb: palette.pressedARGB))
        }
        container.addSubview(stack)

        // Recording badge ("0:42 · MP4") in the top-left corner, clear of the button
        // row. Click-through, so the drag gesture still works over it.
        if let badge, !badge.isEmpty {
            container.addSubview(Self.badgeView(badge, cardSize: size))
        }

        // Full-size, click-through hover layer on top of everything so mouse
        // enter/exit pause/restart the auto-dismiss countdown for the whole
        // card, without stealing clicks from the buttons or the drag gesture
        // (see HoverTrackingView.hitTest).
        let hoverView = HoverTrackingView(frame: container.bounds)
        hoverView.onEnter = { [weak self] in self?.pauseAutoDismiss() }
        hoverView.onExit = { [weak self] in self?.startAutoDismiss() }
        container.addSubview(hoverView)

        panel.contentView = container
        panel.orderFrontRegardless()
        self.panel = panel
        // If the cursor already rests where the card just appeared, AppKit
        // won't fire an initial mouseEntered: on HoverTrackingView, so the
        // countdown would run (and could dismiss the card) while it's
        // effectively hovered. Treat that case as already-paused; the
        // existing mouseExited: → startAutoDismiss() path begins the
        // countdown once the cursor actually leaves.
        if autoDismissSeconds > 0 {
            if panel.frame.contains(NSEvent.mouseLocation) {
                pauseAutoDismiss()
            } else {
                startAutoDismiss()
            }
        }
    }

    public func dismiss(reason: DismissReason = .actionTaken) {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        guard panel != nil else { return }
        panel?.orderOut(nil); panel = nil; actions = nil
        onDismissed?(reason)
    }

    /// Starts (or restarts) the auto-dismiss countdown. No-op when
    /// `autoDismissSeconds <= 0` (persistent overlay).
    private func startAutoDismiss() {
        guard autoDismissSeconds > 0 else { return }
        autoDismissTimer?.invalidate()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: Double(autoDismissSeconds),
                                                repeats: false) { [weak self] _ in
            guard let self else { return }
            // A running tour pauses the countdown, like hovering does.
            if self.isShowingTour { self.startAutoDismiss() } else { self.dismiss(reason: .closed) }
        }
    }

    /// A guided tour is pointing at this card: TourKit's tag panels are child windows of their host.
    /// The card then stays up — no auto-dismiss, and a drop doesn't close it.
    private var isShowingTour: Bool {
        guard let children = panel?.childWindows, !children.isEmpty else { return false }
        let tags = MainActor.assumeIsolated { Set(TagOverlayController.allWindowNumbers) }
        return children.contains { tags.contains($0.windowNumber) }
    }

    /// Tells the guided tours what the user did on the card ("quickAccess.<name>"); a no-op when no
    /// tour listens. Every caller runs on the main thread (clicks, drags).
    private func tourEvent(_ name: String) {
        MainActor.assumeIsolated { TourEvents.post(.action("quickAccess.\(name)")) }
    }

    /// Pauses the auto-dismiss countdown (e.g. while the mouse hovers the card).
    private func pauseAutoDismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }

    /// Slides the overlay to a new stack slot.
    public func move(to origin: CGPoint) {
        panel?.setFrameOrigin(origin)
    }

    /// Luminance extremes of the pixels the button row actually sits on. The card
    /// draws the image `.resizeAspectFill`, so the row's card rect has to be mapped
    /// back through `AspectFillMap` — the image's own bottom strip is often cropped
    /// off screen. Read into a tight RGBA buffer at the band's on-screen resolution.
    /// Any failure → dark 0 / bright 0, i.e. light glyphs at the minimum scrim,
    /// which is what a fully dark shot plans to anyway.
    private func sampleBandExtremes(_ cg: CGImage, cardSize: CGSize,
                                    rowFrame: CGRect) -> QuickAccessContrast.BandExtremes {
        let none = QuickAccessContrast.BandExtremes(dark: 0, bright: 0)
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return none }

        // Pad a few points so glyph antialiasing spilling past the row is covered.
        // The scrim holds its flat alpha over rowFrame.maxY and below, so this stays
        // a subset of the scrimmed area — the direction the contrast proof allows.
        let padded = rowFrame.insetBy(dx: -4, dy: -4)
            .intersection(CGRect(origin: .zero, size: cardSize))
        guard !padded.isNull, padded.width > 0, padded.height > 0 else { return none }
        // AspectFillMap (and CGImage.cropping) are top-left; rowFrame is AppKit bottom-left.
        let topLeftRect = CGRect(x: padded.minX, y: cardSize.height - padded.maxY,
                                 width: padded.width, height: padded.height)
        let srcRect = AspectFillMap.sourceRect(cardSize: cardSize,
                                               imagePixelSize: CGSize(width: w, height: h),
                                               cardRect: topLeftRect)
        guard srcRect.width >= 1, srcRect.height >= 1,
              let band = cg.cropping(to: srcRect) else { return none }

        // Downsample no further than the band's own device pixels — that is exactly
        // the reduction CoreAnimation performs when it draws the layer, so the
        // percentiles describe what is on screen. Going smaller box-filters a white
        // headline into its dark surround (0.91 → 0.33 on the measured lock-screen
        // case) and plans a scrim far too weak for the pixels the user actually sees.
        let sw = band.width, sh = band.height
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        let tw = max(1, min(sw, Int((padded.width * backing).rounded())))
        let th = max(1, min(sh, Int((padded.height * backing).rounded())))

        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data
        else { return none }
        ctx.draw(band, in: CGRect(x: 0, y: 0, width: tw, height: th))

        // Copy row-by-row into a tight buffer so any bytesPerRow stride padding
        // CoreGraphics chose doesn't corrupt the sampled pixels.
        let bpr = ctx.bytesPerRow
        let src = data.bindMemory(to: UInt8.self, capacity: bpr * th)
        let pixelCount = tw * th
        let rowBytes = tw * 4
        var rgba = [UInt8](repeating: 0, count: pixelCount * 4)
        rgba.withUnsafeMutableBufferPointer { dst in
            for row in 0..<th {
                let s = row * bpr
                let d = row * rowBytes
                for i in 0..<rowBytes { dst[d + i] = src[s + i] }
            }
        }
        return BandLuminance.extremes(rgba: rgba, pixelCount: pixelCount)
    }

    /// A shared-HUD-style chip holding `text`, pinned 8pt in from the top-left corner.
    private static func badgeView(_ text: String, cardSize: CGSize) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = HUDStyle.primaryText
        label.sizeToFit()
        let chipSize = NSSize(width: ceil(label.frame.width) + 14, height: 20)
        let holder = ClickThroughView(frame: NSRect(x: 8, y: cardSize.height - 8 - chipSize.height,
                                                    width: chipSize.width, height: chipSize.height))
        // Blends with the card's own image layer, which is drawn in this window.
        let chip = HUDStyle.makeBackground(frame: holder.bounds, cornerRadius: 6,
                                           blending: .withinWindow)
        label.frame.origin = NSPoint(x: 7, y: ((chipSize.height - label.frame.height) / 2).rounded())
        chip.addSubview(label)
        holder.addSubview(chip)
        holder.setAccessibilityElement(true)
        holder.setAccessibilityRole(.staticText)
        holder.setAccessibilityLabel(text)
        return holder
    }

    private static func nsColor(argb: UInt32) -> NSColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    // Copy keeps the overlay up (so the user can still save/drag/close it).
    @objc private func copyAction() { tourEvent("copy"); actions?.onCopy() }
    // Save writes to the screenshot folder, then dismisses.
    @objc private func saveAction() { tourEvent("save"); actions?.onSave(); dismiss(reason: .actionTaken) }
    // Opening the editor takes over from the overlay. The tour hears about it first, so the
    // Quick Access tour finishes (and hands over) before the editor window appears.
    @objc private func annotateAction() {
        tourEvent("edit")
        let a = actions
        dismiss(reason: .actionTaken)
        a?.onAnnotate()
    }
    // Opening the recording hands off to the default player.
    @objc private func openAction() {
        let a = actions
        dismiss(reason: .actionTaken)
        a?.onOpen()
    }
    // Trimming opens its own window, which takes over from the overlay.
    @objc private func trimAction() {
        let a = actions
        dismiss(reason: .actionTaken)
        a?.onTrim?()
    }
    // Revealing in Finder is the recording's "I know where it lives now".
    @objc private func revealAction() {
        let a = actions
        dismiss(reason: .actionTaken)
        a?.onReveal()
    }
    @objc private func closeAction() { dismiss(reason: .closed) }
}

/// A chromeless, layer-backed icon button for the overlaid action row: a
/// template SF Symbol tinted to the auto-contrast glyph colour on a transparent
/// pill that fills on hover / press. Plain NSView (not NSControl) so it stays
/// visually silent over the image; clicks fire the `onClick` closure.
private final class QuickAccessIconButton: NSView {
    private let glyphView: NSImageView
    private var hoverColor: CGColor?
    private var pressedColor: CGColor?
    private let onClick: () -> Void
    private var trackingAreaRef: NSTrackingArea?
    private var hovered = false

    init(symbol: String, tip: String, onClick: @escaping () -> Void) {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            ?? NSImage(size: NSSize(width: 1, height: 1))
        img.isTemplate = true
        glyphView = NSImageView(frame: NSRect(x: (32 - 17) / 2.0, y: (30 - 17) / 2.0,
                                              width: 17, height: 17))
        glyphView.image = img
        glyphView.imageScaling = .scaleProportionallyUpOrDown
        self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: 32, height: 30))
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        toolTip = tip
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
        addSubview(glyphView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Colours land after init: the row has to exist, and be measured, before the
    /// pixels underneath it can be sampled for the contrast plan.
    func apply(glyph: NSColor, hover: NSColor, pressed: NSColor) {
        glyphView.contentTintColor = glyph
        hoverColor = hover.cgColor
        pressedColor = pressed.cgColor
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 32, height: 30) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        layer?.backgroundColor = hoverColor
    }
    override func mouseExited(with event: NSEvent) {
        hovered = false
        layer?.backgroundColor = nil
    }
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = pressedColor
    }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        layer?.backgroundColor = hovered ? hoverColor : nil
        if inside { onClick() }
    }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
}

/// Never the target of a click, so the drag-to-export gesture passes through
/// whatever it contains (the badge).
private final class ClickThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A transparent, click-through view that exists solely to own a tracking area
/// spanning the whole card, so hover can pause/restart the auto-dismiss
/// countdown. It must NOT be used as an `NSTrackingArea` owner directly by the
/// controller (that previously crashed with an unrecognized-selector on
/// `mouseEntered:`) — this dedicated NSView owns the tracking area and
/// implements the callbacks itself, forwarding via closures.
///
/// `hitTest(_:)` always returns nil so it never intercepts clicks or the
/// drag gesture; the tracking area still tracks mouse-enter/exit over its
/// `.inVisibleRect` because tracking areas work independently of hit-testing.
private final class HoverTrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
