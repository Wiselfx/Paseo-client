#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The model page of `DraftControlsSheet`: the chosen provider's models, the current one checked.
struct DraftModelPage: View {
    let models: [AgentModelDefinition]
    let selectedId: String?
    /// The provider is still probing, so an empty list may yet fill in.
    let isLoading: Bool
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if models.isEmpty {
                    VStack(spacing: 8) {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        }
                        Text(
                            isLoading
                                ? "Loading models from this provider…"
                                : "No models reported by this provider"
                        )
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                    }
                    .padding(.top, 24)
                } else {
                    RowGroup {
                        ForEach(models.enumerated(), id: \.element.id) { index, model in
                            ListRow(
                                title: model.label,
                                subtitle: model.description,
                                accessory: selectedId == model.id
                                    ? ListRow.Accessory.checkmark(true)
                                    : (model.isDefault == true
                                        ? ListRow.Accessory.badge("Default")
                                        : ListRow.Accessory.none)
                            ) {
                                onSelect(model.id)
                            }
                            if index < models.count - 1 { RowDivider() }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}
#endif
