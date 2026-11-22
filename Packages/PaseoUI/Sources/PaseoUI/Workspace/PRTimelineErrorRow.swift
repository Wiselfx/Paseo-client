#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The activity timeline's failure line, with Try again.
struct PRTimelineErrorRow: View {
    let error: PullRequestTimelineError
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Palette.failureInk)
            Text(error.message.isEmpty ? fallbackMessage : error.message)
                .font(.paseo(.caption))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Try again", action: retry)
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .accessibilityLabel("Timeline error")
    }

    private var fallbackMessage: String {
        switch error.kind {
        case .notFound: "This PR is gone or your token can't see it."
        case .forbidden: "No permission to read this timeline."
        case .unknown: "The timeline is unavailable."
        }
    }
}
#endif
