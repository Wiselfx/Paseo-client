#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The conversation's 48 pt bar (R4 `ShellHeader`) around the agent's title menu (`ChatTitleMenu`),
/// with the rename, archive and rewind confirmations.
///
/// **Reads:** `store.isRunning` (the archive confirmation's copy). The title, workspace line and
/// the "Jump to message…" gate are read by `ChatTitleMenu`. Everything else comes from
/// `controller` state.
struct ChatHeaderBar: View {
    @Bindable var store: ConversationStore
    @Bindable var controller: ChatController
    /// True while the header is hidden on scroll: only the title pill slides up and fades (N6 B).
    var titleHidden: Bool = false
    /// The shell's drawer, nil outside the shell. The sidebar button toggles through it (N1 B).
    @Environment(\.shellDrawer) private var shellDrawer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The title pill's laid-out height: the slide distance. Measured so Dynamic Type sizes leave
    /// the pill completely.
    @State private var titleHeight: CGFloat = 0

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
            item: $controller.pendingRewind,
            titleVisibility: .visible
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
        return ShellHeader(
            leading: leading, title: title, trailing: trailing, alignsControlsToTop: true)
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
        makeHeaderBar(title: { hideableTitle }) {
            if let onOpenPanel = controller.onOpenPanel {
                GlassIconButton(
                    systemName: "sidebar.right", label: "Open workspace panel", action: onOpenPanel)
            }
        }
    }

    /// The title pill with the scroll-hide motion (N6 B): it slides up by its own height and fades,
    /// and stops taking touches and VoiceOver focus while hidden. The bar's layout does not change.
    private var hideableTitle: some View {
        ChatTitleMenu(store: store, controller: controller)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if abs(height - titleHeight) > 0.5 { titleHeight = height }
            }
            .offset(y: titleHidden && !reduceMotion ? -(titleHeight + Space.xs) : 0)
            .opacity(titleHidden ? 0 : 1)
            .allowsHitTesting(!titleHidden)
            .accessibilityHidden(titleHidden)
    }
}
#endif
