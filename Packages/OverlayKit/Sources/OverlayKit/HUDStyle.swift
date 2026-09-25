import AppKit

/// The one dark HUD look shared by every small floating surface (toasts, the
/// area-selection size chip, the pin's close button, the Quick Access badge):
/// a `.hudWindow` blur in `.vibrantDark`, always `.active`, under a fixed 40% black
/// tint with a 1px 10% white border. The tint is what keeps it dark over light
/// content — the blur alone reads mid-grey over a white page.
public enum HUDStyle {
    public static let tintAlpha: CGFloat = 0.40
    public static let borderAlpha: CGFloat = 0.10
    public static let primaryText = NSColor.white
    public static let secondaryText = NSColor.white.withAlphaComponent(0.6)

    /// A rounded HUD background of `frame`. Add content as subviews of the returned
    /// view (they sit above the tint). Use `.withinWindow` when the HUD floats over
    /// content drawn in the same window (a pinned image), `.behindWindow` otherwise.
    public static func makeBackground(frame: NSRect, cornerRadius: CGFloat,
                                      blending: NSVisualEffectView.BlendingMode = .behindWindow)
        -> NSVisualEffectView {
        let v = NSVisualEffectView(frame: frame)
        v.appearance = NSAppearance(named: .vibrantDark)
        v.material = .hudWindow
        v.blendingMode = blending
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.masksToBounds = true

        // Tint + border on one plain layer above the blur (a border on the effect
        // view's own layer can end up under its private material sublayers).
        let tint = NSView(frame: v.bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(tintAlpha).cgColor
        tint.layer?.borderColor = NSColor.white.withAlphaComponent(borderAlpha).cgColor
        tint.layer?.borderWidth = 1
        tint.layer?.cornerRadius = cornerRadius
        v.addSubview(tint)
        return v
    }
}
