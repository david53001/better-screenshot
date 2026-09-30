import Combine
import Foundation

/// Settings → Appearance → Opacity, shared with MacStats and JVoice
/// (`MacStats/docs/design-language/opacity-setting.md` §2): 0 = as see-through as each surface can
/// safely go, 0.5 = the designed default, 1 = solid. The app sets `value` from its settings; every
/// `HUDSurfaceView`, `WindowMaterial` backdrop and `CardBackground` observes it and re-applies live.
@MainActor
public final class UIOpacity: ObservableObject {
    public static let shared = UIOpacity()
    public static let defaultValue = 0.5
    /// 0…1 (the mappings clamp anything outside).
    @Published public var value = UIOpacity.defaultValue

    private init() {}
}

/// Where a `HUDSurfaceView` sits, which decides how far it may go towards clear.
public enum HUDPlacement: Equatable, Sendable {
    /// Over arbitrary apps (toast, record strip, recording pill, countdown, chips…): a white page can be
    /// right behind it, so its black tint keeps white text readable.
    case floating
    /// Only ever on the editor's / video editor's own dark window (tool pill, inspector, trim card).
    case docked
}

/// What a `HUDSurfaceView` draws at a given opacity: the blur's alpha, then a tint of
/// `NSColor(white: tintWhite, alpha: tintAlpha)` above it.
public struct HUDFill: Equatable, Sendable {
    public var backdropAlpha: Double
    public var tintAlpha: Double
    public var tintWhite: Double
}

/// The pure value → surface mappings (unit-tested in `DesignKitTests`). Each is piecewise-linear
/// through the surface's transparent (0), designed default (0.5) and solid (1) points.
public enum OpacityCurve {
    public static func value(at opacity: Double, transparent: Double, standard: Double, opaque: Double) -> Double {
        let v = opacity.isFinite ? min(max(opacity, 0), 1) : 0.5
        // a·(1−t) + b·t hits both ends exactly.
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a * (1 - t) + b * t }
        return v <= 0.5 ? lerp(transparent, standard, v / 0.5) : lerp(standard, opaque, (v - 0.5) / 0.5)
    }

    /// The solid HUD colour at 1: a dark grey like Apple's HUDs (rgb 33), not a black slab.
    public static let solidHUDWhite = 0.13

    /// Floating HUD black-tint alpha. Measured over an opaque white page on macOS 26 (2026-09-30,
    /// `docs/PROGRESS-2026-09-30-opacity.md`): tint 0.20 → white text 3.02:1, 0.40 → 4.66:1 (80 %-white
    /// secondary 3.64:1), 0.50 → 5.94:1 (v3.1.0). Default 0.42 is the lightest with margin over the
    /// 4.5:1 / 3:1 floor. **Clamp:** 0 stops at 0.22 (≈ 3.15:1), never the bare blur (2.13:1).
    public static let floatingTint = (transparent: 0.22, standard: 0.42, opaque: 1.0)
    /// Docked panels have no tint at the default (it only made black slabs on the dark window); going
    /// transparent fades their blur into the window instead. Their backdrop is always the dark window.
    public static let dockedBackdrop = (transparent: 0.5, standard: 0.85, opaque: 1.0)

    public static func hudFill(_ opacity: Double, _ placement: HUDPlacement) -> HUDFill {
        let white = value(at: opacity, transparent: 0, standard: 0, opaque: solidHUDWhite)
        switch placement {
        case .floating:
            let t = floatingTint
            return HUDFill(backdropAlpha: 1,
                           tintAlpha: value(at: opacity, transparent: t.transparent, standard: t.standard, opaque: t.opaque),
                           tintWhite: white)
        case .docked:
            let b = dockedBackdrop
            return HUDFill(backdropAlpha: value(at: opacity, transparent: b.transparent, standard: b.standard, opaque: b.opaque),
                           tintAlpha: value(at: opacity, transparent: 0, standard: 0, opaque: 1),
                           tintWhite: white)
        }
    }

    /// Alpha of the window-background colour laid over a window's `.popover` material (MacStats' popover
    /// family). Measured with dark-mode Settings over an opaque white page on macOS 26 (label 85 % white,
    /// secondary 55 %): v3.1.0's `.sidebar` 4.50:1 / 2.87:1; **0.52 (default) ≈ 4.8:1 / 3.0:1** while the
    /// see-through share (grey over white − grey over black) rises dark 0.18 → 0.20, light 0.08 → 0.13.
    /// **Clamp:** 0 stops at 0.15 (≈ 3.2:1 primary; the bare material measured 2.77:1). 1 is solid.
    public static let windowSolidCurve = (transparent: 0.15, standard: 0.52, opaque: 1.0)

    public static func windowSolid(_ opacity: Double) -> Double {
        let w = windowSolidCurve
        return value(at: opacity, transparent: w.transparent, standard: w.standard, opaque: w.opaque)
    }

    /// `Color.primary` opacity of a Settings card: faint at every setting (≤ 0.05).
    public static func cardFill(_ opacity: Double) -> Double {
        value(at: opacity, transparent: 0.03, standard: Design.cardFill, opaque: 0.05)
    }
}
