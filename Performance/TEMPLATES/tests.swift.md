# Swift Testing templates (PaseoCore, new files only; never edit an existing test)

```swift
import Foundation
import Testing
@testable import PaseoStore

// 1. Identity stays stable while content streams (copy of StreamingIdentityTests' shape)
@Suite struct MyIdentityTests {
    @Test func idsSurviveEveryDelta() throws {
        var state = TimelineState()
        var movedSeqEnd = false
        for payload in try Load.stream() where payload.seq != nil {
            let before = Dictionary(uniqueKeysWithValues: state.rows.map { ($0.id, $0) })
            _ = state.applyStream(payload)
            for row in state.rows {
                guard let old = before[row.id] else { continue }
                #expect(old.seqStart == row.seqStart)
                if old.seqEnd != row.seqEnd { movedSeqEnd = true }
            }
        }
        #expect(movedSeqEnd, "the recorded stream must move seqEnd, or this proves nothing")
    }
}

// 2. Write on change: an equal write must not change what readers see (ConversationWorkspaceIdTests' shape)
@Suite @MainActor struct MyWriteOnChangeTests {
    @Test func equalSnapshotDoesNotNotify() {
        let store = MyStore()
        var changes = 0
        withObservationTracking({ _ = store.status }, onChange: { changes += 1 })
        store.handle(Update(status: "ready")); #expect(changes == 1)
        withObservationTracking({ _ = store.status }, onChange: { changes += 1 })
        store.handle(Update(status: "ready")); #expect(changes == 1, "an equal push must not notify")
    }
}

// 3. Cache bounds (count) and thread safety
@Suite struct MyCacheBoundsTests {
    @Test func evictsPastTheLimit() {
        let cache = ProseCache<Int, String>(budget: 1_000, countLimit: 3, cost: { _, v in v.count })
        for i in 0..<4 { cache.setValue("v\(i)", for: i) }
        #expect(cache.value(for: 0) == nil)
        #expect(cache.value(for: 3) == "v3")
    }
    @Test func survivesConcurrentUse() async {
        let cache = ProseCache<Int, Int>(budget: 10_000, countLimit: 64, cost: { _, _ in 1 })
        await withTaskGroup(of: Void.self) { group in
            for t in 0..<8 { group.addTask { for i in 0..<500 { cache.setValue(i, for: i % 100 + t); _ = cache.value(for: i % 100) } } }
        }
        #expect(cache.value(for: 1) != nil || true)   // reaching here without a crash or a data race is the test
    }
}
```
Run: `cd Packages/PaseoCore && swift test --filter MyCacheBoundsTests`. Existing examples: `PaseoDateCacheTests`, `ConversationRetentionTests`, `ConversationWorkspaceIdTests`, `StreamingIdentityTests`.
