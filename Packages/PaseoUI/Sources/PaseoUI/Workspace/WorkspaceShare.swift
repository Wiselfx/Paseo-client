#if canImport(UIKit)
import PaseoStore
import SwiftUI
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
        let file = try await readFile(checkout, path: path)
        let data: Data
        if let text = file.textContent {
            data = Data(text.utf8)
        } else if file.encoding == .base64, let content = file.content,
            let decoded = Data(base64Encoded: content, options: .ignoreUnknownCharacters)
        {
            data = decoded
        } else if file.kind == .binary {
            throw ShareError.unreadable("This file can't be shared from here.")
        } else {
            throw ShareError.unreadable("The daemon sent no bytes for this file.")
        }
        let displayName = name ?? file.path.split(separator: "/").last.map(String.init) ?? "file"
        let base = (displayName as NSString).deletingPathExtension
        let ext = (displayName as NSString).pathExtension
        let unique = ext.isEmpty
            ? "\(base)-\(UUID().uuidString.prefix(8))"
            : "\(base)-\(UUID().uuidString.prefix(8)).\(ext)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(unique)
        try data.write(to: url, options: .atomic)
        return url
    }
}
#endif
