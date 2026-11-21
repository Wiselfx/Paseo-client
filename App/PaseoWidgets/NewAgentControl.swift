import AppIntents
import SwiftUI
import WidgetKit

struct NewAgentControl: ControlWidget {
    static let kind = "com.wiselfx.paseoclient.new-agent"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            title: "New agent",
            image: Image(systemName: "plus.message")
        ) {
            ControlWidgetButton(action: WidgetNewAgentIntent()) {
                Label("New agent", systemImage: "plus.message")
            }
        }
    }
}
