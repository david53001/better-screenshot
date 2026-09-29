import AppKit

/// The app's one dark floating-control surface (toasts, chips, the record strip, the
/// recording pill, the countdown, the editor's tool pill and inspector…). Floating HUDs
/// stay dark in light mode too — Apple's are, and the contrast measurements in
/// `docs/reviews/2026-09-25-ui-review.md` (C1, E2) depend on it.
///
/// macOS 26: Liquid Glass (`NSGlassEffectView`, dark). Earlier: a `.hudWindow` blur in
/// `.vibrantDark`. Both sit under a **40 % black tint**: the blur alone measured rgb 129
/// behind white text over a white page (3.9:1); the tint is what keeps white text ≥ 4.5:1.
/// Continuous corners and a 0.5 pt white-10 % hairline. Add content with `addSubview`:
/// it lands above the backdrop and tint.
open class HUDSurfaceView: NSView {
    public static let tintAlpha: CGFloat = 0.40
    public static let hairlineAlpha: CGFloat = 0.10
    public static let primaryText = NSColor.white
    public static let secondaryText = NSColor.white.withAlphaComponent(0.6)

    /// The material behind everything: glass on macOS 26, a blur before.
    public let backdrop: NSView
    /// The black tint and hairline, above the backdrop and beneath content.
    public let tint: NSView

    public var cornerRadius: CGFloat {
        didSet { applyCorners() }
    }

    /// `.withinWindow` when the HUD floats over content drawn in its own window (a
    /// pinned image); `.behindWindow` otherwise. (Glass samples both.)
    public init(frame: NSRect = .zero, cornerRadius: CGFloat,
                blending: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.cornerRadius = cornerRadius
        backdrop = Self.makeBackdrop(blending: blending)
        tint = NSView()
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        for view in [backdrop, tint] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(Self.tintAlpha).cgColor
        tint.layer?.borderColor = NSColor.white.withAlphaComponent(Self.hairlineAlpha).cgColor
        tint.layer?.borderWidth = 0.5
        applyCorners()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Whether the backdrop is Liquid Glass (macOS 26 and a 26 SDK).
    public var usesGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return backdrop is NSGlassEffectView }
        #endif
        return false
    }

    private func applyCorners() {
        layer?.setContinuousCorners(cornerRadius)
        layer?.masksToBounds = true
        tint.layer?.setContinuousCorners(cornerRadius)
        #if compiler(>=6.2)
        if #available(macOS 26, *), let glass = backdrop as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            return
        }
        #endif
        backdrop.layer?.setContinuousCorners(cornerRadius)
    }

    private static func makeBackdrop(blending: NSVisualEffectView.BlendingMode) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.appearance = NSAppearance(named: .darkAqua)
            return glass
        }
        #endif
        let blur = NSVisualEffectView()
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.material = .hudWindow
        blur.blendingMode = blending
        blur.state = .active
        blur.wantsLayer = true
        return blur
    }
}
