#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The provider's models, the current one checked, the provider default badged.
struct AgentModelPage: View {
    let models: [AgentModelDefinition]
    let currentModelId: String?
    let isProviderLoading: Bool
    let onPick: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Space.md) {
                if models.isEmpty {
                    VStack(spacing: Space.sm) {
                        if isProviderLoading { ProgressView().controlSize(.small) }
                        Text(
                            isProviderLoading
                                ? "Loading models from this provider…"
                                : "No models reported by this provider"
                        )
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                    }
                    .padding(.top, Space.xxl)
                } else {
                    RowGroup {
                        ForEach(models.enumerated(), id: \.element.id) { index, model in
                            ListRow(
                                title: model.label,
                                subtitle: model.description,
                                accessory: currentModelId == model.id
                                    ? ListRow.Accessory.checkmark(true)
                                    : (model.isDefault == true
                                        ? ListRow.Accessory.badge("Default")
                                        : ListRow.Accessory.none)
                            ) {
                                onPick(model.id)
                            }
                            if index < models.count - 1 { RowDivider() }
                        }
                    }
                    .padding(.horizontal, Space.lg)
                    Text("Model ids are provider-defined; the list comes from the host's catalogue.")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, Space.lg)
                }
            }
        }
    }
}
#endif
