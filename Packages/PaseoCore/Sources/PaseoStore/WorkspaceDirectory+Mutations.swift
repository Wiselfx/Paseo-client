import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Pin, project rename, base branch, and archive undo for `WorkspaceDirectory`. Kept in an
/// extension so the main file stays small. Capability checks happen here once per call; wire
/// types live in `PaseoProtocol/WorkspaceMutations.swift`.
@MainActor
extension WorkspaceDirectory {

    // MARK: Project rename

    /// Renames a project. `customName` empty or nil clears the override (the daemon reverts to
    /// the derived folder name). The daemon answers with the effective name; the row is updated
    /// locally on acceptance.
    @discardableResult
    public func renameProject(_ projectId: String, to customName: String?) async -> Bool {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = (trimmed?.isEmpty == false) ? trimmed : nil
        do {
            let response = try await client.send(
                ProjectRenameRequest(projectId: projectId, customName: effective))
            guard response.accepted else {
                setActionError(response.error ?? "The daemon rejected the rename.")
                return false
            }
            renameProjectLocally(projectId, customName: response.customName)
            setActionError(nil)
            return true
        } catch {
            setActionError(paseoStoreErrorText(error))
            return false
        }
    }

    // MARK: Pin / Unpin

    /// Pins or unpins a workspace. Optimistic with rollback on failure. The daemon answers with
    /// the effective `pinnedAt` (nil after an unpin).
    @discardableResult
    public func setPinned(_ workspaceId: String, _ pinned: Bool) async -> Bool {
        guard supportsWorkspacePinning else {
            setActionError("This daemon cannot pin workspaces.")
            return false
        }
        guard workspaces.contains(where: { $0.id == workspaceId }) else {
            setActionError("Workspace not found.")
            return false
        }
        let previous = workspaces.first(where: { $0.id == workspaceId })?.pinnedAt

        // Optimistic: pin immediately; the daemon's response confirms or rolls back.
        setPinLocally(workspaceId, pinnedAt: pinned ? Self.nowTimestamp() : nil)
        do {
            let response = try await client.send(
                WorkspacePinSetRequest(workspaceId: workspaceId, pinned: pinned))
            guard response.accepted else {
                setPinLocally(workspaceId, pinnedAt: previous ?? nil)
                setActionError(response.error ?? "The daemon rejected the pin change.")
                return false
            }
            setPinLocally(workspaceId, pinnedAt: pinned ? response.pinnedAt : nil)
            setActionError(nil)
            return true
        } catch {
            setPinLocally(workspaceId, pinnedAt: previous ?? nil)
            setActionError(paseoStoreErrorText(error))
            return false
        }
    }

    // MARK: Base branch

    /// Sets the workspace's base branch (used for ahead/behind and the default diff comparison).
    /// `baseRef` is a full ref, e.g. `refs/heads/main`.
    @discardableResult
    public func setBaseBranch(_ workspaceId: String, baseRef: String) async -> Bool {
        guard supportsWorkspaceBaseBranch else {
            setActionError("This daemon cannot set the base branch.")
            return false
        }
        let trimmed = baseRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setActionError("A base branch is required.")
            return false
        }
        do {
            let response = try await client.send(
                WorkspaceBaseBranchSetRequest(workspaceId: workspaceId, baseRef: trimmed))
            guard response.accepted else {
                setActionError(response.error ?? "The daemon rejected the base branch.")
                return false
            }
            setActionError(nil)
            return true
        } catch {
            setActionError(paseoStoreErrorText(error))
            return false
        }
    }

    // MARK: Archive with undo

    /// Archives a workspace optimistically: the row disappears immediately, the daemon archives on
    /// its own schedule. On failure the row is restored and `actionError` is set. When the daemon
    /// pushed nothing unusual, `actionError` is nil. On success the snapshot is kept for
    /// `undoArchive`. When the daemon cannot undo archives, falls back to a plain archive.
    ///
    /// The daemon may answer `canceled: true` (another undo won); the row is then kept (restored)
    /// and this returns false with `actionError` set to the daemon's reason.
    @discardableResult
    public func archiveWorkspaceWithUndo(_ workspaceId: String) async -> Bool {
        guard supportsWorkspaceArchiveUndo else {
            // Fallback: plain archive (send + remove on success).
            return await archiveWorkspace(workspaceId)
        }
        guard let snapshot = snapshotAndRemoveWorkspace(id: workspaceId) else {
            setActionError("Workspace not found.")
            return false
        }
        do {
            let response = try await client.send(ArchiveWorkspaceRequest(workspaceId: workspaceId))
            if response.canceled == true {
                restoreWorkspace(snapshot)
                lastArchiveSnapshot = nil
                setActionError(response.error ?? "The archive was canceled.")
                return false
            }
            if let error = response.error {
                restoreWorkspace(snapshot)
                lastArchiveSnapshot = nil
                setActionError(error)
                return false
            }
            lastArchiveSnapshot = snapshot
            setActionError(nil)
            return true
        } catch {
            restoreWorkspace(snapshot)
            lastArchiveSnapshot = nil
            setActionError(paseoStoreErrorText(error))
            return false
        }
    }

    /// Undoes the latest archived workspace. The daemon cancels the archive if it is still running
    /// on its side, otherwise restores the workspace (and unarchives the agents that archive took
    /// down); the row is re-inserted locally if the daemon's `workspace_update` push has not
    /// re-added it by the time this returns.
    @discardableResult
    public func undoArchive(_ workspaceId: String) async -> Bool {
        guard supportsWorkspaceArchiveUndo else {
            setActionError("This daemon cannot undo archives.")
            return false
        }
        do {
            let response = try await client.send(WorkspaceArchiveUndoRequest(workspaceId: workspaceId))
            guard response.accepted else {
                setActionError(response.error ?? "The archive could not be undone.")
                return false
            }
            if let snapshot = lastArchiveSnapshot,
                snapshot.id == workspaceId,
                !workspaces.contains(where: { $0.id == workspaceId })
            {
                restoreWorkspace(snapshot)
            }
            lastArchiveSnapshot = nil
            setActionError(nil)
            return true
        } catch {
            setActionError(paseoStoreErrorText(error))
            return false
        }
    }

    // MARK: Helpers

    /// Daemon-shaped ISO-8601 with fractional seconds, matching `ConversationStore.nowTimestamp`.
    private static func nowTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
