import SwiftUI

/// The inset card surface: a faint `Color.primary` fill (the window's material shows
/// through) and a hairline, with continuous corners. Without an explicit `fill`, the fill
/// follows Settings → Opacity (`OpacityCurve.cardFill`, 0.03…0.05).
public struct CardBackground: View {
    var fill: Double?
    var cornerRadius: CGFloat
    @ObservedObject private var opacity = UIOpacity.shared

    public init(fill: Double? = nil, cornerRadius: CGFloat = Design.cardCornerRadius) {
        self.fill = fill
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(Color.primary.opacity(fill ?? OpacityCurve.cardFill(opacity.value)))
            .overlay(shape.strokeBorder(Color.primary.opacity(Design.cardHairline), lineWidth: Design.hairlineWidth))
    }
}
