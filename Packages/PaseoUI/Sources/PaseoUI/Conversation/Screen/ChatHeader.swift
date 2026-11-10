#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The conversation's 48 pt bar (R4 `ShellHeader`) and the agent's title menu.
///
/// **Reads:** `store.agent?.title`, `store.agent?.workspaceId`, `store.isRunning` (the archive
/// confirmation's copy), `store.turns` / `store.promptOutline.prompts` (whether "Jump to
/// message…" is offered). Everything else comes from `controller` state.
struct ChatHeaderBar: View {
    @Bindable var store: ConversationStore
    @Bindable var controller: ChatController

    var body: some View {
        headerBar
        .alert("Rename agent", isPresented: $controller.renamingAgent) {
            TextField("Name", text: $controller.renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                controller.commitRename()
            }
        }
        .confirmationDialog(
            "Archive agent?",
            isPresented: $controller.archiveConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                Task { await controller.archiveNow() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                store.isRunning
                    ? "This agent is still running. Archiving it will stop the agent."
                    : "The agent will disappear from your list.")
        }
        .confirmationDialog(
            "Rewind to this message?",
            isPresented: Binding(
                get: { controller.pendingRewind != nil },
                set: { if !$0 { controller.pendingRewind = nil } }),
            titleVisibility: .visible,
            presenting: controller.pendingRewind
        ) { rewind in
            Button(rewindScopeTitle(rewind.scope), role: .destructive) {
                controller.performPendingRewind(rewind)
                controller.pendingRewind = nil
            }
            Button("Cancel", role: .cancel) { controller.pendingRewind = nil }
        } message: { _ in
            Text("This action cannot be undone.")
        }
    }

    /// `ShellHeader.Leading` is nested in the generic, so the value is built *inside* a generic
    /// builder: naming `ShellHeader<EmptyView, EmptyView>.Leading` at the property level would pin
    /// the header's generic parameters.
    private func makeHeaderBar<Title: View, Trailing: View>(
        @ViewBuilder title: () -> Title, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let leading: ShellHeader<Title, Trailing>.Leading
        if let onOpenSidebar = controller.onOpenSidebar {
            leading = .sidebar(onOpenSidebar)
        } else if let onBack = controller.onBack {
            leading = .back(onBack)
        } else {
            leading = .none
        }
        return ShellHeader(leading: leading, title: title, trailing: trailing)
    }

    private var headerBar: some View {
        makeHeaderBar(title: { titleMenu }) {
            if let onOpenPanel = controller.onOpenPanel {
                GlassIconButton(systemName: "sidebar.right", label: "Open workspace panel") {
                    onOpenPanel()
                }
            }
        }
    }

    /// The title menu, in PLAN §RH order: jump, find, rename, copy id, divider, archive.
    private var titleMenu: some View {
        Menu {
            if controller.outlineAvailable {
                Button("Jump to message…", systemImage: "list.bullet.indent") {
                    controller.sheet = .turnNav
                }
            }
            Button("Search in conversation", systemImage: "magnifyingglass") {
                controller.openFind(anchor: nil)
            }
            Button("Rename…", systemImage: "pencil") {
                controller.beginRename()
            }
            Button("Copy agent ID", systemImage: "doc.on.doc") {
                controller.copyAgentId()
            }
            Divider()
            Button("Archive agent", systemImage: "archivebox", role: .destructive) {
                controller.archiveAgent()
            }
        } label: {
            VStack(alignment: .center, spacing: 1) {
                Text(store.agent?.title ?? "Agent")
                    .font(.paseo(.title))
                    .lineLimit(1)
                if let workspaceLine {
                    Text(workspaceLine)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(.rect)
        }
        .accessibilityLabel("Agent menu, \(store.agent?.title ?? "Agent")")
    }

    /// `workspace · branch`, small and secondary under the agent title.
    private var workspaceLine: String? {
        let session = controller.session
        guard
            let workspaceId = store.agent?.workspaceId,
            let workspace = session.workspaceDirectory.workspace(id: workspaceId)
        else { return nil }
        let title = ChatHeaderBar.workspaceTitle(workspace)
        if let branch = workspace.branch, branch != title {
            return "\(title) · \(branch)"
        }
        return title
    }

    /// Workspace title, or the branch when there is no title.
    static func workspaceTitle(_ workspace: WorkspaceDescriptor) -> String {
        if let title = workspace.title,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return title
        }
        return workspace.branch ?? workspace.name
    }
}

#endif
