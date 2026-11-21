#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The agent's modes, the current one checked.
struct AgentModePage: View {
    let modes: [AgentMode]
    let currentModeId: String?
    let onPick: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Space.md) {
                RowGroup {
                    ForEach(modes.enumerated(), id: \.element.id) { index, mode in
                        ListRow(
                            title: mode.label, subtitle: mode.description,
                            accessory: .checkmark(currentModeId == mode.id)
                        ) {
                            onPick(mode.id)
                        }
                        if index < modes.count - 1 { RowDivider() }
                    }
                }
                .padding(.horizontal, Space.lg)
                if modes.isEmpty {
                    Text("This agent reports no modes.")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, Space.lg)
                }
            }
        }
    }
}
#endif
