#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The file-viewer sheet: the agent's workspace resolved to a checkout, with a fallback while the
/// workspace directory has not loaded. Reads `store.agent` and `session.workspaceDirectory` here,
/// so `ChatSheets` itself does not depend on them.
struct ChatFileSheet: View {
    let store: ConversationStore
    let session: HostSession
    let controller: ChatController

    var body: some View {
        if let agent = store.agent,
            let workspaceId = agent.workspaceId,
            let workspace = session.workspaceDirectory.workspace(id: workspaceId)
        {
            NavigationStack {
                WorkspaceFileViewer(
                    checkout: session.checkout(for: workspace),
                    relPath: controller.openFilePath ?? "",
                    onBack: { controller.openFilePath = nil },
                    backLabel: "Files")
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        } else {
            // The agent's workspace isn't loaded (rare: directory fetch pending).
            EmptyState(
                systemImage: "exclamationmark.triangle", title: "Workspace not available",
                message: nil,
                action: (title: "Close", run: { controller.openFilePath = nil }))
                .presentationDetents([.height(240)])
        }
    }
}
#endif
