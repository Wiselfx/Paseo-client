#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Upstream's fixed header slot (strategy-native.tsx:69-74: height 32): the spinner while the
/// operation runs, "Try again" on failure, empty otherwise (the app's one retry wording).
struct TranscriptHistorySlot: View {
    let store: ConversationStore
    let history: HistoryStartController
    let onRetry: () -> Void

    var body: some View {
        let status = history.state.status
        Group {
            if store.isLoadingOlder || status == .loading || status == .settling {
                ProgressView()
                    .controlSize(.small)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Loading earlier messages")
            } else if status == .failed, store.timeline.hasOlder {
                Button("Try again", action: onRetry)
                    .buttonStyle(.paseoSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: TranscriptView.historyStartSlotHeight)
    }
}
#endif
