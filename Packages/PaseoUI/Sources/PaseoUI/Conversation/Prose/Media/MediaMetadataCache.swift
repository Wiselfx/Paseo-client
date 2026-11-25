#if canImport(UIKit)
import CoreGraphics
import Foundation

// MARK: - MediaMetadataCache (G2 §1.3)

// NOTE: RemoteImagePipeline/G2: durations join this cache in G11.
// NOTE: MermaidCard (`shapeKey`) and RichWebCard (`contentKey`) key by `hashValue`, which changes
// every launch: their rows persist but never match again, and they push live rows out at the cap.

/// The shape of every URL and daemon path the transcript has seen, by content identity.
///
/// A card's box is reserved from here before any byte arrives (§1.3): the first frame reads
/// synchronously — an `NSCache` read is O(1) and thread-safe, so scrolling back never flashes
/// a placeholder — and the single animated settle to the true ratio happens once, the first
/// time a size is learned. The entry survives eviction of the pixels themselves, so a card
/// never animates twice for the same content.
///
/// Two layers. `NSCache` answers first. Behind it, `MediaAspectFile` keeps the same table on disk
/// (`<Caches>/paseo-media-aspects.json`, capped), so a card seen in an earlier launch reserves its
/// real box on the first pass too. A file hit refills the `NSCache`.
///
/// Keys are cache identities, not URLs: the normalized absolute string for remote content
/// (`MediaPipeline.cacheIdentity(for:)`), the daemon live key for files
/// (`MediaPipeline.liveKey(ref:)`). Keys are persisted, so they must be the same in every launch:
/// never derive one from `hashValue`, which Swift seeds per process. Values are width / height as
/// decoded, never zero.
enum MediaMetadataCache {
    /// `NSNumber` hands back `Double`; convert explicitly (`Double?` is not `CGFloat?`).
    nonisolated(unsafe) private static let sizes = NSCache<NSString, NSNumber>()

    /// The persisted table behind `sizes`. Its file is read on first access; see `MediaAspectFile`.
    private static let persisted = MediaAspectFile(fileURL: MediaAspectFile.defaultFileURL)

    /// The aspect ratio known for a key, or nil when nothing has learned it yet. Memory first; a
    /// miss reads the persisted table, and a hit there refills memory.
    static func aspectRatio(for key: String) -> CGFloat? {
        if let cached = sizes.object(forKey: key as NSString) {
            return CGFloat(cached.doubleValue)
        }
        guard let stored = persisted.aspectRatio(for: key) else { return nil }
        sizes.setObject(NSNumber(value: stored), forKey: key as NSString)
        return CGFloat(stored)
    }

    /// Remember a shape learned any other way (an SVG `viewBox`, a snapshot, a video track).
    /// Non-positive and non-finite ratios are dropped: a card must never divide by them. The
    /// persisted table takes the value off main, in one debounced write; a value within 0.001 of
    /// the stored one is not written again.
    static func remember(_ aspectRatio: CGFloat, for key: String) {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return }
        let value = Double(aspectRatio)
        sizes.setObject(NSNumber(value: value), forKey: key as NSString)
        persisted.remember(value, for: key)
    }
}
#endif
