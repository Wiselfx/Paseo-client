#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// Decoded heroes and icons, by page URL. The provider hands over full `UIImage`s
/// that decode lazily on main at first draw; the cache holds the width-exact
/// thumbnails, and remembers misses so a revisit never refetches a failure.
/// `NSCache` reads are O(1) and thread-safe, so the first pass after a remount
/// lays the hero box out instead of flashing the text row for one frame.
@MainActor
enum RichLinkHeroCache {
    nonisolated(unsafe) private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 32
        return cache
    }()

    private static var misses: Set<String> = []

    static func image(for key: String) -> UIImage? {
        images.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, for key: String) {
        images.setObject(image, forKey: key as NSString)
        misses.remove(key)
    }

    static func noteMiss(for key: String) {
        misses.insert(key)
    }

    static func missed(_ key: String) -> Bool {
        misses.contains(key)
    }
}
#endif
