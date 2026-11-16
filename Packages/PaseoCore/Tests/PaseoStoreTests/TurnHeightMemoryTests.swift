import Testing

@testable import PaseoStore

/// Remembered turn heights: exact keys, bounded memory, no reinforcement.
/// The UI wiring (geometry callbacks, UserDefaults) is thin on top of this.
@Suite struct TurnHeightMemoryTests {
    private func key(_ turn: String = "row:4", first: Int? = 1, last: Int? = 7) -> String {
        TurnHeightMemory.fingerprint(
            epoch: "e1", turnId: turn, firstRowSeq: first, lastRowSeq: last,
            columnWidth: 350, dynamicType: "large")
    }

    @Test func fingerprintIsStable() {
        #expect(key() == key())
    }

    @Test func fingerprintSeparatesWhatChangesLayout() {
        let base = key()
        #expect(key("row:8") != base)
        #expect(key(first: 2) != base)
        #expect(key(last: 9) != base)
        #expect(
            TurnHeightMemory.fingerprint(
                epoch: "e2", turnId: "row:4", firstRowSeq: 1, lastRowSeq: 7,
                columnWidth: 350, dynamicType: "large") != base)
        #expect(
            TurnHeightMemory.fingerprint(
                epoch: "e1", turnId: "row:4", firstRowSeq: 1, lastRowSeq: 7,
                columnWidth: 400, dynamicType: "large") != base)
        #expect(
            TurnHeightMemory.fingerprint(
                epoch: "e1", turnId: "row:4", firstRowSeq: 1, lastRowSeq: 7,
                columnWidth: 350, dynamicType: "xLarge") != base)
    }

    @Test func fingerprintIgnoresSubBucketJitter() {
        let a = TurnHeightMemory.fingerprint(
            epoch: "e1", turnId: "row:4", firstRowSeq: 1, lastRowSeq: 7,
            columnWidth: 350, dynamicType: "large")
        let b = TurnHeightMemory.fingerprint(
            epoch: "e1", turnId: "row:4", firstRowSeq: 1, lastRowSeq: 7,
            columnWidth: 351, dynamicType: "large")
        #expect(a == b)
    }

    @Test func missingKeyHasNoHint() {
        #expect(TurnHeightMemory().height(for: key()) == nil)
    }

    @Test func recordedHeightReadsBack() {
        var memory = TurnHeightMemory()
        let ok = memory.record(key: key(), height: 812)
        #expect(ok)
        #expect(memory.height(for: key()) == 812)
    }

    @Test func equalWriteChangesNothing() {
        var memory = TurnHeightMemory()
        let ok = memory.record(key: key(), height: 812)
        #expect(ok)
        let changed = memory.record(key: key(), height: 812)
        #expect(!changed)
    }

    @Test func nonPositiveHeightsAreRefused() {
        var memory = TurnHeightMemory()
        let refused = memory.record(key: key(), height: 0)
        #expect(!refused)
        #expect(memory.count == 0)
    }

    @Test func negativeAndNonFiniteHeightsAreRefused() {
        var memory = TurnHeightMemory()
        for height in [-4.0, Double.nan, Double.infinity] {
            let refused = memory.record(key: key(), height: height)
            #expect(!refused)
        }
        #expect(memory.count == 0)
    }

    @Test func appliedHintIsCapped() {
        var memory = TurnHeightMemory()
        let ok = memory.record(key: key(), height: 60_000)
        #expect(ok)
        #expect(memory.height(for: key()) == TurnHeightMemory.maxAppliedHeight)
    }

    @Test func capacityEvictsOldestFirst() {
        var memory = TurnHeightMemory()
        for i in 0..<(TurnHeightMemory.capacity + 10) {
            let k = TurnHeightMemory.fingerprint(
                epoch: "e", turnId: "row:\(i)", firstRowSeq: i, lastRowSeq: i,
                columnWidth: 350, dynamicType: "large")
            let ok = memory.record(key: k, height: Double(100 + i))
            #expect(ok)
        }
        #expect(memory.count == TurnHeightMemory.capacity)
        let first = TurnHeightMemory.fingerprint(
            epoch: "e", turnId: "row:0", firstRowSeq: 0, lastRowSeq: 0,
            columnWidth: 350, dynamicType: "large")
        #expect(memory.height(for: first) == nil)
        let latest = TurnHeightMemory.fingerprint(
            epoch: "e", turnId: "row:\(TurnHeightMemory.capacity + 9)",
            firstRowSeq: TurnHeightMemory.capacity + 9,
            lastRowSeq: TurnHeightMemory.capacity + 9,
            columnWidth: 350, dynamicType: "large")
        #expect(memory.height(for: latest) != nil)
    }

    @Test func mergeRespectsCapacityAndKeepsLiveEntries() {
        var memory = TurnHeightMemory()
        let ok = memory.record(key: key(), height: 111)
        #expect(ok)
        var persisted: [String: Double] = [:]
        for i in 0..<(TurnHeightMemory.capacity + 5) {
            persisted["persisted:\(i)"] = Double(200 + i)
        }
        memory.merge(persisted)
        #expect(memory.count == TurnHeightMemory.capacity)
        // The live entry survives the merge.
        #expect(memory.height(for: key()) == 111)
    }

    @Test func mergeSkipsJunk() {
        var memory = TurnHeightMemory()
        memory.merge(["a": 0, "b": -3, "c": .nan, "ok": 42])
        #expect(memory.count == 1)
        #expect(memory.height(for: "ok") == 42)
    }

    @Test func persistedRoundTrips() {
        var memory = TurnHeightMemory()
        let ok = memory.record(key: key(), height: 812)
        #expect(ok)
        var restored = TurnHeightMemory()
        restored.merge(memory.persisted)
        #expect(restored.height(for: key()) == 812)
    }
}
