# Caches and memory

Rules: PF-31, PF-33. MUST: M28, M29, M30. Checks: C20, H12, H24, F07. Template: [cache](../TEMPLATES/cache.swift.md).
A cache with no bound is a leak with a delay. Every cache here has a count limit AND a cost limit, a lock when touched off main, and the key the reader uses.

## 1. ProseCache: thread-safe LRU, O(1) hit (`9f14d48`)
```swift
final class ProseCache<Key: Hashable, Value>: @unchecked Sendable {
    private let lock = NSLock(); private var nodes: [Key: Node] = [:]; private var head: Node?; private var tail: Node?
    private var cost = 0; private let budget: Int; private let countLimit: Int; private let costOf: (Key, Value) -> Int
    func value(for key: Key) -> Value? { lock.lock(); defer { lock.unlock() }; guard let node = nodes[key] else { return nil }; moveToFront(node); return node.value }
    func setValue(_ value: Value, for key: Key) { lock.lock(); defer { lock.unlock() } /* update cost, pushFront, evict() to budget and countLimit */ }
}
```
BAD it replaced: evict-all at 64 entries; a linked list scan per hit with long streamed strings as keys; unlocked access while the warm-up wrote off main.

## 2. Sized by what it holds
- `CodeHighlightMirror`: `ProseCache<CodeHighlightKey, AttributedString>(budget: 8 * 1024 * 1024, countLimit: 128, cost: { key, _ in key.count * 4 })`.
- `PaseoDate.parse`: 4096 entries behind an `NSLock`, `removeAll` when full; it stores `nil` for unparsable strings too (`b368d48`; tens of microseconds per `FormatStyle` parse, per agent per sidebar pass).
- Images: `NSCache` with `countLimit` + `totalCostLimit`, evicted on memory warning, failure memo.

## 3. Bound what stays open (`d061427`; `ConversationRetentionTests`)
`HostSession.retainedConversationLimit = 6`: past it, a new open closes conversations that are not recent, not focused and not busy (running, permission pending, unsent draft, unknown send, upload).
Reopen loads from the daemon like a first open; drafts live in `DraftStore`. Not yet bounded: both daemon event streams are `.unbounded` (open follow-up, [DECISIONS.md](../DECISIONS.md)).

## 4. Test the bound, not just the hit
Insert `limit + 1` entries; assert the oldest is gone and `count <= limit`. Template: [tests](../TEMPLATES/tests.swift.md).

If you remember nothing else:
- Count limit AND cost limit, an `NSLock` when anything off main touches it, and a test that proves the bound.
- Key the cache exactly as the view reads it, or the warm-up warms nothing.
- Bound open stores and streams by recency plus busy; images evict on memory warning.
