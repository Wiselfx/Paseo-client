#if canImport(UIKit)
import Foundation

/// The persisted table behind `MediaMetadataCache`: identity -> width / height, in one bounded
/// JSON file in the caches directory. A relaunched transcript then reserves every remembered
/// card's real box on its first pass, instead of a guess that resizes once the size is known.
///
/// `lock` guards the table. The file is read once, synchronously, on first access, because the
/// first pass needs the table; a missing or corrupt file reads as empty. Writes never run on main.
/// `remember` schedules at most one write, about two seconds out, on a utility-priority task, and
/// changes that arrive while it waits ride along with it. Each write holds `writeLock` for its
/// whole run, snapshots the table under `lock`, and replaces the file atomically, so an older
/// snapshot cannot land after a newer one.
///
/// The table holds at most `capacity` identities, and past that the oldest insertion goes first.
/// The file is a plain dictionary and keeps no order, so after a relaunch the loaded entries count
/// as ordered by identity: eviction among them is arbitrary, though still bounded.
final class MediaAspectFile: @unchecked Sendable {
    /// Identities kept, in memory and on disk.
    private static let capacity = 4000
    /// A value this close to the stored one is not remembered again: no change, no write.
    private static let tolerance = 0.001
    /// How long a change waits for its write, so a burst of learned sizes shares one write.
    private static let writeDelay: Duration = .seconds(2)
    private static let fileName = "paseo-media-aspects.json"

    /// `<Caches>/paseo-media-aspects.json`, or nil when the system has no caches directory.
    static var defaultFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: Self.fileName, directoryHint: .notDirectory)
    }

    private let fileURL: URL?
    /// Guards `aspects`, `order`, `loaded` and `pendingWrite`. Never held across a file write.
    private let lock = NSLock()
    /// Serializes file writes, so an older snapshot cannot replace a newer one.
    private let writeLock = NSLock()
    private var aspects: [String: Double] = [:]
    /// Identities in insertion order: the first is the oldest.
    private var order: [String] = []
    private var loaded = false
    private var pendingWrite: Task<Void, Never>?

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    /// The stored ratio for an identity, or nil when nothing has learned it.
    func aspectRatio(for key: String) -> Double? {
        lock.withLock { () -> Double? in
            loadIfNeededLocked()
            return aspects[key]
        }
    }

    /// Stores a finite, positive ratio and schedules its write. A value within `tolerance` of the
    /// stored one changes nothing and writes nothing.
    func remember(_ aspectRatio: Double, for key: String) {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return }
        lock.withLock { () -> Void in
            loadIfNeededLocked()
            if let current = aspects[key] {
                guard abs(current - aspectRatio) > Self.tolerance else { return }
            } else {
                order.append(key)
            }
            aspects[key] = aspectRatio
            evictOverflowLocked()
            scheduleWriteLocked()
        }
    }

    /// Drops the oldest insertions until the table fits `capacity`. The newest entry is last, so
    /// it is never the one dropped. Caller holds `lock`.
    private func evictOverflowLocked() {
        while order.count > Self.capacity {
            let oldest = order.removeFirst()
            aspects[oldest] = nil
        }
    }

    /// Reads the file once. Values that cannot be ratios are dropped and the table is capped, so a
    /// corrupt entry never reaches a card. Caller holds `lock`.
    private func loadIfNeededLocked() {
        guard !loaded else { return }
        loaded = true
        guard let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return }
        aspects = stored.filter { _, value in value.isFinite && value > 0 }
        order = aspects.keys.sorted()
        evictOverflowLocked()
    }

    /// Schedules the one pending write, unless one already waits or there is no file to write.
    /// Caller holds `lock`.
    private func scheduleWriteLocked() {
        guard pendingWrite == nil, fileURL != nil else { return }
        pendingWrite = Task(priority: .utility) { [weak self] () async -> Void in
            try? await Task.sleep(for: MediaAspectFile.writeDelay)
            self?.writeNow()
        }
    }

    /// Snapshots the table and writes it. Clears `pendingWrite` in the same critical section, so a
    /// change made after the snapshot schedules the next write. Runs on the utility task, not main.
    private func writeNow() {
        guard let fileURL else { return }
        writeLock.withLock { () -> Void in
            let snapshot = lock.withLock { () -> [String: Double] in
                pendingWrite = nil
                return aspects
            }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
#endif
