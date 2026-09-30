import AppKit
import SwiftUI

public extension NSView {
    /// The stable id a tour step points at ("<surface>.<name>", e.g. "editor.inspector.colour").
    /// Stored as the view's accessibility identifier, so it survives layout changes and costs nothing
    /// when no tour runs.
    var tourAnchor: String? {
        get {
            let id = accessibilityIdentifier()
            return id.isEmpty ? nil : id
        }
        set { setAccessibilityIdentifier(newValue ?? "") }
    }

    /// What the tour's red outline follows, in this view's coordinates: the rect it surrounds and that
    /// rect's corner radius (0 = square). The radius is the view's own layer corner radius, or that of a
    /// same-size background view inside it (a pill's `HUDSurfaceView`), so the outline is concentric
    /// with a pill or card instead of a fixed 6 pt box around it. A stack view with no background of its
    /// own (the editor side panel's sections, which span the panel's full width) is outlined around its
    /// content rather than its padding — otherwise the outline runs along, and past, the panel's edge.
    var tourOutline: (rect: CGRect, cornerRadius: CGFloat) {
        if let radius = Self.visibleCornerRadius(of: self, depth: 2) { return (bounds, radius) }
        if let stack = self as? NSStackView, stack.layer?.backgroundColor == nil {
            let i = stack.edgeInsets
            let content = CGRect(x: bounds.minX + i.left, y: bounds.minY + (isFlipped ? i.top : i.bottom),
                                 width: bounds.width - i.left - i.right, height: bounds.height - i.top - i.bottom)
            if content.width > 0, content.height > 0 { return (content, 0) }
        }
        return (bounds, 0)
    }

    private static func visibleCornerRadius(of view: NSView, depth: Int) -> CGFloat? {
        if let r = view.layer?.cornerRadius, r > 0 { return r }
        guard depth > 0 else { return nil }
        for sub in view.subviews where !sub.isHidden && sub.frame.size == view.bounds.size {
            if let r = visibleCornerRadius(of: sub, depth: depth - 1) { return r }
        }
        return nil
    }
}

public extension NSWindow {
    /// The visible view carrying `anchor`, searching the whole window including title-bar accessories.
    /// Nil when it isn't there or is hidden — the tour then skips that step.
    func view(forTourAnchor anchor: String) -> NSView? {
        // The content view's superview is the window's frame view, which also holds the title bar.
        guard let root = contentView?.superview ?? contentView else { return nil }
        return Self.find(anchor, in: root)
    }

    private static func find(_ anchor: String, in view: NSView) -> NSView? {
        if view.isHidden { return nil }
        if view.tourAnchor == anchor { return view }
        for sub in view.subviews {
            if let found = find(anchor, in: sub) { return found }
        }
        return nil
    }
}

public extension View {
    /// SwiftUI windows (Settings, History): puts a transparent AppKit view carrying `id` behind this
    /// view, the same size, so `NSWindow.view(forTourAnchor:)` finds SwiftUI content too.
    /// `cornerRadius`: the content's own corner radius (a card's), so the outline follows it.
    func tourAnchor(_ id: String, cornerRadius: CGFloat = 0) -> some View {
        background(TourAnchorView(id: id, cornerRadius: cornerRadius))
    }
}

private struct TourAnchorView: NSViewRepresentable {
    let id: String
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true   // transparent; only carries the radius for `tourOutline`
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.tourAnchor = id
        view.layer?.cornerRadius = cornerRadius
    }
}
