#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Persistence for remembered turn heights (W8): one small UserDefaults dictionary (bounded by
/// `TurnHeightMemory.capacity`), read once per chat open, written on a private serial queue.
enum TurnHeightStore {
    private static let key = "paseo.turnHeights.v1"
    private static let queue = DispatchQueue(label: "paseo.turnHeights", qos: .utility)

    static func load() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    static func save(_ snapshot: [String: Double]) {
        queue.async { UserDefaults.standard.set(snapshot, forKey: key) }
    }
}
#endif
