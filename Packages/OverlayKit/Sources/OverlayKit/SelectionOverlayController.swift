import AppKit
import CaptureKit

public final class SelectionOverlayController {
    private var windows: [NSWindow] = []
    private var completion: ((SelectionResult?) -> Void)?

    /// True while a selection is on screen and awaiting its result. Lets the
    /// capture layer tell "our overlay has focus" apart from "the user is in
    /// one of our windows".
    public var isPresenting: Bool { completion != nil }

    public init() {}

    /// Presents selection overlays on all screens; calls completion with the result (or nil if cancelled).
    public func present(completion: @escaping (SelectionResult?) -> Void) {
        // Re-entry guard: a second capture hotkey (e.g. ⌘⇧7 during ⌘⇧4's
        // selection) cancels the open selection instead of stacking windows
        // and orphaning the first completion.
        if self.completion != nil {
            self.completion?(nil)
            self.completion = nil
            windows.forEach { $0.orderOut(nil) }
            windows.removeAll()
        }
        self.completion = completion
        for screen in NSScreen.screens {
            let view = SelectionView(frame: screen.frame)
            view.onComplete = { [weak self] rect in self?.finish(rect: rect, screen: screen) }
            view.onCancel = { [weak self] in self?.finish(rect: nil, screen: screen) }
            let window = KeyableOverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                                              backing: .buffered, defer: false, screen: screen)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            // Borderless windows can't become key by default; KeyableOverlayWindow
            // overrides that, so make the view first responder to receive Escape.
            window.makeFirstResponder(view)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Dismisses an in-flight selection (if any), firing its completion with nil.
    /// No-op when nothing is being presented.
    public func cancel() {
        guard let completion else { return }
        self.completion = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        completion(nil)
    }

    private func finish(rect: CGRect?, screen: NSScreen) {
        // Multiple overlays (one per display) can each call finish; only the
        // first wins. Clear completion first so it can never fire twice.
        guard let completion else { return }
        self.completion = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        guard let rect else { completion(nil); return }
        let clamped = SelectionClamp.clamp(rect, to: screen.frame)
        guard clamped.width >= 1, clamped.height >= 1 else { completion(nil); return }
        let displayID = (screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        completion(SelectionResult(globalRect: clamped, displayID: displayID))
    }
}

/// A borderless window that can still become key, so its view receives key
/// events (Escape to cancel). Plain borderless NSWindows return false here.
final class KeyableOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class SelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    /// "400 × 176" on a dark HUD chip just outside the selection's corner, so it stays
    /// readable over light pages and never covers what is being selected.
    private let sizeChip = SelectionSizeChip()

    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil); needsDisplay = true
        updateSizeChip()
    }

    private func updateSizeChip() {
        guard let s = start, let c = current else { sizeChip.isHidden = true; return }
        let sel = rectBetween(s, c)
        if sizeChip.superview == nil { addSubview(sizeChip) }
        sizeChip.setText("\(Int(sel.width)) × \(Int(sel.height))")
        sizeChip.setFrameOrigin(OverlayLabelLayout.selectionChipOrigin(
            selection: sel, chipSize: sizeChip.frame.size, bounds: bounds))
        sizeChip.isHidden = false
    }
    override func mouseUp(with event: NSEvent) {
        guard let s = start, let c = current else { onCancel?(); return }
        // Convert local view rect → global (window origin is screen origin here).
        let local = rectBetween(s, c)
        let global = window.map { NSRect(x: $0.frame.minX + local.minX,
                                         y: $0.frame.minY + local.minY,
                                         width: local.width, height: local.height) } ?? local
        onComplete?(global)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } // Escape
    }

    private func rectBetween(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        guard let s = start, let c = current else { return }
        let sel = rectBetween(s, c)
        // Punch out the selection.
        NSColor.clear.setFill()
        sel.fill(using: .copy)
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: sel); path.lineWidth = 1; path.stroke()
    }
}

/// The selection's size readout: white monospaced digits on the shared dark HUD chip.
final class SelectionSizeChip: NSView {
    private let label = NSTextField(labelWithString: "")
    private let background: NSVisualEffectView
    private static let height: CGFloat = 22
    private static let padX: CGFloat = 8

    init() {
        background = HUDStyle.makeBackground(frame: NSRect(x: 0, y: 0, width: 60, height: Self.height),
                                             cornerRadius: 6)
        super.init(frame: background.frame)
        background.autoresizingMask = [.width, .height]
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = HUDStyle.primaryText
        addSubview(background)
        background.addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    // The chip is a readout, not a control: clicks and drags go to the overlay.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setText(_ text: String) {
        guard label.stringValue != text else { return }
        label.stringValue = text
        label.sizeToFit()
        setFrameSize(NSSize(width: ceil(label.frame.width) + Self.padX * 2, height: Self.height))
        label.frame.origin = NSPoint(x: Self.padX, y: ((Self.height - label.frame.height) / 2).rounded())
    }
}
