#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import UIKit

/// Watches the composer's text in a body of its own (P3).
///
/// `.onChange(of: store.draft)` placed on the conversation's root view subscribed that whole
/// body to the draft, so every keystroke re-evaluated the header, the transcript's turns and the
/// turn rail. A view modifier's body is a separate value in the graph: reading the draft here
/// re-evaluates this modifier and the text field, and nothing else.
struct DraftObserver: ViewModifier {
    let store: ConversationStore
    let onDraftChange: (String) -> Void
    let onMentionQueryChange: (String?) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: store.draft) { _, newValue in onDraftChange(newValue) }
            .onChange(of: mentionQuery) { _, query in onMentionQueryChange(query) }
    }

    /// The open mention query for the current draft; nil when there is none.
    private var mentionQuery: String? { ChatMentions.query(in: store.draft) }
}
#endif
