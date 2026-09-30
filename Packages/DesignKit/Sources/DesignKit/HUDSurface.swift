import AppKit
import Combine

/// The app's one dark floating-control surface (toasts, chips, the record strip, the
/// recording pill, the countdown, the editor's tool pill and inspector…). Floating HUDs
/// stay dark in light mode too — Apple's are, and the contrast measurements in
/// `docs/reviews/2026-09-25-ui-review.md` (C1, E2) depend on it.
///
/// A `.hudWindow` blur in `.vibrantDark` under a black tint, continuous corners and a 0.5 pt
/// white-10 % hairline. The tint follows Settings → Opacity (`UIOpacity`, mapping in
/// `OpacityCurve.hudFill`): **42 %** at the default — white text ≈ 4.9:1 over an opaque white page
/// on macOS 26 (v3.1.0's 50 % measured 5.94:1), never below 22 % (≈ 3.15:1), a solid dark grey at 1;
/// the same at every size and at 0.5, 2 and 5 s. Not Liquid Glass: glass adapts to what is
/// behind it, and a 715 × 40 pill with a window shadow went from rgb 75 to rgb 166 (2.44:1)
/// within 2 s — no tint arrangement (overlay, `tintColor`, content in `contentView`, clear
/// style) kept it readable (`docs/reviews/2026-09-29-native-look-review.md` H1).
/// Add content with `addSubview`: it lands above the backdrop and tint.
open class HUDSurfaceView: NSView {
    public static let hairlineAlpha: CGFloat = 0.10
    public static let primaryText = NSColor.white
    /// 80 % white: ≈ 3.8:1 on the default tint over white (60 % measured 4.3:1 at v3.1.0's tint).
    public static let secondaryText = NSColor.white.withAlphaComponent(0.8)

    /// The blur behind everything.
    public let backdrop: NSVisualEffectView
    /// The black tint and hairline, above the backdrop and beneath content.
    public let tint: NSView
    public let placement: HUDPlacement
    private var opacityWatch: AnyCancellable?

    public var cornerRadius: CGFloat {
        didSet { applyCorners() }
    }

    /// `.withinWindow` when the HUD floats over content drawn in its own window (a
    /// pinned image, the editor's canvas); `.behindWindow` otherwise. `placement`: `.docked`
    /// for panels that only ever sit on the editor's dark window (no tint at the default —
    /// there it just made black slabs).
    public init(frame: NSRect = .zero, cornerRadius: CGFloat,
                blending: NSVisualEffectView.BlendingMode = .behindWindow, placement: HUDPlacement = .floating) {
        self.cornerRadius = cornerRadius
        self.placement = placement
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
        tint.layer?.borderColor = NSColor.white.withAlphaComponent(Self.hairlineAlpha).cgColor
        tint.layer?.borderWidth = 0.5
        applyCorners()
        // Emits the current value now, then every Settings → Opacity change (live).
        opacityWatch = UIOpacity.shared.$value.sink { [weak self] in self?.applyOpacity($0) }
    }

    private func applyOpacity(_ opacity: Double) {
        let fill = OpacityCurve.hudFill(opacity, placement)
        backdrop.alphaValue = fill.backdropAlpha
        tint.layer?.backgroundColor = NSColor(white: fill.tintWhite, alpha: fill.tintAlpha).cgColor
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func applyCorners() {
        layer?.setContinuousCorners(cornerRadius)
        layer?.masksToBounds = true
        backdrop.layer?.setContinuousCorners(cornerRadius)
        tint.layer?.setContinuousCorners(cornerRadius)
    }
}
