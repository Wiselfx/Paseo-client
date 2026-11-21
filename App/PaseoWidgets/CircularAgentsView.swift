import SwiftUI
import WidgetKit

struct CircularAgentsView: View {
    let snapshot: GlanceMirror?

    var body: some View {
        let needing = (snapshot?.agents ?? []).filter(\.requiresAttention)
        Gauge(value: Double(max(needing.count, 0)), in: 0...Double(max(needing.count, 1))) {
            Text("\(needing.count)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .accessibilityLabel("\(needing.count) need you")
    }
}
