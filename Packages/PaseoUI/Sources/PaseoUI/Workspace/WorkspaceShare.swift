#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Reads a workspace file's bytes through the store read and writes them to a unique temp file,
/// so the rows and the viewer can hand the system share sheet a file URL.
///
/// `WorkspaceFiles.read` returns everything in one RPC (text inline, or base64 for binary/images),
/// so there is no byte-level progress to report; callers show an indeterminate state while it runs.
enum WorkspaceShare {
    enum ShareError: Error {
        case unreadable(String)
    }

    /// The `FileExplorerFile` of a finished read, or throws with the daemon's message.
    static func readFile(_ checkout: CheckoutStore, path: String, maxBytes: Int = 64 * 1024 * 1024) async throws -> FileExplorerFile {
        let files = checkout.files
        await files.read(path, maxBytes: maxBytes)
        guard files.phase == .ready, let file = files.file else {
            throw ShareError.unreadable(files.error ?? "The daemon returned no file.")
        }
        return file
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
        try data.write(to: url, options: .atomic)
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
        return try bytesAndName(file, name: name)
    }

    /// The shared byte extraction for `prepare` and `prepareExport`.
    static func bytesAndName(
        _ file: FileExplorerFile, name: String?
    ) throws -> (data: Data, contentType: UTType, displayName: String) {
        let data: Data
        if let text = file.textContent {
            data = Data(text.utf8)
        } else if file.encoding == .base64, let content = file.content,
            let decoded = Data(base64Encoded: content, options: .ignoreUnknownCharacters)
        {
            data = decoded
        } else if file.kind == .binary {
            throw ShareError.unreadable("This file can't be saved from here.")
        } else {
            throw ShareError.unreadable("The daemon sent no bytes for this file.")
        }
        let displayName = name ?? file.path.split(separator: "/").last.map(String.init) ?? "file"
        let ext = (displayName as NSString).pathExtension
        let contentType = ext.isEmpty ? .data : (UTType(filenameExtension: ext) ?? .data)
        return (data, contentType, displayName)
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
        data = configuration.file?.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
