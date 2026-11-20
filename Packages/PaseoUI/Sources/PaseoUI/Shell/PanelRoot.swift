#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The panel's root: it resolves the workspace descriptor in its own body, so the shell body
/// never reads the directory (R5 §4.1).
struct PanelRoot: View {
    let session: HostSession
    let workspaceId: String?
    let currentAgentId: String?
    let initialTerminalId: String?
    let onSelectAgent: (String) -> Void
    let onNewAgent: (WorkspaceDescriptor) -> Void
    let onMentionInChat: (String) -> Void

    var body: some View {
        WorkspacePanel(
            session: session,
            workspace: workspaceId.flatMap { session.workspaceDirectory.workspace(id: $0) },
            currentAgentId: currentAgentId,
            onSelectAgent: onSelectAgent,
            onNewAgent: onNewAgent,
            onMentionInChat: onMentionInChat,
            initialTerminalId: initialTerminalId)
    }
}
#endif
