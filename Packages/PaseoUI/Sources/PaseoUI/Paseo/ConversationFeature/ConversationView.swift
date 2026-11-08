import PaseoStore
import SwiftUI

/// One agent's conversation: turns, then the composer.
public struct ConversationView: View {
    @Bindable var store: ConversationStore
    @Environment(\.openURL) private var openURL

    public init(store: ConversationStore) { self.store = store }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.turnSpacing) {
                if store.timeline.hasOlder {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await store.loadOlder() }
                }
                ForEach(store.turns) { turn in
                    TurnView(turn: turn, onOpenURL: { openURL($0) })
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .animation(.snappy(duration: 0.3), value: store.turns.map(\.id))
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background)
        .overlay { overlay }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let error = store.actionError {
                    Text(error)
                        .font(Typeset.caption)
                        .foregroundStyle(Palette.failure)
                        .transition(.opacity)
                }
                Composer(
                    text: $store.draft,
                    isRunning: store.isRunning,
                    onSend: { text in Task { await store.send(text) } },
                    onStop: { Task { await store.cancel() } })
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .navigationTitle(store.agent?.title ?? "Agent")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: store.isRunning) { wasRunning, isRunning in
            if wasRunning && !isRunning { Haptics.settle() }
        }
    }

    @ViewBuilder private var overlay: some View {
        switch store.phase {
        case .loading where store.turns.isEmpty:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.bubble", description: Text(message))
        case .ready where store.turns.isEmpty:
            ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.text.bubble.right")
        default:
            EmptyView()
        }
    }
}
