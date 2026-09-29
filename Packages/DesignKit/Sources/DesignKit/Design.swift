import SwiftUI

/// Shared tokens (MacStats design language, `MacStats/docs/design-language/README.md` §2).
/// Surfaces are `Color.primary` tints so the window's material shows through and they
/// follow light/dark. Nested corners are concentric: inner radius = outer − gap.
public enum Design {
    /// Content cards in a regular window (System Settings' grouped sections).
    public static let cardCornerRadius: CGFloat = 10
    /// Gap between neighbouring cards and the window edge.
    public static let outerPadding: CGFloat = 20
    public static let cardSpacing: CGFloat = 12
    public static let cardPadding: CGFloat = 12
    /// `Color.primary` opacities.
    public static let cardFill: Double = 0.04
    public static let cardHairline: Double = 0.08
    /// Borders are hairlines: one physical pixel on Retina.
    public static let hairlineWidth: CGFloat = 0.5
}

public extension CALayer {
    /// Rounds with Apple's continuous (squircle) curve instead of a circular arc.
    func setContinuousCorners(_ radius: CGFloat) {
        cornerRadius = radius; cornerCurve = .continuous
    }
}
