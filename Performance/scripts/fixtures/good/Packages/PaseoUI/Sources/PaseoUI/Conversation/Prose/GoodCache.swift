// features: F04 F05 F07 F15
// Fixture: GOOD cache shapes: ProseCache style (lock, count and cost limits), NSCache with both limits,
// a dictionary cache that evicts, a stored Task that is cancelled, an @unchecked Sendable guarded by a lock.
import Foundation
import UIKit

final class GoodProseCache<Key: Hashable, Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var nodes: [Key: Value] = [:]
    private let countLimit: Int

    init(countLimit: Int) { self.countLimit = max(1, countLimit) }

    func value(for key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return nodes[key]
    }

    func setValue(_ value: Value, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        if nodes.count >= countLimit { nodes.removeAll(keepingCapacity: true) }
        nodes[key] = value
    }
}

final class GoodImages {
    func render(_ text: String) -> AttributedString { AttributedString(text) }

    private let cache = NSCache<NSString, UIImage>()
    private var loader: Task<Void, Never>?

    init() {
        cache.countLimit = 64
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func webView(_ webView: UIView, didFinish navigation: Navigation!) {}

    func drain() {
        while true {
            guard let item = next() else { break }
            handle(item)
        }
    }

    func start() {
        loader = Task { await run() }
    }

    deinit { loader?.cancel() }
}
