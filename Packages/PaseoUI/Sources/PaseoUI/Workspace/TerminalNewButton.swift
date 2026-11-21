#if canImport(UIKit)
import SwiftUI

/// The "New" chip at the end of the chip bar; shows a spinner while the daemon creates the
/// terminal.
struct TerminalNewButton: View {
    let isCreating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isCreating {
                    ProgressView().controlSize(.mini).tint(Palette.secondaryInk)
                } else {
                    Image(systemName: "plus")
                        .font(.glyph(.small, weight: .medium))
                }
                Text("New").font(.paseo(.footnote))
            }
            .padding(.horizontal, Space.md)
            .frame(minHeight: 44)
            .foregroundStyle(Palette.ink)
            .overlay {
                Capsule().strokeBorder(Palette.cardBorder, lineWidth: 0.5)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(isCreating)
        .accessibilityLabel("New terminal")
    }
}
#endif
