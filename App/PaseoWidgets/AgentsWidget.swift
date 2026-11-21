import SwiftUI
import WidgetKit

// MARK: - Agents widget (Phase E G15, plan §3.1)

// Home Screen sizes plus the Lock Screen accessory families. One static entry from
// the App Group snapshot — no polling, no refresh budget spent. The "Updated"
// label ticks itself (`Text(date, style: .relative)`), so staleness is honest.
// Titles are `.privacySensitive()`; the snapshot already redacts them when the
// reader hid names. Every row deep-links through the existing `paseo://` routes.

struct AgentsWidget: Widget {
    static let kind = "com.wiselfx.paseoclient.agents"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlanceTimelineProvider()) { entry in
            AgentsWidgetView(entry: entry)
        }
        .configurationDisplayName("Agents")
        .description("Who needs you, at a glance.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryCircular, .accessoryInline,
        ])
    }
}
