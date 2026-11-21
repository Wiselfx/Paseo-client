#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One list control for every provider (UX spec §4.2): a row per level, in the provider's
/// order, the current level checked. The Faster↔Smarter slider is gone.
///
/// The provider's levels, verbatim: Default first, then one row per reported option.
struct AgentThinkingPage: View {
    let options: [ProviderThinkingOption]
    let effectiveId: String?
    let isProviderLoading: Bool
    let onChoose: (String?) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Space.md) {
                RowGroup {
                    ListRow(
                        title: "Default",
                        subtitle: "Use the provider's level for this model",
                        accessory: .checkmark(effectiveId == nil)
                    ) {
                        onChoose(nil)
                    }
                    ForEach(options) { option in
                        RowDivider()
                        ListRow(
                            title: option.label, subtitle: option.description,
                            accessory: effectiveId == option.id
                                ? ListRow.Accessory.checkmark(true)
                                : (option.isDefault == true
                                    ? ListRow.Accessory.badge("Default")
                                    : ListRow.Accessory.none)
                        ) {
                            onChoose(option.id)
                        }
                    }
                }
                .padding(.horizontal, Space.lg)
                if options.isEmpty {
                    Text(
                        isProviderLoading
                            ? "Waiting for this provider's model list…"
                            : "This model reports no thinking levels."
                    )
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, Space.lg)
                }
            }
        }
    }
}
#endif
