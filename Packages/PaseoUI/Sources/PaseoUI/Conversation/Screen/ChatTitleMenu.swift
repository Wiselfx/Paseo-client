#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The agent's title pill and the menu it opens, in PLAN §RH order: jump, find, rename, copy id,
/// divider, archive. A struct of its own so the header's scroll-hide state does not re-run the
/// menu or the workspace lookup behind the pill's second line.
///
/// **Reads:** `store.agent?.title`, `store.agent?.workspaceId`, `controller.outlineAvailable`.
struct ChatTitleMenu: View {
    let store: ConversationStore
    let controller: ChatController

    var body: some View {
        Menu {
            if controller.outlineAvailable {
                Button("Jump to message…", systemImage: "list.bullet.indent") {
                    controller.sheet = .turnNav
                }
            }
            Button("Search in conversation", systemImage: "magnifyingglass") {
                controller.openFind(anchor: nil)
            }
            Button("Media in this chat", systemImage: "photo.on.rectangle") {
                controller.sheet = .media
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
            // The Claude header: one sans line, and the workspace line only when it fits on one
            // line. A truncated second line under the title was the "ugly" the user saw; the
            // workspace stays reachable in this menu (H2 §3). The bar's height is constant: the
            // title block is shorter than `ShellHeader`'s 48 pt either way.
            // A small chevron says the pill opens a menu; without it the title read as static text.
            HStack(spacing: Space.xs) {
                ViewThatFits(in: .horizontal) {
                    VStack(alignment: .center, spacing: Space.xs) {
                        headerTitle
                        if let workspaceLine {
                            headerWorkspace(workspaceLine)
                        }
                    }
                    headerTitle
                }
                Image(systemName: "chevron.down")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
                    .accessibilityHidden(true)
            }
            // N6 C: the pill takes the height its text needs at every Dynamic Type size, so the two
            // lines never draw over each other. No fixed height anywhere on this path.
            .fixedSize(horizontal: false, vertical: true)
            // The title sits in a pill (N1 D): a solid fill and a hairline border, hugging the title
            // up to the room between the two buttons, then truncating. Upstream: none (user directive).
            .padding(.horizontal, Space.md)
            .frame(minHeight: Metrics.hitSize)
            .background(Palette.panel, in: Capsule())
            .overlay { Capsule().strokeBorder(Palette.cardBorder, lineWidth: 1) }
            // Breathing room under the status bar, above the pill (D1 §1).
            .padding(.top, Space.xs)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(.rect)
        }
        .accessibilityLabel("Agent menu, \(store.agent?.title ?? "Agent")")
    }

    /// The title line: semibold sans, one line (H2 §3).
    private var headerTitle: some View {
        Text(store.agent?.title ?? "Agent")
            .font(.paseo(.headline))
            .lineLimit(1)
    }

    private func headerWorkspace(_ line: String) -> some View {
        Text(line)
            .font(.paseo(.caption))
            .foregroundStyle(Palette.secondaryInk)
            .lineLimit(1)
    }

    /// `workspace · branch`, small and secondary under the agent title.
    private var workspaceLine: String? {
        let session = controller.session
        guard
            let workspaceId = store.agent?.workspaceId,
            let workspace = session.workspaceDirectory.workspace(id: workspaceId)
        else { return nil }
        let title = Self.workspaceTitle(workspace)
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
