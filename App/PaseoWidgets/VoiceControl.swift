import AppIntents
import SwiftUI
import WidgetKit

struct VoiceControl: ControlWidget {
    static let kind = "com.wiselfx.paseoclient.open-conversation"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            title: "Open conversation",
            image: Image(systemName: "message")
        ) {
            ControlWidgetButton(action: WidgetVoiceIntent()) {
                Label("Open conversation", systemImage: "message")
            }
        }
    }
}
