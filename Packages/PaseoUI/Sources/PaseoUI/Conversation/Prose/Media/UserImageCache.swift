#if canImport(UIKit)
import Foundation
import UIKit

// MARK: - UserImageCache (Phase C §9.5)

// NOTE: Images the reader sends from this device ride in the user bubble, keyed by
// the send's `clientMessageId` (the daemon echoes it on the user_message row, so the
// pending bubble and the settled row read the same entry). Thumbnails seed memory
// synchronously at send time (the tray already holds them); full bytes persist to a
// bounded disk cache off main. Anything else — another device, an evicted entry —
// shows nothing: no placeholder, no fetch, never a network read for a bubble.

/// This device's sent-image thumbnails, by send id. Memory first, disk second.
enum UserImageCache {
    nonisolated(unsafe) private static let memory: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.countLimit = 200
        return cache
    }()

    private static let fileExtension = "jpg"
    /// LRU bound: user thumbnails are small; 50 MB is thousands of sends.
    private static let diskCapBytes = 50 * 1024 * 1024
    /// The bubble's thumbnail width: downscaled once at send, drawn as-is.
    private static let thumbnailMaxPixels = 600

    /// The tray's thumbnails, seeded synchronously at send so the pending bubble
    /// draws on its first pass with no async gap.
    static func seed(_ images: [UIImage], for clientMessageId: String) {
        guard !images.isEmpty else { return }
        memory.setObject(images as NSArray, forKey: clientMessageId as NSString)
    }

    /// The full bytes, downscaled and written off main. Fire-and-forget: the memory
    /// seed already covers the visible bubble; this is for history and remounts.
    static func persist(_ datas: [Data], for clientMessageId: String) {
        guard !datas.isEmpty else { return }
        Task.detached(priority: .utility) {
            guard let directory = diskDirectory() else { return }
            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
            } catch {
                return
            }
            for (index, data) in datas.enumerated() {
                guard let image = downscaled(data: data) else { continue }
                let url = directory
                    .appending(path: "\(clientMessageId)-\(index).\(fileExtension)")
                try? image.jpegData(compressionQuality: 0.8)?.write(to: url, options: .atomic)
            }
            evictOverdue(in: directory)
        }
    }

    /// The memory seed, or nil when nothing is known: the bubble shows nothing.
    static func memoryThumbnails(for clientMessageId: String) -> [UIImage]? {
        (memory.object(forKey: clientMessageId as NSString) as? [UIImage])
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The disk entries, oldest-index first. Nil when nothing is known. Off main;
    /// a disk hit also reseeds memory so the next first pass is instant.
    static func diskThumbnails(for clientMessageId: String) async -> [UIImage]? {
        await Task.detached(priority: .utility) { () -> [UIImage]? in
            guard let directory = diskDirectory() else { return nil }
            var images: [UIImage] = []
            for index in 0..<Self.maxImagesPerMessage {
                let url = directory
                    .appending(path: "\(clientMessageId)-\(index).\(Self.fileExtension)")
                guard let data = try? Data(contentsOf: url),
                    let image = UIImage(data: data)
                else { break }
                images.append(image)
                try? FileManager.default.setAttributes(
                    [.modificationDate: Date()], ofItemAtPath: url.path)
            }
            guard !images.isEmpty else { return nil }
            memory.setObject(images as NSArray, forKey: clientMessageId as NSString)
            return images
        }.value
    }

    /// More images than any bubble draws; bounds the disk scan per message.
    private static let maxImagesPerMessage = 8

    private static func diskDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "user-images", directoryHint: .isDirectory)
    }

    private static func downscaled(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixels,
        ]
        guard
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    /// Evicts least-recently-used files until the directory fits the cap.
    private static func evictOverdue(in directory: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys)
        else { return }
        let sized = files.compactMap { url -> (URL, Int, Date)? in
            guard
                let values = try? url.resourceValues(forKeys: Set(keys)),
                let size = values.fileSize, let date = values.contentModificationDate
            else { return nil }
            return (url, size, date)
        }
        var total = sized.reduce(0) { $0 + $1.1 }
        guard total > diskCapBytes else { return }
        for (url, size, _) in sized.sorted(by: { $0.2 < $1.2 }) {
            try? FileManager.default.removeItem(at: url)
            total -= size
            if total <= diskCapBytes { break }
        }
    }
}
#endif
