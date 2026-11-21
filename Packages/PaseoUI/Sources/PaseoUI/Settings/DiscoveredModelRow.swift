#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One discovered model: label, Default and Unavailable chips, and its ID.
struct DiscoveredModelRow: View {
    let model: AgentModelDefinition

    var body: some View {
        let unavailable = model.isSelectable == false
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(model.label)
                        .font(.paseo(.body))
                        .foregroundStyle(unavailable ? Palette.secondaryInk : Palette.ink)
                        .lineLimit(1)
                    if model.isDefault == true {
                        Text("Default")
                            .font(.paseo(.caption2, weight: .semibold))
                            .foregroundStyle(Palette.secondaryInk)
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, 5)
                            .background(Palette.chip, in: .capsule)
                    }
                    if unavailable {
                        Text("Unavailable")
                            .font(.paseo(.caption2, weight: .semibold))
                            .foregroundStyle(Palette.failureInk)
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, 5)
                            .background(Palette.chip, in: .capsule)
                    }
                }
                Text(model.id)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Space.sm)
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}
#endif
