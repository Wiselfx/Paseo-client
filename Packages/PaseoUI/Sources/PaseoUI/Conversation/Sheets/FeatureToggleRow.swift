#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One boolean feature: its label, its description (or tooltip) and a switch. The switch shows
/// the snapshot's value; a flip is reported through `onChange` and lands back through the store.
struct FeatureToggleRow: View {
    let toggle: AgentFeature.Toggle
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(toggle.label)
                    .font(.paseo(.body))
                if let detail = toggle.description {
                    Text(detail)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let tooltip = toggle.tooltip {
                    Text(tooltip)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Space.sm)
            Toggle(
                "",
                isOn: Binding(
                    get: { toggle.value },
                    set: { newValue in onChange(newValue) })
            )
            .labelsHidden()
            .tint(Palette.toggleTint)
            .accessibilityLabel(toggle.label)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}
#endif
