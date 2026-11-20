#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Extracted pieces

/// The slash-command and mention menus over the card. The one composer view that reads the draft
/// on every keystroke: it needs the query, and nothing else in the composer does.
struct ComposerMenus: View {
    let store: ConversationStore
    let controller: ChatController
    @Binding var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let text = store.draft
        let slash = controller.slashQuery(in: text)
        let mentionOpen = ChatMentions.query(in: text) != nil
        let showsMentions =
            mentionOpen && (!controller.mentionMatches.isEmpty || controller.mentionIndex.isBuilding)
        VStack(alignment: .leading, spacing: 0) {
            if let slash {
                SlashMenu(controller: controller, query: slash, onPick: { command in
                    store.draft = "/" + command.name + " "
                    focused = true
                })
                .padding(.bottom, 6)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
            if showsMentions {
                MentionMenu(
                    rows: controller.mentionMatches, isBuilding: controller.mentionIndex.isBuilding
                ) { row in
                    controller.handleMentionPick(row)
                    focused = true
                }
                .padding(.bottom, 6)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: slash != nil)
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: showsMentions)
    }
}
#endif
