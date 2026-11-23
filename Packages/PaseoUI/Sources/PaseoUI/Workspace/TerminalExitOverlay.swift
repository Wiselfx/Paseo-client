#if canImport(UIKit)
import SwiftUI

/// The card over the top of the stage once a terminal's process has ended: why it ended, with
/// Reattach (a fresh emulator and subscription) and Dismiss. It sits on the top edge so the
/// terminal's final output stays readable, and it is announced to VoiceOver when it appears.
struct TerminalExitOverlay: View {
    let message: String
    let onReattach: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.md))
            : AnyLayout(HStackLayout(spacing: Space.md))
        layout {
            Image(systemName: "power")
                .font(.glyph(.regular, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityHidden(true)
            Text(message)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.ink)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.sm) {
                Button("Reattach", action: onReattach)
                    .buttonStyle(.paseoPrimary())
                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .buttonStyle(.plain)
                    .frame(width: TerminalChrome.hit, height: TerminalChrome.hit)
                    .contentShape(.rect)
            }
        }
        .padding(Space.md)
        .terminalGlass(.rect(cornerRadius: Radius.lg))
        .accessibilityElement(children: .contain)
        // Once when it appears, and again only when it now describes another ending (a switch
        // between two ended terminals keeps the card up).
        .onChange(of: message, initial: true) { announce() }
    }

    private func announce() {
        AccessibilityNotification.Announcement(message).post()
    }
}
#endif
