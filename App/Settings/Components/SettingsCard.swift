import SwiftUI
import DesignKit

/// A Settings card (MacStats design language): an uppercase `.caption2` section label, then
/// the content, on a faint tinted surface with a hairline and continuous corners — the
/// window's material shows through.
struct SettingsCard<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content
        }
        .padding(Design.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }
}
