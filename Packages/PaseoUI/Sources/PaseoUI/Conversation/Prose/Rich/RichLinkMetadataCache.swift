#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

// MARK: - Link card (§1.1)

/// Metadata cache, keyed by URL. LPMetadataProvider network fetches are expensive; a
/// card should never refetch what scroll already showed it.
@MainActor
enum RichLinkMetadataCache {
    private static var table: [URL: LPLinkMetadata] = [:]

    static func metadata(for url: URL) -> LPLinkMetadata? { table[url] }

    static func store(_ metadata: LPLinkMetadata, for url: URL) {
        if table.count >= 64 { table.removeAll(keepingCapacity: true) }
        table[url] = metadata
    }
}
#endif
