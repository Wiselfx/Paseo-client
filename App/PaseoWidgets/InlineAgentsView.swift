import SwiftUI
import WidgetKit

struct InlineAgentsView: View {
    let snapshot: GlanceMirror?

    var body: some View {
        let needing = (snapshot?.agents ?? []).filter(\.requiresAttention)
        Text("\(needing.count) need you · \(snapshot?.runningCount ?? 0) running")
    }
}
