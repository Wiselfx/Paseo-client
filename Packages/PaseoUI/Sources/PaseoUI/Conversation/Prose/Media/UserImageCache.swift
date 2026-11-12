#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit

// MARK: - UserImageCache (Phase C §9.5)

// NOTE: Images the reader sends from this device ride in the user bubble, keyed by
// the send's `clientMessageId` (the daemon echoes it on the user_message row, so the
// pending bubble and the settled row read the same entry). Thumbnails seed memory
// synchronously at send (the tray already holds them, so the pending bubble draws
// on its first pass with no async gap); full bytes persist to a bounded disk cache
// off main. A tiny manifest (`clientId → [aspect ratio]`) reserves the image boxes
// at the right ratios on the first pass — the pixels fade into reserved boxes —
// loaded once off main at app start into the published dictionary. Anything else
// (another device, an evicted entry, no manifest row) shows nothing: no box, no
// placeholder, no fetch, never a network read for a bubble.

/// This device's sent-image thumbnails, by send id. Memory first, disk second.
/// An `@Observable` main-actor store: the bubble reads the manifest and memory in
/// `body` (O(1), subscribed), and every write path funnels here. File bytes move
/// in `Task.detached`; the manifest dictionary and its JSON never leave main.
@MainActor @Observable
final class UserImageCache {
    static let shared = UserImageCache()

    /// Aspect ratios per send, in image order. The bubble reserves these boxes on
    /// frame one; the pixels arrive after.
    private(set) var manifest: [String: [CGFloat]] = [:]

