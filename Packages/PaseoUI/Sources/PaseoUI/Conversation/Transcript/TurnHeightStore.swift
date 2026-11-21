#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Persistence for remembered turn heights (W8): one small UserDefaults dictionary (bounded by
/// `TurnHeightMemory.capacity`), read once per chat open, written off the main actor.
enum TurnHeightStore {
    private static let key = "paseo.turnHeights.v1"

    /// Snapshots waiting to be written. One consumer drains the stream in the order the snapshots
    /// were queued, so writes never overlap and an older snapshot cannot land after a newer one.
    /// Only the newest unwritten snapshot is kept: each one is the whole dictionary, so a skipped
    /// one loses nothing.
    private static let pending: AsyncStream<[String: Double]>.Continuation = {
        let (stream, continuation) = AsyncStream<[String: Double]>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        let storageKey = key
        Task(priority: .utility) {
            for await snapshot in stream {
                UserDefaults.standard.set(snapshot, forKey: storageKey)
            }
        }
        return continuation
    }()

    static func load() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    static func save(_ snapshot: [String: Double]) {
        pending.yield(snapshot)
    }
}
#endif
