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

/// A whole card as a button: the fill strengthens on hover and again while pressed.
public struct CardButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HoverCard(isPressed: configuration.isPressed) { configuration.label }
    }

    private struct HoverCard<Label: View>: View {
        let isPressed: Bool
        @ViewBuilder let label: Label
        @State private var hovering = false

        var body: some View {
            label
                .background(CardBackground(fill: isPressed ? Design.cardPressedFill
                                            : hovering ? Design.cardHoverFill : Design.cardFill))
                .scaleEffect(isPressed ? 0.985 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: isPressed)
                .onHover { hovering = $0 }
        }
    }
}

/// Small secondary button in the cards' material language: a continuous-corner tint
/// that brightens on hover and dims when disabled.
public struct SubtleButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        SubtleButton(configuration: configuration)
    }

    private struct SubtleButton: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let fill = configuration.isPressed ? 0.16 : hovering && isEnabled ? 0.12 : 0.08
            let shape = RoundedRectangle(cornerRadius: Design.smallButtonRadius, style: .continuous)
            configuration.label
                .font(.callout.weight(.medium))
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .padding(.horizontal, 10)
                .frame(height: Design.smallButtonHeight)
                .background(shape.fill(Color.primary.opacity(fill)))
                .contentShape(shape)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}
