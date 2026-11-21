#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The thinking page of `DraftControlsSheet`: one row per level, in the provider's order, the
/// current one checked (§4.2). "Default" means the provider's own choice for this model, which the
/// create request leaves out, so it selects `nil`.
struct DraftThinkingPage: View {
    let options: [ProviderThinkingOption]
    let selectedId: String?
    /// The provider is still probing, so an empty list may yet fill in.
    let isLoading: Bool
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                RowGroup {
                    ListRow(
                        title: "Default",
                        subtitle: "Use the provider's level for this model",
                        accessory: .checkmark(selectedId == nil)
                    ) {
                        onSelect(nil)
                    }
                    ForEach(options) { option in
                        RowDivider()
                        ListRow(
                            title: option.label, subtitle: option.description,
                            accessory: selectedId == option.id
                                ? .checkmark(true)
                                : (option.isDefault == true ? .badge("Default") : .none)
                        ) {
                            onSelect(option.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                if options.isEmpty {
                    Text(
                        isLoading
                            ? "Waiting for this provider's model list…"
                            : "This model reports no thinking levels."
                    )
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}
#endif
