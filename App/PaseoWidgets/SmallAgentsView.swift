import SwiftUI
import WidgetKit

/// The big numeral: agents needing you, or running agents when none do.
struct SmallAgentsView: View {
    let snapshot: GlanceMirror?

    var body: some View {
        let agents = snapshot?.agents ?? []
        let needing = agents.filter(\.requiresAttention)
        let count = needing.isEmpty ? snapshot?.runningCount ?? 0 : needing.count
        let label: LocalizedStringResource = needing.isEmpty ? "running" : "need you"
        let top = (needing.first ?? agents.first)
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(.system(.largeTitle, design: .serif))
                .foregroundStyle(WidgetTokens.accent)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let top {
                AgentLink(top) {
                    Text(top.title)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
