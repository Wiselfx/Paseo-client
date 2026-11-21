#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The options of one select feature, the current one checked. "None" appears only while a
/// value is set, and picking it clears the feature.
struct AgentFeatureSelectPage: View {
    /// Nil when the agent no longer reports this feature.
    let select: AgentFeature.Select?
    let onPick: (_ featureId: String, _ value: String?) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Space.md) {
                if let select {
                    RowGroup {
                        if select.value != nil {
                            ListRow(title: "None") {
                                onPick(select.id, nil)
                            }
                            RowDivider()
                        }
                        ForEach(select.options.enumerated(), id: \.element.id) { index, option in
                            ListRow(
                                title: option.label, subtitle: option.description,
                                accessory: select.value == option.id
                                    ? ListRow.Accessory.checkmark(true)
                                    : (option.isDefault == true
                                        ? ListRow.Accessory.badge("Default")
                                        : ListRow.Accessory.none)
                            ) {
                                onPick(select.id, option.id)
                            }
                            if index < select.options.count - 1 { RowDivider() }
                        }
                    }
                    .padding(.horizontal, Space.lg)
                } else {
                    Text("This feature is gone — the agent changed its feature set.")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.top, Space.xxl)
                }
            }
        }
    }
}
#endif
