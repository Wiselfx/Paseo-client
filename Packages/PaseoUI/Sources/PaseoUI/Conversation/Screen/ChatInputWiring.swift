#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Wiring

/// The draft, the queue and the turn boundary: things that change while you type or while the
/// agent works. A modifier's body is its own value in the graph, so a keystroke re-evaluates this
/// and the composer's text field — not the transcript.
struct ChatInputWiring: ViewModifier {
    let store: ConversationStore
    let controller: ChatController
    @Binding var focused: Bool

    /// Inline images decode at the window's width in pixels: the scale comes from the environment
    /// (`UIScreen.main` is deprecated on iOS 26) and the width from this view's geometry (D1 §4).
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .task { await controller.loadSlashCommands() }
            .onChange(of: store.activeTurnId) { oldId, newId in
                guard newId == nil, oldId != nil else { return }
                // The anchor's job (hold your message at the top while the answer arrives) is
                // done. Clearing it first lets a queued message arm its own runway.
                controller.anchoringToAnswer = false
                controller.flushQueuedMessage()
                // Follow comes back from the transcript's idle rule, not from here: the reader
                // may have scrolled away from the end while the answer ran.
            }
            .draftObserver(
                store: store,
                onDraftChange: { newValue in
                    controller.scheduleDraftSave(newValue)
                    controller.feedMascot(.userActivity(at: .now))
                },
                onMentionQueryChange: { query in controller.handleMentionQuery(query) })
            .onAppear {
                controller.seedSavedDraft()
                controller.displayScale = displayScale
                controller.dictation.onDraft = { [store] text in store.draft = text }
            }
            .onChange(of: displayScale) { _, scale in controller.displayScale = scale }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                controller.contentWidth = width
            }
    }
}
#endif
