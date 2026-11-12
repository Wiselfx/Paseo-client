import SwiftUI
import WidgetKit

// MARK: - Agents widget (Phase E G15, plan §3.1)

// Home Screen sizes plus the Lock Screen accessory families. One static entry from
// the App Group snapshot — no polling, no refresh budget spent. The "Updated"
// label ticks itself (`Text(date, style: .relative)`), so staleness is honest.
// Titles are `.privacySensitive()`; the snapshot already redacts them when the
// reader hid names. Every row deep-links through the existing `paseo://` routes.

struct GlanceTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(GlanceEntry(date: Date(), snapshot: GlanceMirror.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let entry = GlanceEntry(date: Date(), snapshot: GlanceMirror.load())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct GlanceEntry: TimelineEntry {
    let date: Date
    let snapshot: GlanceMirror?
}

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

private struct AgentsWidgetView: View {
    let entry: GlanceEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var agents: [GlanceMirror.Agent] { entry.snapshot?.agents ?? [] }
    private var needing: [GlanceMirror.Agent] { agents.filter(\.requiresAttention) }

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .accessoryRectangular:
            rectangularView
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        default:
            smallView
        }
    }

    // MARK: Home Screen

    /// The big numeral: agents needing you, or running agents when none do.
    private var smallView: some View {
        let count = needing.isEmpty ? entry.snapshot?.runningCount ?? 0 : needing.count
        let label = needing.isEmpty ? "running" : "need you"
        let top = (needing.first ?? agents.first)
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(.system(.largeTitle, design: .serif))
                .foregroundStyle(WidgetTokens.accent)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let top {
                agentLink(top) {
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

    /// Up to 3 rows: status, title, project, relative time. Attention first.
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(agents.prefix(3))) { agent in
                agentLink(agent) {
                    HStack(spacing: 8) {
                        statusMark(for: agent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.title)
                                .font(.callout)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            if let project = agent.project {
                                Text(project)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        if let updated = agent.updatedAt {
                            Text(updated, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if let host = entry.snapshot?.hostDisplayName {
                    Text(host)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("Updated")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let captured = entry.snapshot?.capturedAt {
                    Text(captured, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Lock Screen

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(needing.count) need you · \(entry.snapshot?.runningCount ?? 0) running")
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

    private var circularView: some View {
        Gauge(value: Double(max(needing.count, 0)), in: 0...Double(max(needing.count, 1))) {
            Text("\(needing.count)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var inlineView: some View {
        Text("\(needing.count) need you · \(entry.snapshot?.runningCount ?? 0) running")
    }

    // MARK: Shared

    /// Status that survives accented rendering: shapes, not just colors (HIG).
    @ViewBuilder
    private func statusMark(for agent: GlanceMirror.Agent) -> some View {
        if renderingMode == .accented {
            Image(
                systemName: agent.requiresAttention
                    ? "exclamationmark.circle.fill" : "circle.dotted")
        } else {
            Circle()
                .fill(agent.requiresAttention ? WidgetTokens.accent : Color.secondary)
                .frame(width: 8, height: 8)
        }
    }

    private func agentLink<Content: View>(
        _ agent: GlanceMirror.Agent, @ViewBuilder content: () -> Content
    ) -> some View {
        Group {
            if let url = GlanceMirror.deepLink(for: agent) {
                Link(destination: url, label: content)
            } else {
                content()
            }
        }
        .privacySensitive()
    }
}
