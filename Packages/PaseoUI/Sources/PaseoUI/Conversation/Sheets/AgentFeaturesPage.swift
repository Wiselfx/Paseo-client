#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Feature switches from the snapshot: toggle rows with a switch, select rows as menus of
/// options. Unknown feature kinds are not shown.
struct AgentFeaturesPage: View {
    let toggles: [AgentFeature.Toggle]
    let selects: [AgentFeature.Select]
    let onToggle: (_ featureId: String, _ value: Bool) -> Void
    let onOpenSelect: (_ featureId: String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Space.md) {
                if toggles.isEmpty, selects.isEmpty {
                    Text("This agent doesn't offer any features.")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.top, Space.xxl)
                } else {
                    RowGroup {
                        ForEach(toggles.enumerated(), id: \.element.id) { index, toggle in
                            FeatureToggleRow(toggle: toggle) { value in
                                onToggle(toggle.id, value)
                            }
                            if index < toggles.count - 1 || !selects.isEmpty { RowDivider() }
                        }
                        ForEach(selects.enumerated(), id: \.element.id) { index, select in
                            ListRow(
                                title: select.label, subtitle: select.description,
                                accessory: .value(Self.valueLabel(select))
                            ) { onOpenSelect(select.id) }
                            if index < selects.count - 1 { RowDivider() }
                        }
                    }
                    .padding(.horizontal, Space.lg)
                }
            }
        }
    }

    private static func valueLabel(_ select: AgentFeature.Select) -> String {
        guard let value = select.value else { return "None" }
        return select.options.first(where: { $0.id == value })?.label ?? value
    }
}
#endif
