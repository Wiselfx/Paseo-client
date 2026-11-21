#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Upstream's idle-cleanup card (`idle-runtime-cleanup-card.tsx`): title with an info tip, the
/// hint, then the switch. Only the switch is disabled while the config is unavailable, so the
/// info tip stays reachable.
struct SettingsToggleRow: View {
    let title: String
    let hint: String
    let info: String
    @Binding var isOn: Bool
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text(title)
                        .font(.paseo(.body))
                    SettingsInfoButton(title: title, info: info)
                }
                Text(hint)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.sm)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Palette.toggleTint)
                .disabled(isDisabled)
                .accessibilityLabel(title)
                .accessibilityIdentifier("settings.config." + title)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(minHeight: 44)
    }
}
#endif
