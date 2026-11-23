#if canImport(UIKit)
import Foundation

/// How far each live message's paced reveal has got, by timeline row id.
///
/// A row's reveal state lives in `@State`, which a transcript cell loses when it is reused or
/// rebuilt. Before, the rebuilt view took first sight as "reveal whole", so a message scrolled
/// back into view mid-stream, or one that arrived as a single delta, painted all of its text at
/// once. The ledger lets a remounted reveal resume where it was, and lets the tail of a running
/// turn tell a message it has never shown (pace it from the start) from one it already has.
///
/// Main-actor only; a handful of entries live at a time (the running turn's prose), and an entry
/// goes once its message has finished revealing.
@MainActor
enum RevealLedger {
    private static var revealed: [String: Int] = [:]
    /// Insertion order, so a leaked entry (a view torn down mid-reveal) is evicted eventually.
    private static var order: [String] = []
    private static let capacity = 64

    static func progress(for key: String) -> Int? { revealed[key] }

    static func record(_ units: Int, for key: String) {
        if revealed.updateValue(units, forKey: key) == nil {
            order.append(key)
            if order.count > capacity {
                revealed[order.removeFirst()] = nil
            }
        }
    }

    static func finish(_ key: String) {
        guard revealed.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
    }
}
#endif
