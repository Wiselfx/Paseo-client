#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Routes the conversation's `ClaudeChatSheet` item to the sheet it names. The sheets that open
/// another screen dismiss through `controller.sheet = nil` first.
struct ChatSheetRouter: View {
    let item: ClaudeChatSheet
    let store: ConversationStore
    let session: HostSession
    @Bindable var controller: ChatController

    var body: some View {
        switch item {
        case .controls:
            ClaudeAgentControlsSheet(session: session, store: store)
        case .subagents:
            ChatSubagentsSheet(
                session: session, parentAgentId: store.agentId, subagents: store.subagents,
                hiddenIds: $controller.hiddenSubagentIds,
                onOpenAgent: { agentId in
                    controller.sheet = nil
                    controller.onOpenAgent?(agentId)
                })
        case .backgroundWork:
            ChatBackgroundWorkSheet(backgroundWork: store.backgroundWork)
        case .media:
            ChatMediaSheet(store: store)
        case .turnNav:
            ChatTurnNavSheet(
                store: store, items: controller.outlineItems,
                activeSeq: store.promptOutline.activeSeq
            ) { seq in
                controller.sheet = nil
                controller.jumpToPrompt(seq)
            }
        }
    }
}
#endif
