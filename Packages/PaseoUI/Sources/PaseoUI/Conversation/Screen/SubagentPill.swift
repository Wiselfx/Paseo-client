#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The subagents track: one quiet pill in the strip directly above the composer, where upstream
/// puts its `ComposerTrackBar` pills (`app/src/panels/agent-tracks.tsx:127`).
///
/// **Reads:** `store.subagents.items`, `session.agents` (Paseo-managed children of this agent),
/// `controller.hiddenSubagentIds`.
struct SubagentPill: View {
    @Bindable var store: ConversationStore
    let controller: ChatController

    var body: some View {
        let managed = controller.session.subagents(of: store.agentId)
        let visible = store.subagents.items.filter { !controller.hiddenSubagentIds.contains($0.id) }
        if !visible.isEmpty || !managed.isEmpty {
            SubagentTrackPill(items: visible, managed: managed) {
                controller.sheet = .subagents
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
