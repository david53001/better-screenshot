import SwiftUI

/// The "info tip" (SF `info.circle`) placed next to a Settings row label. Hovering it
/// (after a short delay, so a quick pass-through doesn't pop it) reveals a card with a title,
/// a plain-language explanation, and an optional "e.g. …" example. Uses the normal arrow cursor —
/// deliberately not a help/`?` cursor.
struct InfoTip: View {
    private let title: String
    private let explanation: String
    private let example: String?

    @State private var isHovering = false
    @State private var showTooltip = false

    init(title: String, explanation: String, example: String? = nil) {
        self.title = title
        self.explanation = explanation
        self.example = example
    }

    init(help: HelpText) {
        self.title = help.title
        self.explanation = help.explanation
        self.example = help.example
    }

    var body: some View {
        Image(systemName: "info.circle")
            .font(.callout)
            .foregroundStyle(isHovering ? .primary : .secondary)
            .contentShape(Circle())
            .onHover { hovering in
                isHovering = hovering
                guard hovering else {
                    showTooltip = false
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    // Guard against a quick pass-through: only show if still hovering.
                    if isHovering {
                        showTooltip = true
                    }
                }
            }
            .popover(isPresented: $showTooltip, arrowEdge: .bottom) {
                tooltipCard
            }
    }

    /// Fixed width + vertical fixedSize on every Text: a popover proposes no width of
    /// its own, so without them each line was cut to one row with "…".
    private var tooltipCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(explanation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let example {
                Text("e.g. " + example)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(width: 280, alignment: .leading)
        .padding(12)
    }
}
