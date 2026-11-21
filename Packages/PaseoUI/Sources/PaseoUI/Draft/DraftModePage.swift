#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The mode page of `DraftControlsSheet`: the chosen provider's modes, the current one checked.
struct DraftModePage: View {
    let modes: [AgentMode]
    let selectedId: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                RowGroup {
                    ForEach(modes.enumerated(), id: \.element.id) { index, mode in
                        ListRow(
                            title: mode.label, subtitle: mode.description,
                            accessory: .checkmark(selectedId == mode.id)
                        ) {
                            onSelect(mode.id)
                        }
                        if index < modes.count - 1 { RowDivider() }
                    }
                }
                .padding(.horizontal, 16)
                if modes.isEmpty {
                    Text("This provider reports no modes.")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, 16)
                }
            }
        }
    }
}
#endif
