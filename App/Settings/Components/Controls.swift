import SwiftUI

/// A native slider over an `Int` stop index within `range`, with its value on the right.
/// Callers map the index to a domain value (e.g. `OverlayDismissScale`) and back.
struct StopSlider: View {
    @Binding var position: Int
    let range: ClosedRange<Int>
    let valueLabel: (Int) -> String

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: Binding(get: { Double(position) },
                                  set: { position = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .controlSize(.small)
            Text(valueLabel(position))
                .font(.callout).monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)
        }
    }
}

/// A native pop-up menu (`Picker(.menu)`) over labelled options, full width.
struct MenuPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A file path shown read-only in a field-like tint, truncated in the middle.
struct PathField: View {
    let path: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text(path)
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Color.primary.opacity(0.05)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}
