#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// A session that does not exist yet (UX-SPEC §3). It is the conversation surface, not a sheet:
/// the workspace name in the header, the butterfly over a serif greeting while nothing has been
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

    /// The composer's focus (E1 §1): a plain flag, because the composer's field is a
    /// `UITextView` under SwiftUI and nothing focusable is bound to a `@FocusState`.
    @State private var composerFocused = false

    /// The shell's drawer, nil outside the shell. The sidebar button toggles through it (N3 F).
    @Environment(\.shellDrawer) private var shellDrawer

    /// The draft's page: the stage (greeting, or the pending bubble) with the header floating over
    /// it, then the workspace line and the composer — or the Add project action when the host has
    /// no workspace at all (§3.1). The draft has no scroll content, so only the header is a bar
    /// (D1 §1).
    var body: some View {
        HomeHeroLayout {
            ShellHeader(leading: .sidebar(toggleSidebar)) {
                Text(workspaceTitle)
                    .font(.paseo(.title))
                    .lineLimit(1)
                    // The header is a 48 pt bar (`HomeHeroMetrics.headerHeight`) and the launch frame
                    // reserves exactly that, so the title must not make the row taller: this is bar
                    // chrome, and bar labels keep their height like UIKit's do. Without the cap the
                    // title's line box passes 48 pt at the largest text sizes and the hero shifts a
                    // few points on the launch → draft hand-off (H4 §1).
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityIdentifier("draft.workspace")
            } trailing: {
                if let onOpenPanel {
                    GlassIconButton(
                        systemName: "sidebar.right", label: "Open workspace panel",
                        action: onOpenPanel)
                }
            }
        } hero: {
            DraftStage(
                pendingPrompt: draft.pendingPrompt, onTapOutside: { composerFocused = false })
        } footer: {
            if needsProject {
                DraftAddProjectAction(onAddProject: onAddProject)
            } else {
                DraftWorkspaceLine(session: session, draft: draft)
                // The one composer (R6 §5): the draft's card is `ComposerView` in `.draft` mode — a
                // one-line pill at rest, the two-row card once it has focus, text, an attachment or
                // an error. Send hands the prompt to the shell, which creates the agent and swaps
                // the conversation in.
                ComposerView(
                    draft: draft, session: session, onSubmit: onSubmit, focused: $composerFocused)
                .padding(.bottom, Space.sm)
            }
        }
        // No background here: the shell's rounded card is the canvas (UX-SPEC §1.1).
        .foregroundStyle(Palette.ink)
        .tint(Palette.ink)
        .task { await loadCatalogue() }
        .onChange(of: session.agentControl.providers) { _, _ in seedIfNeeded() }
    }

    /// The sidebar button toggles, as the chat header's does (N1 B, N3 F): it closes the sidebar
    /// when the sidebar is already on screen, and otherwise opens it. Upstream: none (user directive).
    private func toggleSidebar() {
        if let shellDrawer {
            shellDrawer.toggle(.sidebar)
        } else {
            onOpenSidebar()
        }
    }

    /// No workspaces at all: nothing can be created yet, so the hero asks for a project instead
    /// of offering a composer (§3.1).
    private var needsProject: Bool {
        session.workspaceDirectory.hasLoaded && session.workspaceDirectory.workspaces.isEmpty
    }

    private var workspaceTitle: String {
        DraftWorkspaceLine.workspaceTitle(for: draft, in: session)
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
