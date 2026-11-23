#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

// MARK: - Link card (§1.1)

/// Metadata cache, keyed by URL. LPMetadataProvider network fetches are expensive; a
/// card should never refetch what scroll already showed it, nor a link that already failed.
/// Past the limit the oldest entry goes, so one new link never flips every card's title
/// back to its domain.
@MainActor
enum RichLinkMetadataCache {
    private static let limit = 64
    private static var table: [URL: LPLinkMetadata] = [:]
    /// Insertion order, oldest first, for eviction.
    private static var order: [URL] = []
    private static var misses: Set<URL> = []

    static func metadata(for url: URL) -> LPLinkMetadata? { table[url] }

    static func store(_ metadata: LPLinkMetadata, for url: URL) {
        if table[url] != nil {
            order.removeAll { $0 == url }
        } else if table.count >= limit, let oldest = order.first {
            order.removeFirst()
            table[oldest] = nil
        }
        order.append(url)
        table[url] = metadata
        misses.remove(url)
    }

    /// A fetch that failed: a remount does not retry it this session.
    static func noteMiss(for url: URL) {
        misses.insert(url)
    }

    static func missed(_ url: URL) -> Bool {
        misses.contains(url)
    }
}
#endif
