#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The payload for the "Archive worktree?" destructive confirmation: the counts to show.
struct WorktreeArchiveWarning {
    let workspace: WorkspaceDescriptor
    let message: String
}

extension PaseoSidebar {
    /// M2.10: entry point for the sidebar's "Archive workspace" action. Worktree-kind
    /// workspaces get a risk check first; a clean worktree (or any other kind) keeps the
    /// pre-M2.10 flow.
    func requestArchive(_ workspace: WorkspaceDescriptor) {
        guard workspace.workspaceKind == .worktree else {
            continueArchiveFlow(workspace)
            return
        }
        Task { @MainActor in
            if let message = await worktreeArchiveRiskMessage(workspace) {
                workspacePendingArchiveWarning = WorktreeArchiveWarning(
                    workspace: workspace, message: message)
            } else {
                continueArchiveFlow(workspace)
            }
        }
    }

    /// The pre-M2.10 flow: undo toast when the host supports it, else the confirmation dialog.
    func continueArchiveFlow(_ workspace: WorkspaceDescriptor) {
        if session.workspaceDirectory.supportsWorkspaceArchiveUndo {
            archiveWorkspace(workspace)
        } else {
            workspacePendingArchive = workspace
        }
    }

    /// The risk line for archiving a worktree, or nil when it is clean.
    ///
    /// Reads checkout status (T11). Fails closed: an unreadable status warns with a generic
    /// line rather than archiving silently. Unpushed commits are `aheadOfOrigin` (vs the
    /// upstream ref), falling back to `aheadBehind` (vs the base ref) when the branch has no
    /// upstream — otherwise a never-pushed branch would look clean. The file count is the
    /// working-tree diff's (T11); when it can't be loaded the line is "Uncommitted changes".
    func worktreeArchiveRiskMessage(_ workspace: WorkspaceDescriptor) async -> String? {
        let checkout = session.checkout(for: workspace)
        await checkout.loadStatus()
        guard let status = checkout.status else {
            return "This worktree's status could not be read."
        }
        var parts: [String] = []
        if status.isDirty == true {
            if let files = await uncommittedFileCount(checkout: checkout) {
                parts.append(files == 1 ? "1 uncommitted file" : "\(files) uncommitted files")
            } else {
                parts.append("Uncommitted changes")
            }
        }
        let unpushed = status.aheadOfOrigin ?? status.aheadBehind?.ahead ?? 0
        if unpushed > 0 {
            parts.append(
                unpushed == 1 ? "1 unpushed commit" : "\(unpushed) unpushed commits")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The working-tree diff's file count (T11), or nil when it can't be determined.
    /// Loads the working diff fresh: a snapshot left by the Changes page may be a
    /// "vs base" comparison, whose file count is not uncommitted work. On the binary
    /// pipeline the files arrive asynchronously, so a fresh load may have no count yet —
    /// nil, and the caller falls back to "Uncommitted changes". The load also leaves the
    /// Changes page on the working-tree comparison.
    private func uncommittedFileCount(checkout: CheckoutStore) async -> Int? {
        let extras = session.gitExtras.workspace(for: checkout)
        await extras.loadWorkingDiff()
        if extras.diffTooLarge { return nil }
        switch extras.diffPhase {
        case .loading, .failed, .idle: return nil
        case .ready: return extras.filesChanged > 0 ? extras.filesChanged : nil
        }
    }

    /// Archives a workspace (confirmed first when the host can't undo; else the undo toast is the
    /// safety net) and surfaces the outcome as a bottom toast with an Undo for ~5 s.
    func archiveWorkspace(_ workspace: WorkspaceDescriptor) {
        let supportsUndo = session.workspaceDirectory.supportsWorkspaceArchiveUndo
        Task {
            let archived = await session.workspaceDirectory.archiveWorkspaceWithUndo(workspace.id)
            guard archived else {
                showToast(
                    session.workspaceDirectory.actionError ?? "Couldn't archive the workspace.")
                return
            }
            if supportsUndo {
                showArchiveToast(for: workspace)
            } else {
                showToast("Archived \(workspaceTitle(workspace))")
            }
        }
    }

    func showArchiveToast(for workspace: WorkspaceDescriptor) {
        let name = workspaceTitle(workspace)
        let token = UUID()
        undoToastToken = token
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            undoToast = (workspace.id, name)
        }
        Haptics.selection()
        UIAccessibility.post(notification: .announcement, argument: "Workspace archived: \(name). Undo is available.")
        Task {
            try? await Task.sleep(for: .seconds(5))
            guard undoToastToken == token else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                undoToast = nil
            }
        }
    }

    func showToast(_ text: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = nil }
        }
    }
}
#endif
