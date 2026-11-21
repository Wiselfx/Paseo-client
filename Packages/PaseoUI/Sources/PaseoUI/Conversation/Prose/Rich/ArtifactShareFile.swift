#if canImport(UIKit)
import Foundation

/// Writes an artifact's exported `.html` to the caches directory. `@concurrent`, so the build and
/// the disk write run off the main actor without an unstructured detached task.
enum ArtifactShareFile {
    /// The live document in the given scheme, saved as `fileName`; nil when the kind has no
    /// document or the write fails. The scheme is baked in so the export opens correctly in
    /// Safari.
    @concurrent
    static func write(kind: ArtifactDocument.Kind, dark: Bool, fileName: String) async -> URL? {
        guard let html = ArtifactDocument(kind: kind, shareImage: nil).liveHTML(dark: dark),
            let data = html.data(using: .utf8)
        else { return nil }
        let directory = URL.cachesDirectory.appending(path: "artifacts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: fileName, directoryHint: .notDirectory)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }
}
#endif
