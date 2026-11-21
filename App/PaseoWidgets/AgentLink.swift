import SwiftUI
import WidgetKit

/// Wraps a row in the agent's deep link through the existing `paseo://` routes, or shows
/// it unlinked when the link cannot be built. Titles are private either way.
struct AgentLink<Content: View>: View {
    let agent: GlanceMirror.Agent
    let content: Content

    init(_ agent: GlanceMirror.Agent, @ViewBuilder content: () -> Content) {
        self.agent = agent
        self.content = content()
    }

    var body: some View {
        Group {
            if let url = GlanceMirror.deepLink(for: agent) {
                Link(destination: url) { content }
            } else {
                content
            }
        }
        .privacySensitive()
    }
}
