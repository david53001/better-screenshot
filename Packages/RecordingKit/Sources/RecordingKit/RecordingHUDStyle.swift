import AppKit

/// The app's one dark HUD look (v3 spec §2, UI review 2026-09-25 C1), as used by the
/// recording surfaces — the record strip, the live recording pill and its hover hint,
/// and the countdown. A blurred `.hudWindow` material forced to vibrant-dark, a fixed
/// **40% black tint** so white text stays readable over light windows (the blur alone
/// measured rgb 129 behind white text, 3.9:1), and a **1px 10% white** border.
/// Primary text is white, secondary text white 60%. Every other HUD surface in the app
/// uses the same values.
public enum RecordingHUDStyle {
    public static let tintAlpha: CGFloat = 0.4
    public static let borderAlpha: CGFloat = 0.1
    public static let primaryText = NSColor.white
    public static let secondaryText = NSColor.white.withAlphaComponent(0.6)

    /// A new HUD background with `cornerRadius`; add content on top of it.
    @MainActor public static func makeBackground(cornerRadius: CGFloat) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        apply(to: view, cornerRadius: cornerRadius)
        return view
    }

    /// Styles an existing effect view and slides the tint in beneath its content.
    @MainActor public static func apply(to view: NSVisualEffectView, cornerRadius: CGFloat) {
        view.appearance = NSAppearance(named: .vibrantDark)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(borderAlpha).cgColor
        let tint = TintView(frame: view.bounds)
        tint.autoresizingMask = [.width, .height]
        view.addSubview(tint, positioned: .below, relativeTo: nil)
    }

    /// The tint layer (exposed for tests).
    public final class TintView: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.withAlphaComponent(RecordingHUDStyle.tintAlpha).cgColor
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    }
}
