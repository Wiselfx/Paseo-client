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
    /// Observable error sink; T15's entry operations surface daemon refusals here verbatim.
    public internal(set) var error: String?

    /// Hard cap for inline reads. Bigger files come back truncated or refused by the daemon.
    public var maxReadBytes = 512 * 1024

    /// Entry-op/write capabilities, read once per host. Internal: T15's `FileEntries.swift`
    /// extension reads and updates it.
    internal var entryCapabilities = EntryCapabilities()

    /// Internal (not private) so the T15 extension file can send RPCs with it.
    internal let client: any DaemonClient

    /// The connection's streamed-read assembler, owned by `HostSession`. Nil in isolated stores
    /// (tests, scratch instances made without one): `fetchBytes` then keeps the JSON road.
    internal let binaryFileReads: BinaryFileReads?

    internal init(cwd: String, client: any DaemonClient, binaryFileReads: BinaryFileReads? = nil) {
        self.cwd = cwd
        self.client = client
        self.binaryFileReads = binaryFileReads
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

    /// Reads one file without touching this store's visible state. For inline previews: several
    /// images can load at once without overwriting `file`/`phase`, which the Files page shows.
    /// Same request as `read`; throws when the daemon answers without a file.
    public func fetch(_ path: String, maxBytes: Int? = nil) async throws -> FileExplorerFile {
        let response = try await client.send(
            FileExplorerRequest(
                cwd: readCwd(for: path),
                mode: .file,
                path: path,
                maxBytes: max(maxBytes ?? maxReadBytes, 1)))
        guard let file = response.file else {
            throw PaseoStoreError.missingFile(path: path, message: response.error)
        }
        return file
    }

    /// Reads one file's bytes through the daemon's binary file channel, so video, audio and
    /// every other binary file that the inline JSON answer refuses (`encoding: "none"`) arrives
    /// whole. Also the road for Save to Files.
    ///
    /// With `acceptBinary: true` the daemon streams `FileBegin`/`FileChunk…`/`FileEnd` frames
    /// correlated to this request's id, then sends no JSON response; the connection closes the
    /// request at `FileEnd` (`DaemonConnection.completeFileRead`) and `binaryFileReads` assembles
    /// the bytes off the main actor. Images and transports without a binary channel keep the
    /// inline JSON road, which is what the image pipeline already reads.
    ///
    /// Upstream: `packages/client/src/daemon-client.ts:5635` (`readFile`).
    public func fetchBytes(_ path: String, maxBytes: Int? = nil) async throws -> FileReadResult {
        let limit = max(maxBytes ?? maxReadBytes, 1)
        guard client.canReceiveBinaryFrames, !Self.isInlineImage(path),
            let binaryFileReads
        else {
            return try await fetchJSONBytes(path, maxBytes: limit)
        }

        let requestId = UUID().uuidString
        await binaryFileReads.register(requestId: requestId, maxBytes: limit)

        let response: FileExplorerRequest.Response
        do {
            var request = FileExplorerRequest(
                cwd: readCwd(for: path), mode: .file, path: path, maxBytes: limit,
                acceptBinary: true)
            request.requestId = requestId
            // The timeout bounds the whole transfer — the daemon streams every byte before the
            // connection closes the request — so it is the read's ceiling, not one frame's.
            // Upstream's `readFile` takes the same bound as an argument (`daemon-client.ts:5635`);
            // 120 s carries a 64 MB file over the relay.
            response = try await client.send(request, timeout: .seconds(120))
        } catch {
            await binaryFileReads.abandon(requestId: requestId)
            throw error
        }

        if let message = response.error {
            // The daemon stats first: over `maxBytes` it answers "File is too large to display"
            // and streams nothing.
            await binaryFileReads.abandon(requestId: requestId)
            throw PaseoStoreError.missingFile(path: path, message: message)
        }
        if let file = response.file {
            // A daemon without a binary channel (or one that answered inline) sends the JSON
            // shape even when asked to stream; the bytes are in `content`.
            await binaryFileReads.abandon(requestId: requestId)
            return try await Self.decodeOffMain(file)
        }

        let assembly: BinaryFileReads.Assembly
        do {
            assembly = try await binaryFileReads.result(for: requestId)
        } catch let failure as BinaryFileReads.Failure {
            switch failure {
            case .tooLarge:
                throw PaseoStoreError.missingFile(path: path, message: Self.tooLargeText)
            case .incomplete, .timedOut:
                throw PaseoStoreError.transferIncomplete(path: path)
            }
        }
        return FileReadResult(
            data: assembly.data, mimeType: assembly.mimeType, size: assembly.size, path: path,
            kind: Self.kind(mimeType: assembly.mimeType), modifiedAt: assembly.modifiedAt,
            revision: assembly.revision)
    }

    /// The inline JSON read behind `fetchBytes`: base64 or UTF-8 content decoded off the main
    /// actor, so a multi-megabyte image never stalls a frame.
    private func fetchJSONBytes(_ path: String, maxBytes: Int) async throws -> FileReadResult {
        let response = try await client.send(
            FileExplorerRequest(
                cwd: readCwd(for: path), mode: .file, path: path, maxBytes: maxBytes))
        guard let file = response.file else {
            throw PaseoStoreError.missingFile(path: path, message: response.error)
        }
        return try await Self.decodeOffMain(file)
    }

    /// The directory a read is rooted in. A path inside the workspace reads from the workspace; `~/`
    /// reads from home; any other absolute path (a screenshot in `/tmp`) reads from the filesystem
    /// root. Upstream: `packages/app/src/file-explorer/preview-target.ts:60-107`.
    nonisolated func readCwd(for path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" || trimmed.hasPrefix("~/") { return "~" }
        guard trimmed.hasPrefix("/") else { return cwd }
        let root = cwd.count > 1 && cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        if root == "/" || trimmed == root || trimmed.hasPrefix(root + "/") { return cwd }
        return "/"
    }

    /// A parent listing without touching the Files page's state (`read`/`list` reset
    /// `file`, `entries` and `phase`, which the open panel shows). Throws when the
    /// daemon answers without a directory. The transcript uses it for lazy file sizes.
    public func entries(at path: String?) async throws -> [FileExplorerEntry] {
        let response = try await client.send(
            FileExplorerRequest(cwd: cwd, mode: .list, path: normalized(path)))
        guard let directory = response.directory else {
            throw PaseoStoreError.missingFile(path: path ?? "", message: response.error)
        }
        return directory.entries
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

    // MARK: Byte decoding

    /// The daemon's own refusal text (`workspace-files-session.ts:296`), so a streamed file past
    /// the cap reads exactly like an inline one past the cap.
    private nonisolated static let tooLargeText = "File is too large to display"

    /// Extensions the daemon answers inline as base64 (`IMAGE_MIME_TYPES`,
    /// `packages/server/src/server/file-explorer/service.ts:130-137`). They keep the JSON road:
    /// the image pipeline already reads those bytes, and a second road buys nothing.
    private nonisolated static func isInlineImage(_ path: String) -> Bool {
        switch (path as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return true
        default: return false
        }
    }

    /// The file kind a streamed read implies. Mirrors upstream's `binaryFileKind`
    /// (`daemon-client.ts:1214`).
    private nonisolated static func kind(mimeType: String) -> FileExplorerFileKind {
        if mimeType.hasPrefix("image/") { return .image }
        if mimeType.hasPrefix("text/") || mimeType == "application/json" { return .text }
        return .binary
    }

    /// Extracts the bytes of an inline file off the main actor: a 64 MB base64 string never
    /// decodes (or copies) on the thread that draws. `@concurrent` runs it on the global
    /// executor without a detached task, so it keeps the caller's task priority.
    @concurrent private nonisolated static func decodeOffMain(_ file: FileExplorerFile) async throws
        -> FileReadResult
    {
        let data: Data
        switch file.encoding {
        case .base64:
            guard let content = file.content,
                let decoded = Data(
                    base64Encoded: content, options: [.ignoreUnknownCharacters])
            else {
                throw PaseoStoreError.missingFile(path: file.path, message: nil)
            }
            data = decoded
        case .utf8:
            data = Data((file.content ?? "").utf8)
        case .none, .unknown:
            throw PaseoStoreError.missingFile(path: file.path, message: nil)
        }
        return FileReadResult(
            data: data, mimeType: file.mimeType ?? "application/octet-stream", size: file.size,
            path: file.path, kind: file.kind, modifiedAt: file.modifiedAt,
            revision: file.revision)
    }
}

/// Entry-operation and file-editing capabilities for `WorkspaceFiles`, set once per host.
/// Internal on purpose: views read the derived `supports*` flags on T15's extension.
struct EntryCapabilities: Sendable, Hashable {
    public var supportsEntryOps: Bool
    public var supportsEntryDuplicate: Bool
    public var supportsFileEditing: Bool

    public init(
        supportsEntryOps: Bool = false, supportsEntryDuplicate: Bool = false,
        supportsFileEditing: Bool = false
    ) {
        self.supportsEntryOps = supportsEntryOps
        self.supportsEntryDuplicate = supportsEntryDuplicate
        self.supportsFileEditing = supportsFileEditing
    }
}

/// A side-effect-free file read that failed (`WorkspaceFiles.fetch`). `read` reports the same
/// failures through `phase`/`error` instead of throwing.
public enum PaseoStoreError: LocalizedError, Sendable, Equatable {
    /// The daemon answered without a file: it refused, or sent an unexpected shape.
    case missingFile(path: String, message: String?)
    /// A streamed read that began but did not finish: bytes short of the advertised size, a chunk
    /// past the cap, or no end frame before the assembly deadline.
    case transferIncomplete(path: String)

    public var errorDescription: String? {
        switch self {
        case .missingFile(_, let message): return message ?? "The daemon returned no file."
        case .transferIncomplete: return "The host didn't finish sending the file."
        }
    }
}

/// One finished file read: the bytes plus what the daemon said about them. Both roads (streamed
/// binary frames and the inline JSON answer) return this shape.
/// Source: `FileReadResult` (`packages/client/src/daemon-client.ts:604`).
public struct FileReadResult: Sendable, Hashable {
    public var data: Data
    public var mimeType: String
    public var size: Int
    public var path: String
    public var kind: FileExplorerFileKind
    public var modifiedAt: String
    public var revision: String?

    public init(
        data: Data, mimeType: String, size: Int, path: String, kind: FileExplorerFileKind,
        modifiedAt: String, revision: String?
    ) {
        self.data = data
        self.mimeType = mimeType
        self.size = size
        self.path = path
        self.kind = kind
        self.modifiedAt = modifiedAt
        self.revision = revision
    }
}
