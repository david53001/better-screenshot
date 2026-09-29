import SwiftUI

/// The inset card surface: a faint `Color.primary` fill (the window's material shows
/// through) and a hairline, with continuous corners.
public struct CardBackground: View {
    var fill: Double
    var cornerRadius: CGFloat

    public init(fill: Double = Design.cardFill, cornerRadius: CGFloat = Design.cardCornerRadius) {
        self.fill = fill
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(Color.primary.opacity(fill))
            .overlay(shape.strokeBorder(Color.primary.opacity(Design.cardHairline), lineWidth: Design.hairlineWidth))
    }
}
