#if canImport(UIKit)
import Foundation

/// The user-image manifest file (`clientId → [aspect ratio]`), one actor owning every read
/// and write. The file is read-modify-written from several places (a persist, a discard,
/// the prune at load, an eviction), so without one serial owner two quick sends can each read
/// the old file and the later write drops the earlier row, and a stale snapshot can undo a
/// concurrent persist. Every change here reads the file fresh and writes it back inside one
/// actor turn.
actor UserImageManifestFile {
    private let directory: URL
    private let fileExtension: String
    private let maxImagesPerMessage: Int

    init(directory: URL, fileExtension: String, maxImagesPerMessage: Int) {
        self.directory = directory
        self.fileExtension = fileExtension
        self.maxImagesPerMessage = maxImagesPerMessage
    }

    private var url: URL {
        directory.appending(path: "manifest.json", directoryHint: .notDirectory)
    }

    /// The manifest, pruned of rows whose files are gone.
    func load() -> [String: [Double]] {
        readPruned()
    }

    /// Merges one send's ratios into the file.
    func merge(_ entry: [String: [Double]]) {
        var manifest = readPruned()
        for (key, value) in entry { manifest[key] = value }
        write(manifest)
    }

    /// Drops the rows for these sends: refused sends and evicted entries.
    func remove(ids: Set<String>) {
        var manifest = readPruned()
        for id in ids { manifest[id] = nil }
        write(manifest)
    }

    private func readPruned() -> [String: [Double]] {
        guard let data = try? Data(contentsOf: url),
            var decoded = try? JSONDecoder().decode([String: [Double]].self, from: data)
        else { return [:] }
        // Prune rows whose files are gone (eviction, manual clears): the manifest
        // never outlives the bytes, so it stays bounded by the LRU itself.
        let pruned = decoded.filter { id, _ in hasFiles(for: id) }
        if pruned.count != decoded.count {
            decoded = pruned
            write(decoded)
        }
        return decoded
    }

    private func write(_ manifest: [String: [Double]]) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func hasFiles(for clientMessageId: String) -> Bool {
        for index in 0..<maxImagesPerMessage {
            let file = directory.appending(path: "\(clientMessageId)-\(index).\(fileExtension)")
            if FileManager.default.fileExists(atPath: file.path) { return true }
        }
        return false
    }
}
#endif
