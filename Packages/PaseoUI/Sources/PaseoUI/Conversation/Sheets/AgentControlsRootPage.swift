#if canImport(UIKit)
import SwiftUI

/// The agent-controls sheet's first page: one row per control, each showing its current value
/// and opening that page. The Features row only appears when the agent reports features.
struct AgentControlsRootPage: View {
    let providerDetail: String?
    let modelValue: String
    let thinkingValue: String
    let modeValue: String
    /// Nil when the agent offers no features: the row is not shown.
    let featuresSummary: String?
    let onSelect: (ClaudeAgentControlsSheet.Page) -> Void

    var body: some View {
        VStack(spacing: Space.md) {
            RowGroup {
                ListRow(
                    title: "Model", subtitle: providerDetail,
                    accessory: .value(modelValue)
                ) { onSelect(.models) }
                RowDivider()
                ListRow(title: "Thinking", accessory: .value(thinkingValue)) { onSelect(.thinking) }
                RowDivider()
                ListRow(title: "Mode", accessory: .value(modeValue)) { onSelect(.modes) }
                if let featuresSummary {
                    RowDivider()
                    ListRow(title: "Features", accessory: .value(featuresSummary)) {
                        onSelect(.features)
                    }
                }
            }
            .padding(.horizontal, Space.lg)
        }
    }
}
#endif
