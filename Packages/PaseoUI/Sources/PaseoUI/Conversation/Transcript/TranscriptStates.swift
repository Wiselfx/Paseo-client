#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Loading, empty and failed states, a whole viewport tall so a centred state stays centred.
/// It reads `store.phase` itself, so a phase change re-evaluates this view and not the transcript.
struct TranscriptStates: View {
    let store: ConversationStore
    let controller: ChatController

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch store.phase {
                case .loading:
                    LoadingState()
                case .failed(let message):
                    VStack(spacing: 0) {
                        InlineBanner(
                            .failure, title: message, systemImage: "exclamationmark.triangle",
                            action: ("Try again", retry))
                            .padding(16)
                        Spacer(minLength: 0)
                    }
                case .ready:
                    // An existing agent with nothing in it is not a new session (audit C #22).
                    EmptyState(systemImage: nil, title: "No messages yet")
                }
            }
            .containerRelativeFrame(.vertical)
        }
        .scrollDisabled(true)
        .simultaneousGesture(TapGesture().onEnded { controller.dismissKeyboard() })
    }

    private func retry() {
        Task { await store.load() }
    }
}
#endif
