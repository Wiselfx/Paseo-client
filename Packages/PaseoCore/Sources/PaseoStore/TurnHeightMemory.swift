import Foundation

/// Remembered turn heights: pre-sizes a turn's row from the height it laid out at
/// before, so the lazy stack's first content estimate is right and the open re-seat
/// converges in one pass instead of realising rows around a wrong offset several times.
///
/// The key is exact — timeline epoch, turn id, the turn's first and last row seq, the
/// prose column bucket and the Dynamic Type size — so a miss reads as "no hint" (today's
/// behaviour), never as a wrong size. Turns are append-only once settled, so a key that
/// matches names identical content; the one case it cannot see (same seq range with
/// shorter content) resolves to growing room, which the layout fills exactly.
///
/// Bounds: at most `capacity` entries (oldest out), and no applied hint exceeds
/// `maxAppliedHeight`, so a corrupt or stale entry can never leave a huge gap.
/// Recording compares before writing; the UI additionally never re-records a height
/// its own hint produced (a minHeight-bound report would reinforce itself forever).
public struct TurnHeightMemory: Sendable, Equatable {
    /// Entries kept; oldest evicted first. ~200 turns × ~64 B ≈ 13 KB persisted.
    public static let capacity = 200
    /// Ceiling for any applied hint. A settled turn taller than this still scrolls
    /// fine — it just opens without a hint.
    public static let maxAppliedHeight: Double = 6000
    /// Column widths bucketed to this, so rotation and split view re-key while a
    /// one-point jitter does not.
    public static let widthBucket: Double = 8

    private var heights: [String: Double] = [:]
    private var order: [String] = []

    public init() {}

    /// The memory key for a settled turn's row. Every input is O(1) in chat size:
    /// call it per row per body pass.
    public static func fingerprint(
        epoch: String, turnId: String, firstRowSeq: Int?, lastRowSeq: Int?,
        columnWidth: Double, dynamicType: String
    ) -> String {
        let bucket = Int(columnWidth / widthBucket)
        return "\(epoch)|\(turnId)|\(firstRowSeq.map(String.init) ?? "-")|\(lastRowSeq.map(String.init) ?? "-")|\(bucket)|\(dynamicType)"
    }

    /// The hint for a key, if any, clamped to `maxAppliedHeight`. Pure read: safe to
    /// call from a view body (it publishes nothing).
    public func height(for key: String) -> Double? {
        guard let height = heights[key] else { return nil }
        return min(height, Self.maxAppliedHeight)
    }

    /// Remember a laid-out height. True when the memory changed. Non-positive heights
    /// are refused; an equal write changes nothing.
    @discardableResult
    public mutating func record(key: String, height: Double) -> Bool {
        guard height > 0, height.isFinite else { return false }
        if heights[key] == height { return false }
        if heights[key] == nil {
            order.append(key)
            while order.count > Self.capacity, !order.isEmpty {
                heights.removeValue(forKey: order.removeFirst())
            }
        }
        heights[key] = height
        return true
    }

    /// Merge persisted entries (one UserDefaults read per chat open). Fills up to the
    /// capacity bound and stops: live entries measured this session are never evicted
    /// by older persisted ones. Later records evict oldest-first as usual.
    public mutating func merge(_ persisted: [String: Double]) {
        for key in persisted.keys.sorted() {
            guard order.count < Self.capacity else { break }
            guard heights[key] == nil else { continue }
            guard let height = persisted[key], height > 0, height.isFinite else { continue }
            order.append(key)
            heights[key] = height
        }
    }

    /// Snapshot for persistence. Bounded by `capacity`.
    public var persisted: [String: Double] { heights }

    public var count: Int { heights.count }
}
