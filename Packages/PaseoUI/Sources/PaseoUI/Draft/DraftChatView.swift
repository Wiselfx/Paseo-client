#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// A session that does not exist yet (UX-SPEC §3). It is the conversation surface, not a sheet:
/// the workspace name in the header, the DSH mark over a serif greeting while nothing has been
/// sent, the workspace line and the normal composer. The first send creates the agent with the
/// text and attachments as its first turn, and the shell swaps its conversation in.
struct DraftChatView: View {
    let session: HostSession
    @Bindable var draft: DraftSession
    var onOpenSidebar: () -> Void
    var onOpenPanel: (() -> Void)?
    /// No workspaces on this host: the hero asks for a project instead of offering a composer.
    var onAddProject: () -> Void
    /// The composer's send; the shell owns creation (D2 §3).
    var onSubmit: (DraftSubmission) -> Void

    @FocusState private var focused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        column
            .task { await loadCatalogue() }
            .onChange(of: session.agentControl.providers) { _, _ in seedIfNeeded() }
    }

    /// The draft's page: header, then the greeting or the pending bubble, then the workspace line
    /// and the composer — or the Add project action when the host has no workspace at all (§3.1).
    private var column: some View {
        VStack(spacing: 0) {
            header
            stage
            if needsProject {
                addProjectAction
            } else {
                workspaceLine
                composer
            }
        }
        // No background here: the shell's rounded card is the canvas (UX-SPEC §1.1).
        .foregroundStyle(Palette.ink)
        .tint(Palette.ink)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onOpenSidebar) {
                UnequalMenu().stroke(
                    Palette.ink.opacity(0.8),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                )
                .frame(width: 18, height: 17)
                .frame(width: 44, height: 44)
            }
            .glassEffect(in: .circle)
            .accessibilityLabel("Open sidebar")

            Text(workspaceTitle)
                .font(.paseo(.title))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("draft.workspace")

            if let onOpenPanel {
                Button(action: onOpenPanel) {
                    Image(systemName: "sidebar.right")
                        .font(.glyph(.regular, weight: .medium))
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
    }

    // MARK: Stage

    /// The greeting fades out the moment the first prompt leaves, replaced by the pending bubble
    /// that the new conversation will carry (§3.2).
    private var stage: some View {
        ZStack {
            if let pending = draft.pendingPrompt {
                VStack(spacing: 0) {
                    ClaudeUserBubble(text: pending, isPending: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    Spacer(minLength: 0)
                }
            } else {
                ClaudeHomeHero()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Tapping the page outside the composer drops the keyboard (V5 §2). Simultaneous, so the
        // workspace-line menu and the hero's own controls still take their taps.
        .simultaneousGesture(TapGesture().onEnded { focused = false })
        .animation(Motion.disclosure.resolved(reduceMotion: reduceMotion), value: draft.pendingPrompt)
    }

    private var addProjectAction: some View {
        VStack(spacing: 10) {
            Button(action: onAddProject) {
                Label("Add project", systemImage: "folder.badge.plus")
                    .font(.paseo(.callout, weight: .medium))
                    .foregroundStyle(Palette.background)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Palette.ink, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("draft.addProject")
        }
        .padding(.bottom, 40)
    }

    // MARK: Workspace line

    @ViewBuilder private var workspaceLine: some View {
        if !session.workspaceDirectory.groups.isEmpty {
            Menu {
                ForEach(session.workspaceDirectory.groups) { group in
                    Section(projectTitle(group.project)) {
                        ForEach(group.workspaces) { workspace in
                            Button {
                                Haptics.selection()
                                draft.move(toWorkspace: workspace.id, cwd: workspace.cwd)
                            } label: {
                                Text(title(of: workspace))
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
            .padding(.bottom, 4)
        }
    }

    /// No workspaces at all: nothing can be created yet, so the hero asks for a project instead
    /// of offering a composer (§3.1).
    private var needsProject: Bool {
        session.workspaceDirectory.hasLoaded && session.workspaceDirectory.workspaces.isEmpty
    }

    private var workspaceTitle: String {
        guard let workspaceId = draft.workspaceId,
            let workspace = session.workspaceDirectory.workspace(id: workspaceId)
        else { return "New session" }
        return title(of: workspace)
    }

    private func title(of workspace: WorkspaceDescriptor) -> String {
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

    // MARK: Composer

    /// The one composer (R6 §5): the draft's card is `ComposerView` in `.draft` mode — a one-line
    /// pill at rest, the two-row card once it has focus, text, an attachment or an error. Send
    /// hands the prompt to the shell, which creates the agent and swaps the conversation in.
    private var composer: some View {
        ComposerView(
            draft: draft, session: session, onSubmit: onSubmit, focused: $focused)
        .padding(.bottom, 8)
    }

    // MARK: Catalogue

    private func loadCatalogue() async {
        let catalog = session.agentControl
        let needsLoad: Bool
        switch catalog.phase {
        case .idle, .failed: needsLoad = true
        case .loading, .ready: needsLoad = catalog.providers.isEmpty
        }
        if needsLoad {
            await catalog.loadCatalog(cwd: draft.cwd.isEmpty ? nil : draft.cwd)
        }
        seedIfNeeded()
    }

    /// Seeds once the catalogue can answer, and again if the chosen provider disappears from it
    /// or arrives without models (a provider that was still probing). A user's picks are never
    /// overwritten otherwise.
    private func seedIfNeeded() {
        let catalog = session.agentControl
        guard let providerId = draft.providerId, catalog.provider(providerId) != nil else {
            draft.seed(catalog: catalog)
            return
        }
        if draft.modelId == nil, catalog.defaultModel(forProvider: providerId) != nil {
            draft.seed(catalog: catalog)
        }
    }
}
#endif
