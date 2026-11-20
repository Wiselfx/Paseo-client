#if canImport(UIKit)
import LinkPresentation
import MapKit
import PaseoStore
import SwiftUI
import UIKit
import WebKit

// MARK: - Map card (M17)

/// Snapshot cache, keyed by coordinate. Snapshots are single-pass renders; re-snapshot
/// on every scroll would flicker, so the card never refetches what it already drew.
@MainActor
enum RichMapSnapshotCache {
    private static var table: [String: UIImage] = [:]

    static func image(for reference: MapReference) -> UIImage? {
        guard let lat = reference.latitude, let lng = reference.longitude else { return nil }
        return table["\(lat),\(lng)"]
    }

    static func store(_ image: UIImage, for reference: MapReference) {
        guard let lat = reference.latitude, let lng = reference.longitude else { return }
        if table.count >= 32 { table.removeAll(keepingCapacity: true) }
        table["\(lat),\(lng)"] = image
    }
}
#endif
