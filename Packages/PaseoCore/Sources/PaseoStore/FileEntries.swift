import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Entry operations and conflict-checked text writes on `WorkspaceFiles`, added in T15.
/// The wire is `fs.entry.create/rename/duplicate/delete` and `fs.file.write`.
///
/// Collisions and other daemon refusals come back as the daemon's `error` string, verbatim.
/// Every successful operation re-lists the affected directory afterwards.
///
/// IMPLEMENTATION TICKET: docs/tickets/T15-git-files-ops.md

/// One outcome for the text-write operation; the front panel's save path matches on it.
public enum FileWriteOutcome: Sendable, Hashable {
    /// The file was replaced. Carries the new stat the daemon returned.
    case written(modifiedAt: String, size: Int, revision: String?)
    /// `expectedModifiedAt` didn't match; carries the current modified time if the daemon sent one.
    case conflict(modifiedAt: String?)
    /// The daemon's error text.
    case failed(String)
}

public extension WorkspaceFiles {
    /// Entry capabilities, read once per host (`server_info`).
    var supportsEntryOps: Bool { entryCapabilities.supportsEntryOps }
    var supportsEntryDuplicate: Bool { entryCapabilities.supportsEntryDuplicate }
    /// `false` until `GitExtrasStore` feeds `server_info` in; gate text writes on it.
    var supportsFileEditing: Bool { entryCapabilities.supportsFileEditing }

    /// Feeds `server_info` in; called by `CheckoutStore.update(serverInfo:)`.
    internal func update(supportsEntryOps: Bool, supportsEntryDuplicate: Bool, supportsFileEditing: Bool) {
        entryCapabilities = EntryCapabilities(
            supportsEntryOps: supportsEntryOps,
            supportsEntryDuplicate: supportsEntryDuplicate,
            supportsFileEditing: supportsFileEditing)
    }

    /// Creates a file or directory inside `parentPath` (nil/empty = the workspace root).
    /// Returns the new path on success, nil with `error` set on refusal.
    @discardableResult
    func createEntry(parentPath: String?, name: String, kind: FileEntryKind) async -> String? {
        guard entryCapabilities.supportsEntryOps else {
            error = "This daemon cannot create files or folders."
            return nil
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            error = "A name is required."
            return nil
        }
        let parent = normalizedEntryPath(parentPath)
        do {
            let response = try await client.send(
                FileEntryCreateRequest(
                    cwd: cwd, parentPath: parent ?? ".", name: trimmedName, kind: kind))
            guard response.success else {
                error = response.error ?? "The daemon could not create the entry."
                return nil
            }
            error = nil
            await list(parent)
            return response.path
        } catch {
            self.error = entryErrorText(error)
            return nil
        }
    }

    /// Renames `path` to `to` — the new basename, not a full path (the wire takes `name`).
    /// Returns the new path on success, nil with `error` set on refusal.
    @discardableResult
    func rename(path: String, to name: String) async -> String? {
        guard entryCapabilities.supportsEntryOps else {
            error = "This daemon cannot rename entries."
            return nil
        }
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty, !trimmedName.isEmpty else {
            error = "A path and a new name are required."
            return nil
        }
        guard !trimmedName.contains("/") else {
            error = "Rename takes a new name, not a path. Move it with the daemon instead."
            return nil
        }
        do {
            let response = try await client.send(
                FileEntryRenameRequest(cwd: cwd, path: trimmedPath, name: trimmedName))
            guard response.success else {
                error = response.error ?? "The daemon could not rename the entry."
                return nil
            }
            error = nil
            await list(parentDirectory(of: trimmedPath))
            return response.renamedPath
        } catch {
            self.error = entryErrorText(error)
            return nil
        }
    }

    /// Duplicates `path` server-side. Returns the new path on success, nil with `error` set on refusal.
    /// Requires `features.fsEntryDuplicate`.
    @discardableResult
    func duplicate(path: String) async -> String? {
        guard entryCapabilities.supportsEntryDuplicate else {
            error = "This daemon cannot duplicate entries."
            return nil
        }
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            error = "A path is required."
            return nil
        }
        do {
            let response = try await client.send(FileEntryDuplicateRequest(cwd: cwd, path: trimmedPath))
            guard response.success else {
                error = response.error ?? "The daemon could not duplicate the entry."
                return nil
            }
            error = nil
            await list(parentDirectory(of: trimmedPath))
            return response.duplicatedPath
        } catch {
            self.error = entryErrorText(error)
            return nil
        }
    }

    /// Deletes `path` (unlink/rmdir — no trash). Irreversible; the caller confirms.
    @discardableResult
    func delete(path: String) async -> Bool {
        guard entryCapabilities.supportsEntryOps else {
            error = "This daemon cannot delete entries."
            return false
        }
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            error = "A path is required."
            return false
        }
        do {
            let response = try await client.send(FileEntryDeleteRequest(cwd: cwd, path: trimmedPath))
            guard response.success else {
                error = response.error ?? "The daemon could not delete the entry."
                return false
            }
            error = nil
            await list(parentDirectory(of: trimmedPath))
            return true
        } catch {
            self.error = entryErrorText(error)
            return false
        }
    }

    /// Writes `content` to `path`, conflict-checked against `expectedModifiedAt`.
    /// Never overwrites blindly: on mismatch the daemon answers with the current version.
    /// Requires `features.workspaceFileEditing`.
    @discardableResult
    func write(path: String, content: String, expectedModifiedAt: String) async -> FileWriteOutcome {
        guard entryCapabilities.supportsFileEditing else {
            error = "This daemon cannot edit files."
            return .failed("This daemon cannot edit files.")
        }
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return .failed("A path is required.") }
        do {
            let response = try await client.send(
                FileWriteRequest(
                    cwd: cwd, path: trimmedPath, content: content,
                    expectedModifiedAt: expectedModifiedAt))
            switch response.result {
            case .written(let modifiedAt, let size, let revision):
                error = nil
                await list(parentDirectory(of: trimmedPath))
                return .written(modifiedAt: modifiedAt, size: size, revision: revision)
            case .conflict(let version):
                return .conflict(modifiedAt: version.modifiedAt)
            case .error(let message):
                // The daemon's text, verbatim.
                error = message
                return .failed(message)
            }
        } catch {
            let message = entryErrorText(error)
            self.error = message
            return .failed(message)
        }
    }

    // MARK: Internals

    private func parentDirectory(of path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slash = trimmed.lastIndex(of: "/") else { return nil }
        let parent = trimmed[..<slash]
        return parent.isEmpty ? "/" : String(parent)
    }

    private func normalizedEntryPath(_ path: String?) -> String? {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private func entryErrorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}
