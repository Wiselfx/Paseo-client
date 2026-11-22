#if canImport(UIKit)
import SwiftUI

/// Avatar leading, the inverted New session pill trailing, sized to its label and never
/// truncated (§0.3, §2.5). The host lives in Settings only.
struct SidebarFooter: View {
    /// The avatar's letter.
    let initial: String
    let onOpenSettings: () -> Void
    let onNewSession: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenSettings) {
                Text(initial)
                    .font(.paseo(.title, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .glassEffect(in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            Spacer(minLength: 8)

            // The shell settles the drawer and plays the one haptic (PLAN §RH).
            Button(action: onNewSession) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.glyph(.regular, weight: .semibold))
                    Text("New session")
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .buttonStyle(.paseoPrimary())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("New session")
        }
        .padding(.horizontal, Space.lg)
        .padding(.bottom, 6)
    }
}
#endif
