import SwiftUI

/// Draggable slider over an `Int` position within `range`, styled for the JVoice monochrome
/// theme. Callers map the position to a domain value (e.g. `OverlayDismissScale`) and back.
struct MonoSlider: View {
    @Binding var position: Int
    let range: ClosedRange<Int>
    let valueLabel: (Int) -> String

    @State private var isHovering = false
    @State private var isDragging = false

    private var fraction: CGFloat {
        let span = CGFloat(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        return CGFloat(position - range.lowerBound) / span
    }

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(SettingsTheme.sliderTrack)
                        .frame(height: SettingsTheme.Metrics.sliderTrackHeight)
                    Capsule()
                        .fill(SettingsTheme.accent)
                        .frame(width: max(0, geo.size.width * fraction), height: SettingsTheme.Metrics.sliderTrackHeight)
                    Circle()
                        .fill(isDragging ? SettingsTheme.accentPressed : (isHovering ? SettingsTheme.accentHover : Color.white))
                        .frame(width: SettingsTheme.Metrics.sliderThumb, height: SettingsTheme.Metrics.sliderThumb)
                        .offset(x: geo.size.width * fraction - SettingsTheme.Metrics.sliderThumb / 2)
                }
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            position = positionFor(x: value.location.x, width: geo.size.width)
                        }
                        .onEnded { _ in isDragging = false }
                )
            }
            .frame(height: SettingsTheme.Metrics.sliderThumb)

            Text(valueLabel(position))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(SettingsTheme.label)
                .frame(minWidth: 46, alignment: .trailing)
        }
    }

    private func positionFor(x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return range.lowerBound }
        let clampedX = min(max(0, x), width)
        let span = Double(range.upperBound - range.lowerBound)
        let newValue = Double(range.lowerBound) + Double(clampedX / width) * span
        return min(max(range.lowerBound, Int(newValue.rounded())), range.upperBound)
    }
}

/// Styled dropdown (`Menu`) for the JVoice monochrome theme.
struct MonoComboField<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]

    private var currentLabel: String {
        options.first(where: { $0.value == selection })?.label ?? ""
    }

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button(option.label) {
                    selection = option.value
                }
            }
        } label: {
            HStack {
                Text(currentLabel)
                    .font(.system(size: 12))
                    .foregroundColor(SettingsTheme.textPrimary)
                    .lineLimit(1)   // long device names truncate instead of wrapping
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(SettingsTheme.headerLabel)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(SettingsTheme.controlRest)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(SettingsTheme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        // `.borderlessButton` drops this label's box and adds a second chevron (macOS 26);
        // a plain button menu draws the label exactly as styled above.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
    }
}

/// Read-only styled text row for displaying a file path, truncated in the middle.
struct MonoPathField: View {
    let path: String

    var body: some View {
        Text(path)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(rgb: 0x0A0A0A))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(SettingsTheme.border, lineWidth: 1)
            )
    }
}
