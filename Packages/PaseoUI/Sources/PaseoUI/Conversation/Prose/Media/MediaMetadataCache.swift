#if canImport(UIKit)
import CoreGraphics
import Foundation

// MARK: - MediaMetadataCache (G2 §1.3)

// NOTE: RemoteImagePipeline/G2: durations join this cache in G11.

/// The shape of every URL and daemon path the transcript has seen, by content identity.
///
/// A card's box is reserved from here before any byte arrives (§1.3): the first frame reads
/// synchronously — an `NSCache` read is O(1) and thread-safe, so scrolling back never flashes
/// a placeholder — and the single animated settle to the true ratio happens once, the first
/// time a size is learned. The entry survives eviction of the pixels themselves, so a card
/// never animates twice for the same content.
///
/// Keys are cache identities, not URLs: the normalized absolute string for remote content
/// (`MediaPipeline.cacheIdentity(for:)`), the daemon disk key for files. Values are width /
/// height as decoded, never zero.
enum MediaMetadataCache {
    /// `NSNumber` hands back `Double`; convert explicitly (`Double?` is not `CGFloat?`).
    nonisolated(unsafe) private static let sizes = NSCache<NSString, NSNumber>()

    /// The aspect ratio known for a key, or nil when nothing has learned it yet.
    static func aspectRatio(for key: String) -> CGFloat? {
        sizes.object(forKey: key as NSString).map { CGFloat($0.doubleValue) }
    }

    /// Remember a shape learned any other way (an SVG `viewBox`, a snapshot, a video track).
    /// Non-positive and non-finite ratios are dropped: a card must never divide by them.
    static func remember(_ aspectRatio: CGFloat, for key: String) {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return }
        sizes.setObject(NSNumber(value: Double(aspectRatio)), forKey: key as NSString)
    }
}
#endif