    private let memory: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.countLimit = 200
        return cache
    }()

    private var manifestLoaded = false
    private var manifestLoad: Task<[String: [Double]], Never>?

    private static let fileExtension = "jpg"
    /// LRU bound: user thumbnails are small; 50 MB is thousands of sends.
    private static let diskCapBytes = 50 * 1024 * 1024
    /// The bubble's thumbnail width: downscaled once at send, drawn as-is.
    private static let thumbnailMaxPixels = 600
    /// More images than any bubble draws; bounds the disk scan per message.
    private static let maxImagesPerMessage = 8

    /// The manifest, once: the JSON read happens off main, the published
    /// dictionary lands on main (which re-renders any waiting bubble).
    func ensureManifestLoaded() async {
        if manifestLoaded { return }
        if manifestLoad == nil {
            manifestLoad = Task.detached(priority: .utility) {
                Self.readManifestFile()
            }
        }
        guard let load = manifestLoad else { return }
        let loaded = await load.value
        manifest = loaded.mapValues { $0.map { CGFloat($0) } }
        manifestLoaded = true
    }

    /// The tray's thumbnails, seeded synchronously at send so the pending bubble
    /// draws on its first pass with no async gap. Also records the ratios: boxes
    /// reserve correctly even before the disk persist lands.
    func seed(_ images: [UIImage], for clientMessageId: String) {
        guard !images.isEmpty else { return }
        memory.setObject(images as NSArray, forKey: clientMessageId as NSString)
        manifest[clientMessageId] = images.map { aspectRatio(of: $0) }
    }

    /// The full bytes, downscaled and written off main. Fire-and-forget: the memory
    /// seed already covers the visible bubble; this is for history and remounts.
    /// The manifest row persists with the files (off main); the published
    /// dictionary follows on main so the first pass after a relaunch reserves.
    func persist(_ datas: [Data], for clientMessageId: String) {
        guard !datas.isEmpty else { return }
        let ext = Self.fileExtension
        Task {
            let ratios = await Task.detached(priority: .utility) { () -> [Double] in
                guard let directory = Self.diskDirectory() else { return [] }
                do {
                    try FileManager.default.createDirectory(
                        at: directory, withIntermediateDirectories: true)
                } catch {
                    return []
                }
                var ratios: [Double] = []
                for (index, data) in datas.enumerated() {
                    guard let image = Self.downscaled(data: data) else { continue }
                    let url = directory
                        .appending(path: "\(clientMessageId)-\(index).\(ext)")
                    try? image.jpegData(compressionQuality: 0.8)?.write(to: url, options: .atomic)
                    let size = image.size
                    ratios.append(size.height > 0 ? Double(size.width / size.height) : 1)
                }
                Self.writeManifestFile(merging: [clientMessageId: ratios])
                return ratios
            }.value
            if !ratios.isEmpty {
                self.manifest[clientMessageId] = ratios.map { CGFloat($0) }
            }
            await self.evictIfNeeded()
        }
    }

    /// Forget a send: refused/failed sends roll their pending bubble back, so no
    /// images may linger in memory, on disk, or in the manifest.
    func discard(_ clientMessageId: String) {
        memory.removeObject(forKey: clientMessageId as NSString)
        manifest[clientMessageId] = nil
        let ext = Self.fileExtension
        let maxImages = Self.maxImagesPerMessage
        Task.detached(priority: .utility) {
            guard let directory = Self.diskDirectory() else { return }
            for index in 0..<maxImages {
                let url = directory
                    .appending(path: "\(clientMessageId)-\(index).\(ext)")
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                } else {
                    break
                }
            }
            Self.writeManifestFile(removing: clientMessageId)
        }
    }

    /// The memory seed, or nil when nothing is known: the bubble shows nothing.
    func memoryThumbnails(for clientMessageId: String) -> [UIImage]? {
        (memory.object(forKey: clientMessageId as NSString) as? [UIImage])
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The manifest ratios for a send, for first-pass box reservation.
    func manifestRatios(for clientMessageId: String) -> [CGFloat]? {
        manifest[clientMessageId]?.filter { $0.isFinite && $0 > 0 }
    }

    /// The disk entries, oldest index first. Nil when nothing is known. Off main;
    /// a disk hit reseeds memory so the next first pass is instant.
    func diskThumbnails(for clientMessageId: String) async -> [UIImage]? {
        let ext = Self.fileExtension
        let maxImages = Self.maxImagesPerMessage
        let images = await Task.detached(priority: .utility) { () -> [UIImage]? in
            guard let directory = Self.diskDirectory() else { return nil }
            var images: [UIImage] = []
            for index in 0..<maxImages {
                let url = directory
                    .appending(path: "\(clientMessageId)-\(index).\(ext)")
                guard let data = try? Data(contentsOf: url),
                    let image = UIImage(data: data)
                else { break }
                images.append(image)
                try? FileManager.default.setAttributes(
                    [.modificationDate: Date()], ofItemAtPath: url.path)
            }
            guard !images.isEmpty else { return nil }
            return images
        }.value
        // A disk hit reseeds memory so the next first pass is instant.
        if let images {
            memory.setObject(images as NSArray, forKey: clientMessageId as NSString)
        }
        return images
    }

    // MARK: Manifest file

    private static func manifestURL() -> URL? {
        diskDirectory()?.appending(path: "manifest.json", directoryHint: .notDirectory)
    }

    private static func readManifestFile() -> [String: [Double]] {
        guard let url = manifestURL(),
            let data = try? Data(contentsOf: url),
            var decoded = try? JSONDecoder().decode([String: [Double]].self, from: data)
        else { return [:] }
        // Prune rows whose files are gone (eviction, manual clears): the manifest
        // never outlives the bytes, so it stays bounded by the LRU itself.
        let pruned = decoded.filter { id, _ in hasFiles(for: id) }
        if pruned.count != decoded.count {
            decoded = pruned
            if let data = try? JSONEncoder().encode(decoded) {
                try? data.write(to: url, options: .atomic)
            }
        }
        return decoded
    }

    private static func hasFiles(for clientMessageId: String) -> Bool {
        guard let directory = diskDirectory() else { return false }
        for index in 0..<maxImagesPerMessage {
            let url = directory.appending(path: "\(clientMessageId)-\(index).\(fileExtension)")
            if FileManager.default.fileExists(atPath: url.path) { return true }
        }
        return false
    }

    /// Merges one send's ratios into the manifest file. Runs off main; the published
    /// dictionary is updated separately on main, so concurrent sends can't clobber
    /// each other in memory (the file is rewritten, not patched, per send).
    private static func writeManifestFile(merging entry: [String: [Double]]) {
        var manifest = readManifestFile()
        for (key, value) in entry { manifest[key] = value }
        guard let url = manifestURL(),
            let data = try? JSONEncoder().encode(manifest)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func writeManifestFile(removing clientMessageId: String) {
        var manifest = readManifestFile()
        manifest[clientMessageId] = nil
        guard let url = manifestURL(),
            let data = try? JSONEncoder().encode(manifest)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Disk

    private static func diskDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "user-images", directoryHint: .notDirectory)
    }

    private static func downscaled(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailMaxPixels,
        ]
        guard
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    private func aspectRatio(of image: UIImage) -> CGFloat {
        let size = image.size
        guard size.height > 0 else { return 1 }
        let ratio = size.width / size.height
        return ratio.isFinite && ratio > 0 ? ratio : 1
    }

    /// Evicts least-recently-used sends until the directory fits the cap, on both
    /// layers: files off main, manifest rows on main with them.
    private func evictIfNeeded() async {
        let ext = Self.fileExtension
        let cap = Self.diskCapBytes
        let evicted = await Task.detached(priority: .utility) { () -> [String] in
            guard let directory = Self.diskDirectory() else { return [] }
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
            guard
                let files = try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: keys)
            else { return [] }
            let thumbs = files.filter { $0.pathExtension == ext }
            var total = 0
            var bySend: [String: [(url: URL, size: Int, date: Date)]] = [:]
            for url in thumbs {
                guard
                    let values = try? url.resourceValues(forKeys: Set(keys)),
                    let size = values.fileSize, let date = values.contentModificationDate
                else { continue }
                total += size
                let name = url.deletingPathExtension().lastPathComponent
                let id = name.components(separatedBy: "-").dropLast().joined(separator: "-")
                bySend[id, default: []].append((url, size, date))
            }
            guard total > cap else { return [] }
            let ordered = bySend.values.flatMap { $0 }.sorted { $0.date < $1.date }
            var evicted: Set<String> = []
            for entry in ordered {
                try? FileManager.default.removeItem(at: entry.url)
                total -= entry.size
                let name = entry.url.deletingPathExtension().lastPathComponent
                evicted.insert(name.components(separatedBy: "-").dropLast().joined(separator: "-"))
                if total <= cap { break }
            }
            return Array(evicted)
        }.value
        guard !evicted.isEmpty else { return }
        for id in evicted {
            memory.removeObject(forKey: id as NSString)
            manifest[id] = nil
        }
        let remaining = manifest
        await Task.detached(priority: .utility) {
            guard let url = Self.manifestURL(),
                let data = try? JSONEncoder().encode(remaining.mapValues { $0.map { Double($0) } })
            else { return }
            try? data.write(to: url, options: .atomic)
        }.value
    }
}
#endif
