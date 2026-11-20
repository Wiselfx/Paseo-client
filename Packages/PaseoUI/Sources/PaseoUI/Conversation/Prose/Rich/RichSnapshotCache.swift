#if canImport(UIKit)
import OSLog
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// Snapshots of rich content, by content and layout. `NSCache` drops them under memory pressure.
@MainActor
enum RichSnapshotCache {
    private static let table: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40
        cache.totalCostLimit = 24_000_000
        return cache
    }()

    /// The last snapshot per (content, scheme), whatever width it was rendered at. A card
    /// recreated by the transcript asks for this in its first `body` pass (O(1), R-1) and
    /// draws the page instead of a placeholder: a second visit never flashes.
    private static let recent: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        // A full-width page snapshot at screen scale is several megabytes; too small a
        // budget would evict the image a revisit is about to ask for.
        cache.totalCostLimit = 32_000_000
        return cache
    }()

    static func image(for key: String) -> UIImage? {
        table.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, for key: String) {
        table.setObject(image, forKey: key as NSString, cost: cost(of: image))
    }

    /// The latest snapshot for a card's content in a scheme, from any layout width.
    static func lastImage(for content: String, dark: Bool) -> UIImage? {
        recent.object(forKey: recentKey(for: content, dark: dark) as NSString)
    }

    /// The width-keyed layout entry: one render per (content, width, scheme).
    /// Content identity, not the string: the caller's hash keeps the key small for a
    /// 100 KB drawing.
    static func key(content: String, width: CGFloat, dark: Bool) -> String {
        "\(content)/\(Int(width.rounded()))/\(dark ? "d" : "l")"
    }

    /// Stores the render for its layout key and remembers it as the content's latest, so
    /// the next visit draws it before it knows its width.
    static func store(_ image: UIImage, for key: String, content: String, dark: Bool) {
        store(image, for: key)
        recent.setObject(image, forKey: recentKey(for: content, dark: dark) as NSString, cost: cost(of: image))
    }

    private static func recentKey(for content: String, dark: Bool) -> String {
        "\(content)|\(dark ? "d" : "l")"
    }

    private static func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.size.height * image.scale * image.scale * 4)
    }
}
#endif
