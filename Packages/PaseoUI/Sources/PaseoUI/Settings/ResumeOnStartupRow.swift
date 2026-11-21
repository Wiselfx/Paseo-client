#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Upstream's restart-recovery card (`restart-recovery-card.tsx`): title with an info tip,
/// the hint, then Edit and the switch. Edit edits the prompt the daemon appends to a
/// resumed agent's message.
struct ResumeOnStartupRow: View {
    @Binding var isOn: Bool
    let canEdit: Bool
    let isDisabled: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text("Resume agents after restart")
                        .font(.paseo(.body))
                    SettingsInfoButton(
                        title: "Resume agents after restart",
                        info:
                            "Reopen agents that were working when the host stopped and send the resume prompt. Applies after graceful restarts and crashes."
                    )
                }
                Text("Continue interrupted work automatically.")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.sm)
            Button("Edit", action: onEdit)
                .font(.paseo(.callout))
                .disabled(!canEdit || isDisabled)
                .accessibilityLabel("Edit prompt")
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Palette.toggleTint)
                .disabled(isDisabled)
                .accessibilityLabel("Resume agents after restart")
                .accessibilityIdentifier("settings.config.Resume agents after restart")
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(minHeight: 44)
    }
}
#endif
