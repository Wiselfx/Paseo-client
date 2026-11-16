import Foundation
import Testing

@testable import PaseoStore

/// `rowsVersion` bumps exactly when `rows` changes, so O(rows) readers can memoize
/// on `(epoch, rowsVersion)` and recompute once per change instead of once per pass.
@Suite struct TimelineRowsVersionTests {
    @Test func versionStartsAtZero() {
        #expect(TimelineState().rowsVersion == 0)
    }

    @Test func pageBumpsOnce() throws {
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        #expect(state.rowsVersion == 1)
        state.applyPage(try Load.page(before: 8))
        #expect(state.rowsVersion == 2)
    }

    @Test func appliedStreamBumps() throws {
        let stream = try Load.stream().filter { $0.seq != nil }
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        let before = state.rowsVersion
        #expect(state.applyStream(stream[0]) == .applied)
        #expect(state.rowsVersion == before + 1)
    }

    @Test func ignoredStreamsNeverBump() throws {
        let stream = try Load.stream().filter { $0.seq != nil }
        var state = TimelineState()
        #expect(state.applyStream(stream[0]) == .ignored)
        #expect(state.rowsVersion == 0)
        state.applyPage(try Load.page(before: 8))
        #expect(state.applyStream(stream[0]) == .applied)
        let before = state.rowsVersion
        #expect(state.applyStream(stream[0]) == .duplicate)
        #expect(state.applyStream(stream[2]) == .gap(expected: 9, received: 10))
        #expect(state.rowsVersion == before)
        var otherEpoch = try #require(stream.first { $0.seq != nil })
        otherEpoch.epoch = "some-other-epoch"
        #expect(state.applyStream(otherEpoch) == .epochChanged)
        #expect(state.rowsVersion == before)
    }

    @Test func pendingSendBumpsOnAddAndRealRemoveOnly() {
        var state = TimelineState()
        state.addPendingUserMessage(text: "hi", clientMessageId: "c1", timestamp: "t")
        #expect(state.rowsVersion == 1)
        state.removePendingUserMessage(clientMessageId: "missing")
        #expect(state.rowsVersion == 1)
        #expect(state.rows.count == 1)
        state.removePendingUserMessage(clientMessageId: "c1")
        #expect(state.rowsVersion == 2)
        #expect(state.rows.isEmpty)
    }
}
