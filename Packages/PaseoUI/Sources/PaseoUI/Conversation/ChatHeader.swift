#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

extension ClaudeChatView {
    // MARK: Header

    var header: some View {
        HStack(spacing: 8) {
            if let onOpenSidebar {
                Button(action: onOpenSidebar) {
                    UnequalMenu().stroke(
                        ClaudePalette.ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                    .frame(width: 18, height: 17)
                    .frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Open sidebar")
            } else if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
            Menu {
                if store.turns.filter({ $0.userMessage != nil }).count >= ClaudeTurnRail.minimumTurns {
                    Button("Jump to message…", systemImage: "list.bullet.indent") {
                        sheet = .turnNav
                    }
                }
                Button("Search in conversation", systemImage: "magnifyingglass") {
                    openFind()
                }
                Button("Rename…", systemImage: "pencil") {
                    beginRename()
                }
                Button("Copy agent ID", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = store.agentId
                    Haptics.selection()
                    showToast("Agent ID copied")
                }
                Divider()
                Button("Archive agent", systemImage: "archivebox", role: .destructive) {
                    archiveAgentConfirm = true
                }
            } label: {
                VStack(alignment: .center, spacing: 1) {
                    Text(store.agent?.title ?? "Agent")
                        .font(typography.serif(20, relativeTo: .headline))
                        .lineLimit(1)
                    if let workspaceLine {
                        Text(workspaceLine)
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(.rect)
            }
            .accessibilityLabel("Agent menu")
            if let onOpenPanel {
                Button(action: onOpenPanel) {
                    Image(systemName: "sidebar.right").font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Open workspace panel")
            } else {
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
        .alert("Rename agent", isPresented: $renamingAgent) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task { await store.rename(to: trimmed) }
            }
        } message: {
            Text("The name shown in the sidebar and the header.")
        }
        .confirmationDialog(
            "Archive agent?",
            isPresented: $archiveAgentConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                Task { await store.archive() }
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
                get: { pendingRewind != nil },
                set: { if !$0 { pendingRewind = nil } }),
            titleVisibility: .visible,
            presenting: pendingRewind
        ) { rewind in
            Button(rewindScopeTitle(rewind.scope), role: .destructive) {
                performPendingRewind(rewind)
                pendingRewind = nil
            }
            Button("Cancel", role: .cancel) { pendingRewind = nil }
        } message: { _ in
            Text("This action cannot be undone.")
        }
    }

    /// `workspace · branch`, small and secondary under the agent title.
    var workspaceLine: String? {
        guard
            let workspaceId = store.agent?.workspaceId,
            let workspace = session.workspaceDirectory.workspace(id: workspaceId)
        else { return nil }
        let title = workspaceTitle(workspace)
        if let branch = workspace.branch, branch != title {
            return "\(title) · \(branch)"
        }
        return title
    }

    /// Workspace title, or the branch when there is no title.
    func workspaceTitle(_ workspace: WorkspaceDescriptor) -> String {
        if let title = workspace.title,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return title
        }
        return workspace.branch ?? workspace.name
    }

    var modelLabel: String? {
        guard let agent = store.agent else { return nil }
        if let id = agent.model,
            let match = session.agentControl.models(forProvider: agent.provider).first(where: { $0.id == id })
        {
            return match.label
        }
        return session.agentControl.defaultModel(forProvider: agent.provider)?.label ?? agent.model
    }

    func newAgent(draft: String) {
        focused = false
        onNewAgent?(draft)
    }

    func openFileViewer(at path: String) {
        Haptics.selection()
        openFilePath = path
    }

    func beginRename() {
        Haptics.selection()
        renameText = store.agent?.title ?? ""
        renamingAgent = true
    }

    // MARK: Connection

    var connectionBanner: AnyView? {
        switch session.connection {
        case .reconnecting(let attempt, _):
            return AnyView(
                bannerRow("Reconnecting to host", detail: "Attempt \(attempt)"))
        case .failed:
            return AnyView(bannerRow("Disconnected", detail: nil))
        case .idle, .connecting, .connected:
            return nil
        }
    }

    func bannerRow(_ title: String, detail: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 13))
            Text(title).font(typography.sans(13, weight: .medium))
            if let detail {
                Text(detail).font(typography.sans(13)).foregroundStyle(ClaudePalette.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(ClaudePalette.secondaryInk)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(ClaudePalette.adaptive(light: 0.95, dark: 0.18), in: .rect(cornerRadius: 10))
    }

}
#endif
