#if canImport(UIKit)
import Foundation
import UniformTypeIdentifiers

/// Reads a file the user picked — Files, the composer's add menu — off the main actor.
///
/// `Data(contentsOf:)` on a security-scoped URL is a **blocking** read: tens of milliseconds of
/// frozen composer for a 40 MB local file, and seconds for an iCloud file that is not downloaded
/// yet (which is also where it fails). The 50 MB cap has to be enforced around that same read, so
/// both live here, once, for the conversation's tray and the draft's.
///
/// The security scope is taken and released inside the same background hop: only the read needs it,
/// and holding it across a suspension would keep the file open for an unbounded time.
enum PickedFileLoader {
    /// One picked file, ready for the tray. `Sendable`: it crosses back to the main actor.
    struct Loaded: Sendable, Equatable {
        let data: Data
        /// From the file's extension; `application/octet-stream` when it has none.
        let mimeType: String
    }

    enum Failure: Error, Equatable, Sendable {
        /// The picker handed us a URL we may not open (a revoked security scope).
        case unopenable
        /// Not a readable file: a directory, a permissions problem, an iCloud file that will not
        /// download.
        case unreadable
        /// Over the upload cap. Refused on the size the filesystem reports when it can, so a
        /// 200 MB pick is never read first.
        case tooLarge(byteCount: Int)
    }

    static func load(_ url: URL, maxBytes: Int) async -> Result<Loaded, Failure> {
        await Task.detached(priority: .userInitiated) { () -> Result<Loaded, Failure> in
            guard url.startAccessingSecurityScopedResource() else { return .failure(.unopenable) }
            defer { url.stopAccessingSecurityScopedResource() }
            // A dataless iCloud file reports no usable size, so the read's own count is checked too.
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                size > maxBytes
            {
                return .failure(.tooLarge(byteCount: size))
            }
            guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
            guard data.count <= maxBytes else {
                return .failure(.tooLarge(byteCount: data.count))
            }
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            return .success(Loaded(data: data, mimeType: mimeType))
        }.value
    }
}
#endif
