#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One config-owned custom model with its remove button.
struct CustomModelRow: View {
    let model: DaemonProviderModel
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.label)
                    .font(.paseo(.body))
                    .lineLimit(1)
                Text(model.id)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Space.sm)
            Button {
                Haptics.light()
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.failureInk)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(model.label)")
            .accessibilityIdentifier("settings.providers.custom.remove.\(model.id)")
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: 52)
    }
}
#endif
