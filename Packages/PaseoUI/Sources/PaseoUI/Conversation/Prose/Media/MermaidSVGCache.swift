#if canImport(UIKit)
import Foundation
import UIKit

/// The rendered SVG per diagram, keyed by (source, scheme): the snapshot cache holds
/// pixels, this holds the vector for the artifact page's live view. Bounded and
/// in-memory like every transcript cache.
enum MermaidSVGCache {
    nonisolated(unsafe) private static let table: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 32
        return cache
    }()

    static func string(for key: String) -> String? {
        table.object(forKey: key as NSString).map { String($0) }
    }

    static func store(_ svg: String, for key: String) {
        table.setObject(svg as NSString, forKey: key as NSString)
    }
}
#endif
