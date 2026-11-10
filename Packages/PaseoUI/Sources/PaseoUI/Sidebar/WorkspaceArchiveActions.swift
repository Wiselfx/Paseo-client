#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The payload for the "Archive worktree?" destructive confirmation: the counts to show.
struct WorktreeArchiveWarning {
    let workspace: WorkspaceDescriptor
    let message: String
}

/// The sidebar's workspace archive flow (M2.10 + PLAN §RH): a worktree risk check first, then
/// either the undo toast or the confirmation a host without undo needs — never both.
@MainActor
@Observable
final class WorkspaceArchiveActions {
    /// Set only when the host can't undo an archive: then a confirmation guards it instead.
    var pendingConfirmation: WorkspaceDescriptor?
    /// Set when a worktree-kind workspace has uncommitted or unpushed changes.
    var pendingWarning: WorktreeArchiveWarning?

    /// Entry point for the sidebar's "Archive workspace".
    func request(_ workspace: WorkspaceDescriptor, session: HostSession, toast: ToastCenter?) {
        guard workspace.workspaceKind == .worktree else {
            continueFlow(workspace, session: session, toast: toast)
            return
        }
        Task { @MainActor in
            if let message = await Self.worktreeRiskMessage(workspace, session: session) {
                pendingWarning = WorktreeArchiveWarning(
                    workspace: workspace, message: message)
            } else {
                continueFlow(workspace, session: session, toast: toast)
            }
        }
    }

    /// The destructive button of the "Archive worktree?" confirmation.
    func confirmWarning(session: HostSession, toast: ToastCenter?) {
        guard let warning = pendingWarning else { return }
        pendingWarning = nil
        archive(warning.workspace, session: session, toast: toast)
    }

    /// The destructive button of the "Archive workspace?" confirmation.
    func confirmPending(session: HostSession, toast: ToastCenter?) {
        guard let workspace = pendingConfirmation else { return }
        pendingConfirmation = nil
        archive(workspace, session: session, toast: toast)
    }

    // MARK: Flow

    /// Undo toast when the host supports it, else the confirmation dialog.
    private func continueFlow(
        _ workspace: WorkspaceDescriptor, session: HostSession, toast: ToastCenter?
    ) {
        if session.workspaceDirectory.supportsWorkspaceArchiveUndo {
            archive(workspace, session: session, toast: toast)
        } else {
            pendingConfirmation = workspace
        }
    }

    /// Archives the workspace and surfaces the outcome: an Undo toast when the host can undo,
    /// the plain confirmation otherwise.
    private func archive(
        _ workspace: WorkspaceDescriptor, session: HostSession, toast: ToastCenter?
    ) {
        let directory = session.workspaceDirectory
        let supportsUndo = directory.supportsWorkspaceArchiveUndo
        let workspaceId = workspace.id
        let name = Self.title(workspace)
        Task {
            let archived = await directory.archiveWorkspaceWithUndo(workspaceId)
            guard archived else {
                toast?.show(directory.actionError ?? "Couldn't archive the workspace.")
                return
            }
            guard supportsUndo else {
                toast?.show("Archived \(name)")
                return
            }
            toast?.show("Archived \(name)", undo: {
                Task {
                    let undone = await directory.undoArchive(workspaceId)
                    guard !undone else { return }
                    toast?.show(directory.actionError ?? "Couldn't undo the archive.")
                }
            })
        }
    }

    /// The workspace title, or the branch when there is no title — the row's own wording.
    private static func title(_ workspace: WorkspaceDescriptor) -> String {
        if let title = workspace.title,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return title
        }
        return workspace.branch ?? workspace.name
    }

    // MARK: Worktree risk

    /// The risk line for archiving a worktree, or nil when it is clean.
    ///
    /// Reads checkout status (T11). Fails closed: an unreadable status warns with a generic
    /// line rather than archiving silently. Unpushed commits are `aheadOfOrigin` (vs the
    /// upstream ref), falling back to `aheadBehind` (vs the base ref) when the branch has no
    /// upstream — otherwise a never-pushed branch would look clean. The file count is the
    /// working-tree diff's (T11); when it can't be loaded the line is "Uncommitted changes".
    private static func worktreeRiskMessage(
        _ workspace: WorkspaceDescriptor, session: HostSession
    ) async -> String? {
        let checkout = session.checkout(for: workspace)
        await checkout.loadStatus()
        guard let status = checkout.status else {
            return "This worktree's status could not be read."
        }
        var parts: [String] = []
        if status.isDirty == true {
            if let files = await uncommittedFileCount(checkout: checkout, session: session) {
                parts.append(files == 1 ? "1 uncommitted file" : "\(files) uncommitted files")
            } else {
                parts.append("Uncommitted changes")
            }
        }
        let unpushed = status.aheadOfOrigin ?? status.aheadBehind?.ahead ?? 0
        if unpushed > 0 {
            parts.append(unpushed == 1 ? "1 unpushed commit" : "\(unpushed) unpushed commits")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The working-tree diff's file count (T11), or nil when it can't be determined.
    /// Loads the working diff fresh: a snapshot left by the Changes page may be a
    /// "vs base" comparison, whose file count is not uncommitted work. On the binary
    /// pipeline the files arrive asynchronously, so a fresh load may have no count yet —
    /// nil, and the caller falls back to "Uncommitted changes". The load also leaves the
    /// Changes page on the working-tree comparison.
    private static func uncommittedFileCount(
        checkout: CheckoutStore, session: HostSession
    ) async -> Int? {
        let extras = session.gitExtras.workspace(for: checkout)
        await extras.loadWorkingDiff()
        if extras.diffTooLarge { return nil }
        switch extras.diffPhase {
        case .loading, .failed, .idle: return nil
        case .ready: return extras.filesChanged > 0 ? extras.filesChanged : nil
        }
    }
}
#endif
