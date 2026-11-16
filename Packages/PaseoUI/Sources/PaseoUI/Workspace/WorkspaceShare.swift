#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Reads a workspace file's bytes through the store read and writes them to a unique temp file,
/// so the rows and the viewer can hand the system share sheet a file URL.
///
/// `WorkspaceFiles.fetchBytes` streams the bytes over the session's binary file channel (the
/// inline JSON answer only carries images), so there is no byte-level progress to report; callers
/// show an indeterminate state while it runs. Main-actor: it drives checkout state.
@MainActor
enum WorkspaceShare {
    enum ShareError: Error {
        case unreadable(String)
    }

    /// The bytes and metadata of a finished read, or throws with the host's message.
    /// Streamed binary frames and the inline JSON answer share this road (V3), so video and audio
    /// save like text and images do.
    static func readFile(
        _ checkout: CheckoutStore, path: String, maxBytes: Int = 64 * 1024 * 1024
    ) async throws -> FileReadResult {
        do {
            return try await checkout.files.fetchBytes(path, maxBytes: maxBytes)
        } catch let error as PaseoStoreError {
            throw ShareError.unreadable(error.errorDescription ?? "The host returned no file.")
        } catch {
            // A lost connection reads the same as it did through `read`: one plain sentence.
            throw ShareError.unreadable(error.localizedDescription)
        }
    }

    /// Reads `path` and materializes it at a unique temp file. Returns the file URL.
    static func prepare(_ checkout: CheckoutStore, path: String, name: String? = nil) async throws -> URL {
        let (data, _, displayName) = try await prepareExport(checkout, path: path, name: name)
        let base = (displayName as NSString).deletingPathExtension
        let ext = (displayName as NSString).pathExtension
        let unique = ext.isEmpty
            ? "\(base)-\(UUID().uuidString.prefix(8))"
            : "\(base)-\(UUID().uuidString.prefix(8)).\(ext)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(unique)
        // A 64 MB write for a video or audio file never runs on the main actor: the share sheet
        // waits a beat instead of the screen freezing.
        try await Task.detached(priority: .userInitiated) {
            try data.write(to: url, options: .atomic)
        }.value
        return url
    }

    /// Reads `path` into memory for `fileExporter`. Same socket read as `prepare` (64 MB cap);
    /// the HTTP `file_download_token` route is unreachable from this client, which has no HTTP
    /// base URL or Basic-auth credentials for the daemon — the file comes over the session
    /// socket instead, like upstream's relay/socket path.
    ///
    /// Returns the bytes, a UTType derived from the extension (`.data` when unknown) and the
    /// display name. In-memory: a 64 MB file doubles its footprint here.
    static func prepareExport(
        _ checkout: CheckoutStore, path: String, name: String? = nil
    ) async throws -> (data: Data, contentType: UTType, displayName: String) {
        let file = try await readFile(checkout, path: path)
        return bytesAndName(file, name: name)
    }

    /// The shared byte extraction for `prepare` and `prepareExport`.
    static func bytesAndName(
        _ file: FileReadResult, name: String?
    ) -> (data: Data, contentType: UTType, displayName: String) {
        let displayName = name ?? file.path.split(separator: "/").last.map(String.init) ?? "file"
        let ext = (displayName as NSString).pathExtension
        let contentType = ext.isEmpty ? .data : (UTType(filenameExtension: ext) ?? .data)
        return (file.data, contentType, displayName)
    }

    /// Whether a `fileExporter` completion error is just the user dismissing the sheet.
    static func isUserCancellation(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == 3072 { return true }
        return String(describing: error).lowercased().contains("cancel")
    }
}

/// Minimal `FileDocument` carrying bytes already in memory, for `fileExporter`.
struct WorkspaceExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.item]
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
