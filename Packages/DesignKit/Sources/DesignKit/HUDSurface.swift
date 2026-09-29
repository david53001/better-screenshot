import AppKit

/// The app's one dark floating-control surface (toasts, chips, the record strip, the
/// recording pill, the countdown, the editor's tool pill and inspector…). Floating HUDs
/// stay dark in light mode too — Apple's are, and the contrast measurements in
/// `docs/reviews/2026-09-25-ui-review.md` (C1, E2) depend on it.
///
/// A `.hudWindow` blur in `.vibrantDark` under a **50 % black tint**, continuous corners
/// and a 0.5 pt white-10 % hairline. Measured on macOS 26 over an opaque white page
/// (2026-09-29): blur alone rgb 116 (white text 4.66:1), with the tint rgb 100 → **5.94:1**,
/// the same at every size and at 0.5, 2 and 5 s. Not Liquid Glass: glass adapts to what is
/// behind it, and a 715 × 40 pill with a window shadow went from rgb 75 to rgb 166 (2.44:1)
/// within 2 s — no tint arrangement (overlay, `tintColor`, content in `contentView`, clear
/// style) kept it readable (`docs/reviews/2026-09-29-native-look-review.md` H1).
/// Add content with `addSubview`: it lands above the backdrop and tint.
open class HUDSurfaceView: NSView {
    /// The tint for surfaces that float over arbitrary content.
    public static let tintAlpha: CGFloat = 0.50
    public static let hairlineAlpha: CGFloat = 0.10
    public static let primaryText = NSColor.white
    /// 80 % white: ≈ 4.5:1 on the tinted backdrop over white (60 % measured 4.3:1 at a 40 % tint).
    public static let secondaryText = NSColor.white.withAlphaComponent(0.8)

    /// The blur behind everything.
    public let backdrop: NSVisualEffectView
    /// The black tint and hairline, above the backdrop and beneath content.
    public let tint: NSView

    public var cornerRadius: CGFloat {
        didSet { applyCorners() }
    }

    /// `.withinWindow` when the HUD floats over content drawn in its own window (a
    /// pinned image, the editor's canvas); `.behindWindow` otherwise. `tint`: the black
    /// overlay's opacity — `tintAlpha` over arbitrary content; less for panels that only
    /// ever sit on the editor's dark window, where the tint would just make black slabs.
    public init(frame: NSRect = .zero, cornerRadius: CGFloat,
                blending: NSVisualEffectView.BlendingMode = .behindWindow, tint tintOpacity: CGFloat = tintAlpha) {
        self.cornerRadius = cornerRadius
        backdrop = NSVisualEffectView()
        tint = NSView()
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        backdrop.appearance = NSAppearance(named: .vibrantDark)
        backdrop.material = .hudWindow
        backdrop.blendingMode = blending
        backdrop.state = .active
        backdrop.wantsLayer = true
        for view in [backdrop, tint] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(tintOpacity).cgColor
        tint.layer?.borderColor = NSColor.white.withAlphaComponent(Self.hairlineAlpha).cgColor
        tint.layer?.borderWidth = 0.5
        applyCorners()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func applyCorners() {
        layer?.setContinuousCorners(cornerRadius)
        layer?.masksToBounds = true
        backdrop.layer?.setContinuousCorners(cornerRadius)
        tint.layer?.setContinuousCorners(cornerRadius)
    }
}
