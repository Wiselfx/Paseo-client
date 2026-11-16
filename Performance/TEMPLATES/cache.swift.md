# New bounded, thread-safe cache (shape of ProseCache, Conversation/Prose/MarkdownDocumentModel.swift)

```swift
final class ThingCache<Key: Hashable, Value>: @unchecked Sendable {
    private final class Node {
        var key: Key; var value: Value; var cost: Int; var previous: Node?; var next: Node?
        init(key: Key, value: Value, cost: Int) { self.key = key; self.value = value; self.cost = cost }
    }
    private let lock = NSLock()                       // everything below is touched only under the lock
    private var nodes: [Key: Node] = [:]
    private var head: Node?; private var tail: Node?
    private var cost = 0
    private let budget: Int                           // cost limit (bytes or units)
    private let countLimit: Int                       // count limit
    private let costOf: (Key, Value) -> Int

    init(budget: Int, countLimit: Int, cost: @escaping (Key, Value) -> Int) {
        self.budget = max(1, budget); self.countLimit = max(1, countLimit); self.costOf = cost
    }
    func value(for key: Key) -> Value? { lock.lock(); defer { lock.unlock() }
        guard let node = nodes[key] else { return nil }; moveToFront(node); return node.value }
    func setValue(_ value: Value, for key: Key) { lock.lock(); defer { lock.unlock() }
        /* update or insert, pushFront, then evict from the tail while cost > budget || nodes.count > countLimit */ }
    // moveToFront / pushFront / detach / evict: copy them from ProseCache (linked list: a hit is O(1))
}
```
Rules: key = exactly what the reader keys on; both limits set; images also `NSCache` + `didReceiveMemoryWarning` eviction; a failure memo for network/decode errors.
Smaller option for a pure memo of cheap values: a dictionary behind an `NSLock` that `removeAll` at a limit (`PaseoDate.Cache`, 4096). Test the bound: [tests.swift.md](tests.swift.md).
