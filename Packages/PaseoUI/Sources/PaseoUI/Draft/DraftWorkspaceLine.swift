#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The "in <workspace>" line above the composer: a menu that moves the draft to another
/// workspace of this host. Hidden until the directory has any.
struct DraftWorkspaceLine: View {
    let session: HostSession
    let draft: DraftSession

    var body: some View {
        if !session.workspaceDirectory.groups.isEmpty {
            Menu {
                ForEach(session.workspaceDirectory.groups) { group in
                    Section(projectTitle(group.project)) {
                        ForEach(group.workspaces) { workspace in
                            Button {
                                draft.move(toWorkspace: workspace.id, cwd: workspace.cwd)
                            } label: {
                                Text(Self.title(of: workspace))
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("in \(workspaceTitle)")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.glyph(.small, weight: .semibold))
                }
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .contentShape(.rect)
            }
            .accessibilityLabel("Workspace, \(workspaceTitle)")
            .accessibilityIdentifier("draft.workspaceLine")
            .paseoFeedback(.selection, trigger: draft.workspaceId)
            .padding(.bottom, 4)
        }
    }

    private var workspaceTitle: String {
        Self.workspaceTitle(for: draft, in: session)
    }

    /// The draft's workspace as the header and this line name it. Reads main-actor state
    /// (`DraftSession`, `HostSession`), so it is isolated like the view that calls it.
    @MainActor
    static func workspaceTitle(for draft: DraftSession, in session: HostSession) -> String {
        guard let workspaceId = draft.workspaceId,
            let workspace = session.workspaceDirectory.workspace(id: workspaceId)
        else { return "New session" }
        return title(of: workspace)
    }

    static func title(of workspace: WorkspaceDescriptor) -> String {
        if let title = workspace.title,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return title
        }
        return workspace.branch ?? workspace.name
    }

    private func projectTitle(_ project: WorkspaceProjectDescriptor) -> String {
        let custom = project.projectCustomName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom, !custom.isEmpty { return custom }
        return project.projectDisplayName
    }
}
#endif
