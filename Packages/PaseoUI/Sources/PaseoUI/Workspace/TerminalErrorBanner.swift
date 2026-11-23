#if canImport(UIKit)
import SwiftUI

/// An error is a banner with a retry (PLAN §RI 22); reopening the directory clears it on
/// success, so dismiss and retry do the same thing on the store side. It floats over the stage
/// as a failure-tinted glass card (`TerminalOverlayLayer`), so it never resizes the terminal.
struct TerminalErrorBanner: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    private func announce() {
        AccessibilityNotification.Announcement(message).post()
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.glyph(.small, weight: .medium))
                .foregroundStyle(Palette.failureInk)
                .accessibilityHidden(true)
            Text(message)
                .font(.paseo(.footnote, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                // Breathing room for two lines at large text sizes; one line still sits inside
                // the 44 pt row the buttons set.
                .padding(.vertical, Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Try again", action: onRetry)
                .font(.paseo(.footnote, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .buttonStyle(.plain)
                .frame(minHeight: TerminalChrome.hit)
                .contentShape(.rect)
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(.glyph(.small, weight: .medium))
                .foregroundStyle(Palette.failureInk)
                .buttonStyle(.plain)
                .frame(width: TerminalChrome.hit, height: TerminalChrome.hit)
                .contentShape(.rect)
        }
        .padding(.leading, Space.md)
        .terminalGlass(
            .rect(cornerRadius: Radius.lg), tint: Palette.failureInk.opacity(TerminalChrome.failureTintOpacity)
        )
        .accessibilityElement(children: .contain)
        // Once when it appears, and again only when the error itself changes.
        .onChange(of: message, initial: true) { announce() }
    }
}
#endif
