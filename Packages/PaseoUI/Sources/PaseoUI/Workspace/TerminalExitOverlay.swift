#if canImport(UIKit)
import SwiftUI

/// The card over the stage once a terminal's process has ended: why it ended, with Reattach (a
/// fresh emulator and subscription) and Dismiss.
struct TerminalExitOverlay: View {
    let message: String
    let onReattach: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Space.md) {
            Text(message)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            HStack(spacing: Space.sm) {
                Button(action: onReattach) {
                    Text("Reattach")
                }
                .buttonStyle(.paseoPrimary())
                Button(action: onDismiss) {
                    Text("Dismiss")
                }
                .buttonStyle(.paseoSecondary)
            }
        }
        .padding(Space.xl)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Palette.cardBorder, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.25), radius: 16, y: 4)
        .padding(.horizontal, Space.xxxl)
    }
}
#endif
