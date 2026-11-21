import SwiftUI
import WidgetKit

/// Routes the widget family to its layout. The container background lives here, per
/// family: WidgetKit shows a placeholder for a widget that declares none, and the
/// Lock Screen families need the accessory background, not the Home Screen fill.
struct AgentsWidgetView: View {
    let entry: GlanceEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallAgentsView(snapshot: entry.snapshot)
            case .systemMedium:
                MediumAgentsView(snapshot: entry.snapshot)
            case .accessoryRectangular:
                RectangularAgentsView(snapshot: entry.snapshot)
            case .accessoryCircular:
                CircularAgentsView(snapshot: entry.snapshot)
            case .accessoryInline:
                InlineAgentsView(snapshot: entry.snapshot)
            default:
                SmallAgentsView(snapshot: entry.snapshot)
            }
        }
        .containerBackground(for: .widget) {
            if family.isAccessory {
                AccessoryWidgetBackground()
            } else {
                Rectangle().fill(.fill.tertiary)
            }
        }
    }
}
