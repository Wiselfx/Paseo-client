import Foundation
import Testing
import PaseoProtocol
@testable import PaseoStore

/// Acceptance tests for T2. Do not weaken these to make an implementation pass.
@Suite struct TimelineStateTests {
    /// The core contract: live deltas, merged, equal what the daemon projects for the same turn.
    @Test func replayingTheStreamReproducesTheProjection() throws {
        let full = try Load.page()
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        for payload in try Load.stream() {
            let result = state.applyStream(payload)
            if payload.seq != nil { #expect(result == .applied, "seq \(payload.seq!)") } else { #expect(result == .ignored) }
        }
        let expected = Load.rows(full.entries)
        #expect(state.rows.count == expected.count)
        for (got, want) in zip(state.rows, expected) {
            #expect(got.id == want.id)
            #expect(got.item == want.item, "row \(want.id)")
            #expect(got.turnId == want.turnId)
            #expect(got.seqStart == want.seqStart)
            #expect(got.seqEnd == want.seqEnd)
        }
        #expect(state.nextSeq == full.window.nextSeq)
    }

    @Test func streamBeforeAnyPageIsIgnored() throws {
        var state = TimelineState()
        let first = try #require(try Load.stream().first { $0.seq != nil })
        #expect(state.applyStream(first) == .ignored)
        #expect(state.rows.isEmpty)
    }

    @Test func duplicatesAndGapsChangeNothing() throws {
        let stream = try Load.stream().filter { $0.seq != nil }
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        #expect(state.applyStream(stream[0]) == .applied)  // seq 8
        let afterFirst = state
        #expect(state.applyStream(stream[0]) == .duplicate)
        #expect(state.applyStream(stream[2]) == .gap(expected: 9, received: 10))
        #expect(state == afterFirst)
    }

    @Test func otherEpochIsReported() throws {
        var payload = try #require(try Load.stream().first { $0.seq != nil })
        payload.epoch = "some-other-epoch"
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        let before = state
        #expect(state.applyStream(payload) == .epochChanged)
        #expect(state == before)
    }

    @Test func pendingUserMessageIsConfirmedInPlace() throws {
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        state.addPendingUserMessage(text: "Think briefly first…", clientMessageId: "fixture-msg-1", timestamp: "2026-11-08T21:00:00.000Z")
        let count = state.rows.count
        #expect(state.rows.last?.isPending == true)
        #expect(state.rows.last?.id == "local:fixture-msg-1")
        let echo = try #require(try Load.stream().first { $0.seq == 8 })
        #expect(state.applyStream(echo) == .applied)
        #expect(state.rows.count == count)
        #expect(state.rows.last?.isPending == false)
        #expect(state.rows.last?.id == "local:fixture-msg-1", "keeps view identity")
        #expect(state.rows.last?.seqStart == 8)
    }

    @Test func pagesCompose() throws {
        let full = try Load.page()
        var older = full
        older.direction = .before
        older.entries = full.entries.filter { $0.seqEnd < 8 }
        older.hasOlder = false
        var tail = full
        tail.entries = full.entries.filter { $0.seqStart >= 8 }
        tail.hasOlder = true

        var state = TimelineState()
        state.applyPage(tail)
        #expect(state.hasOlder)
        #expect(state.rows.first?.seqStart == 8)
        state.applyPage(older)
        #expect(!state.hasOlder)
        #expect(state.rows.map(\.seqStart) == full.entries.map(\.seqStart))
        #expect(state.nextSeq == full.window.nextSeq, "a before page leaves nextSeq alone")

        // Same page again: no duplicate rows.
        state.applyPage(tail)
        #expect(state.rows.count == full.entries.count)

        // A reset page replaces everything.
        var reset = tail
        reset.reset = true
        state.applyPage(reset)
        #expect(state.rows.map(\.seqStart) == tail.entries.map(\.seqStart))
    }
}
