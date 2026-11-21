#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Provider detail: the models the host probed for this provider. Read-only; the host owns the
/// catalogue.
struct DiscoveredModelsSection: View {
    let models: [AgentModelDefinition]
    /// Shown when `models` is empty: loading, the catalogue error, or "none discovered".
    let emptyText: String

    var body: some View {
        SettingsSectionLabel(title: "Discovered")
        RowGroup {
            if models.isEmpty {
                Text(emptyText)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.lg)
                    .frame(minHeight: 52)
            } else {
                ForEach(models.enumerated(), id: \.element.id) { index, model in
                    DiscoveredModelRow(model: model)
                    if index < models.count - 1 { RowDivider() }
                }
            }
        }
        Text("Models the host probes for this provider. Read-only; the host owns the catalogue.")
            .font(.paseo(.footnote))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, Space.lg)
    }
}
#endif
