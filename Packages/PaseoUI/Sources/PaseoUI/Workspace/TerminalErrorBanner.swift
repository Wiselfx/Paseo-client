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
            .rect(cornerRadius: Radius.lg), tint: Palette.failureInk.opacity(0.18)
        )
        .accessibilityElement(children: .contain)
        .onAppear(perform: announce)
    }
}
#endif
