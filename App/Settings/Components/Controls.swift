import AppKit
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

/// A native pop-up menu over labelled options that fills its card's width, so the popups in a
/// column line up (SwiftUI's `.menu` picker keeps its own width and floats centred).
struct MenuPicker<T: Hashable>: NSViewRepresentable {
    @Binding var selection: T
    let options: [(value: T, label: String)]

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.chosen(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        (button.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail   // long device names
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        button.isEnabled = context.environment.isEnabled   // `.disabled(…)` (the audio menus for GIF)
        let titles = options.map(\.label)
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        if let index = options.firstIndex(where: { $0.value == selection }) { button.selectItem(at: index) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: MenuPicker
        init(_ parent: MenuPicker) { self.parent = parent }
        @objc func chosen(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index].value
        }
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
