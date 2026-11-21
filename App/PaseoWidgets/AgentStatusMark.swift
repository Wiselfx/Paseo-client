import SwiftUI
import WidgetKit

/// Status that survives accented rendering and Differentiate Without Color: the symbol
/// differs, not just the color (HIG), and VoiceOver hears the attention state. The
/// snapshot carries no per-agent run state, so the quiet mark claims nothing more than
/// "no action needed".
struct AgentStatusMark: View {
    let agent: GlanceMirror.Agent

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(agent.requiresAttention ? WidgetTokens.accent : Color.secondary)
            .accessibilityLabel(
                agent.requiresAttention ? Text("Needs you") : Text("No action needed"))
    }

    private var symbol: String {
        if agent.requiresAttention { return "exclamationmark.circle.fill" }
        return renderingMode == .accented ? "circle.dotted" : "circle.fill"
    }
}
