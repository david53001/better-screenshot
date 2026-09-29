import SwiftUI

/// Mutually exclusive choices as a native segmented control, leading-aligned.
struct SegmentedControl<T: Hashable>: View {
    @Binding var selection: T
    let segments: [(value: T, label: String)]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Text(segment.label).tag(segment.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
