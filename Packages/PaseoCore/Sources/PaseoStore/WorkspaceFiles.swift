import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Directory listing and file reads for one workspace. One-shot `file_explorer_request`s: list a
/// directory, read a file with a byte limit, keep the last result.
///
/// Created by `CheckoutStore.files`; views call `list`/`read`.
///
/// IMPLEMENTATION TICKET: docs/tickets/T7-workspaces-git.md
@MainActor @Observable
public final class WorkspaceFiles {
    public nonisolated let cwd: String

    public enum Phase: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    /// The directory currently shown.
    public private(set) var path: String?
    public private(set) var entries: [FileExplorerEntry] = []
    /// The last file read, if any.
    public private(set) var file: FileExplorerFile?
    public private(set) var error: String?

    /// Hard cap for inline reads. Bigger files come back truncated or refused by the daemon.
    public var maxReadBytes = 512 * 1024

    private let client: any DaemonClient

    internal init(cwd: String, client: any DaemonClient) {
        self.cwd = cwd
        self.client = client
    }

    /// Lists `path` (nil or empty = the workspace root). Directories first, then name.
    public func list(_ path: String? = nil) async {
        phase = .loading
        do {
            let response = try await client.send(
                FileExplorerRequest(cwd: cwd, mode: .list, path: normalized(path)))
            guard let directory = response.directory else {
                phase = .failed(response.error ?? "The daemon returned no directory.")
                error = response.error ?? "The daemon returned no directory."
                return
            }
            self.path = directory.path
            entries = directory.entries.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            file = nil
            error = nil
            phase = .ready
        } catch {
            phase = .failed(paseoStoreErrorText(error))
            self.error = paseoStoreErrorText(error)
        }
    }

    /// Reads one file. `maxBytes` defaults to `maxReadBytes`; the daemon truncates or classifies
    /// larger content as binary.
    public func read(_ path: String, maxBytes: Int? = nil) async {
        phase = .loading
        do {
            let response = try await client.send(
                FileExplorerRequest(
                    cwd: cwd,
                    mode: .file,
                    path: path,
                    maxBytes: max(maxBytes ?? maxReadBytes, 1)))
            guard let file = response.file else {
                let message = response.error ?? "The daemon returned no file."
                phase = .failed(message)
                error = message
                return
            }
            self.file = file
            self.path = file.path
            entries = []
            error = nil
            phase = .ready
        } catch {
            phase = .failed(paseoStoreErrorText(error))
            self.error = paseoStoreErrorText(error)
        }
    }

    /// Drops the last file so a view can go back to the listing without a re-read.
    public func clearFile() {
        file = nil
    }

    private func normalized(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        return path
    }
}
