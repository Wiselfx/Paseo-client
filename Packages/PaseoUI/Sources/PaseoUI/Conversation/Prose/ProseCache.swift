import Foundation
import Markdown
import PaseoStore

/// A main-actor LRU memo for prose caches (markdown documents, rich detection,
/// linkified text). Entries are kept until the byte budget or the count limit is hit,
/// so a long answer stays warm while older pieces are evicted one at a time. The
/// recency list is a linked list so a hit is O(1); the array version scanned every
/// entry per hit, which is expensive when the keys are long streamed strings.
final class ProseCache<Key: Hashable, Value>: @unchecked Sendable {
    private final class Node {
        var key: Key
        var value: Value
        var cost: Int
        var previous: Node?
        var next: Node?
        init(key: Key, value: Value, cost: Int) {
            self.key = key
            self.value = value
            self.cost = cost
        }
    }

    /// Thread-safe (W1): the warm-up fills these caches off the main actor while the views read them.
    private let lock = NSLock()
    private var nodes: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?
    private var cost = 0
    private let budget: Int
    private let countLimit: Int
    private let costOf: (Key, Value) -> Int

    init(budget: Int, countLimit: Int, cost: @escaping (Key, Value) -> Int) {
        self.budget = max(1, budget)
        self.countLimit = max(1, countLimit)
        self.costOf = cost
    }

    func value(for key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let node = nodes[key] else { return nil }
        moveToFront(node)
        return node.value
    }

    func setValue(_ value: Value, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        let newCost = costOf(key, value)
        if let node = nodes[key] {
            cost += newCost - node.cost
            node.value = value
            node.cost = newCost
            moveToFront(node)
            return
        }
        let node = Node(key: key, value: value, cost: newCost)
        nodes[key] = node
        pushFront(node)
        cost += newCost
        evict()
    }

    private func moveToFront(_ node: Node) {
        guard head !== node else { return }
        detach(node)
        pushFront(node)
    }

    private func pushFront(_ node: Node) {
        node.previous = nil
        node.next = head
        head?.previous = node
        head = node
        if tail == nil { tail = node }
    }

    private func detach(_ node: Node) {
        node.previous?.next = node.next
        node.next?.previous = node.previous
        if head === node { head = node.next }
        if tail === node { tail = node.previous }
        node.previous = nil
        node.next = nil
    }

    private func evict() {
        while cost > budget || nodes.count > countLimit, let node = tail {
            detach(node)
            nodes.removeValue(forKey: node.key)
            cost -= node.cost
        }
    }
}
