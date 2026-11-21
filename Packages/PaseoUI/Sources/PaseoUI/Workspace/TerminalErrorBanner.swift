#if canImport(UIKit)
import SwiftUI

/// An error is a banner with a retry (PLAN §RI 22); reopening the directory clears it on
/// success, so dismiss and retry do the same thing on the store side.
struct TerminalErrorBanner: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        InlineBanner(
            .failure, title: message,
            action: ("Try again", onRetry),
            onDismiss: onDismiss)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.xs)
    }
}
#endif
