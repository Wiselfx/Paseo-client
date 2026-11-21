import SwiftUI
import WidgetKit

struct RectangularAgentsView: View {
    let snapshot: GlanceMirror?

    var body: some View {
        let agents = snapshot?.agents ?? []
        let needing = agents.filter(\.requiresAttention)
        VStack(alignment: .leading, spacing: 2) {
            Text("\(needing.count) need you · \(snapshot?.runningCount ?? 0) running")
                .font(.headline)
            if let top = needing.first ?? agents.first {
                Text(top.title)
                    .font(.caption)
                    .lineLimit(1)
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
