import SwiftUI
import WidgetKit

// MARK: - Paseo widgets entry point (Phase E G15)

// A WidgetKit bundle: the Agents widget plus the two Control Center controls.
// Built but not shipped: the target is not embedded in the app (D1), so the
// default IPA is unchanged.

@main
struct PaseoWidgets: WidgetBundle {
    var body: some Widget {
        AgentsWidget()
        NewAgentControl()
        VoiceControl()
    }
}
