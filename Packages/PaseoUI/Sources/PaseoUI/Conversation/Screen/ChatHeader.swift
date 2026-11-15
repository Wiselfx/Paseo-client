#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The conversation's top chrome: the 48 pt header and the find bar, both in the screen's top
/// safe-area bar. Only this struct reads `controller.headerHidden`, so hiding the header
/// re-evaluates it (and the bar it draws) and nothing in the transcript (R-1, H2 §3).
///
/// **Layout:** the bar keeps its height in both states; the header only *renders* translated and
/// faded. The transcript's top inset is therefore constant, and hiding the header cannot shift a
/// single row.
struct ChatTopChrome: View {
    let store: ConversationStore
    let controller: ChatController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Never hide chrome from VoiceOver.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    /// The header's laid-out height: the slide distance. Measured, not hard-coded, so Dynamic Type
    /// and the two-line title still leave the bar completely.
    @State private var headerHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            if controller.find.isOpen {
                ChatFindBarView(store: store, controller: controller)
            }
        }
    }

    /// Everything that keeps the bar on screen whatever the transcript did: find, a sheet or a
    /// dialog the bar opened, and VoiceOver (H2 §3).
    private var pinned: Bool {
        controller.find.isOpen || controller.sheet != nil || controller.showContextSheet
            || controller.showFullScreenComposer || controller.openFilePath != nil
            || controller.renamingAgent || controller.archiveConfirm
            || controller.pendingRewind != nil || voiceOverEnabled
    }

    private var hidden: Bool { controller.headerHidden && !pinned }

    private var header: some View {
        ChatHeaderBar(store: store, controller: controller)
            .background { backdrop }
            .offset(y: hidden && !reduceMotion ? -(headerHeight + Space.xs) : 0)
            .opacity(hidden ? 0 : 1)
            .animation(hideAnimation, value: hidden)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if abs(height - headerHeight) > 0.5 { headerHeight = height }
            }
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }

    /// The bar's backdrop (N1 C): a solid `Palette.background` fill that extends under the status
    /// bar, so scrolled content is cut off cleanly at the top of the screen. No blur and no fade.
    /// It goes with the header when the header hides (H2 §3).
    private var backdrop: some View {
        Palette.background
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Reduce Motion keeps the fade (opacity is allowed) and drops the slide.
    private var hideAnimation: Animation? {
        reduceMotion
            ? Motion.fade.resolved(reduceMotion: true)
            : Motion.header.resolved(reduceMotion: false)
    }
}

/// The conversation's 48 pt bar (R4 `ShellHeader`) and the agent's title menu.
///
/// **Reads:** `store.agent?.title`, `store.agent?.workspaceId`, `store.isRunning` (the archive
/// confirmation's copy), `store.turns` / `store.promptOutline.prompts` (whether "Jump to
/// message…" is offered). Everything else comes from `controller` state.
struct ChatHeaderBar: View {
    @Bindable var store: ConversationStore
    @Bindable var controller: ChatController
    /// The shell's drawer, nil outside the shell. The sidebar button toggles through it (N1 B).
    @Environment(\.shellDrawer) private var shellDrawer

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
        // Upstream rewind.tooltip, en.ts:2011. A context menu cannot show upstream's warning header,
        // so the dialog carries rewind.warning (en.ts:2012) as its message.
        .confirmationDialog(
            "Rewind to this message",
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
            Text("This action cannot be undone")
        }
    }

    /// `ShellHeader.Leading` is nested in the generic, so the value is built *inside* a generic
    /// builder: naming `ShellHeader<EmptyView, EmptyView>.Leading` at the property level would pin
    /// the header's generic parameters.
    private func makeHeaderBar<Title: View, Trailing: View>(
        @ViewBuilder title: @escaping () -> Title, @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        let leading: ShellHeader<Title, Trailing>.Leading
        if let onOpenSidebar = controller.onOpenSidebar {
            leading = .sidebar(toggleSidebar(open: onOpenSidebar))
        } else if let onBack = controller.onBack {
            leading = .back(onBack)
        } else {
            leading = .none
        }
        return ShellHeader(leading: leading, title: title, trailing: trailing)
    }

    /// The sidebar button toggles (N1 B): it closes the sidebar when the sidebar is already on
    /// screen, and otherwise opens it through the shell's own action. `ShellDrawer.toggle` runs the
    /// same motion, haptic and commit as the open path. Upstream: none (user directive).
    private func toggleSidebar(open: @escaping () -> Void) -> () -> Void {
        let drawer = shellDrawer
        return {
            if let drawer {
                drawer.toggle(.sidebar)
            } else {
                open()
            }
        }
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
            ViewThatFits(in: .horizontal) {
                VStack(alignment: .center, spacing: 1) {
                    headerTitle
                    if let workspaceLine {
                        headerWorkspace(workspaceLine)
                    }
                }
                headerTitle
            }
            // The title sits in a pill (N1 D): a solid fill and a hairline border, hugging the title
            // up to the room between the two buttons, then truncating. Upstream: none (user directive).
            .padding(.horizontal, Space.md)
            .frame(minHeight: Metrics.hitSize)
            .background(Palette.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.cardBorder, lineWidth: 1))
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
