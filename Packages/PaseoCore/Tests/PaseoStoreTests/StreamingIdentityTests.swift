import Foundation
import Testing
import PaseoProtocol
@testable import PaseoStore

/// W1 (docs/perf/PERFORMANCE-RULES.md, rule 3): view identity must not follow a value that moves
/// while text streams. A row's `seqEnd` advances with every merged delta; its `id` and its segment's
/// `id` must not. The transcript once hung `.id("row:\(seqEnd)")` on the streaming prose, so every
/// token destroyed and rebuilt the whole message; these tests pin the two facts that make that a bug
/// and keep the stable identifiers the UI is allowed to use.
@Suite struct StreamingIdentityTests {
    @Test func rowAndSegmentIdsSurviveEveryStreamedDelta() throws {
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        var movedSeqEnd = false
        for payload in try Load.stream() where payload.seq != nil {
            let before = Dictionary(uniqueKeysWithValues: state.rows.map { ($0.id, $0) })
            let turnsBefore = TurnBuilder.turns(from: state.rows, activeTurnId: nil)
            _ = state.applyStream(payload)
            let turnsAfter = TurnBuilder.turns(from: state.rows, activeTurnId: nil)
            for row in state.rows {
                guard let old = before[row.id] else { continue }
                #expect(old.seqStart == row.seqStart, "a row's seqStart is its identity: \(row.id)")
                if old.seqEnd != row.seqEnd { movedSeqEnd = true }
            }
            // Every segment that existed before still exists after, with the same id.
            let idsAfter = Set(turnsAfter.flatMap { $0.segments.map(\.id) })
            for segment in turnsBefore.flatMap({ $0.segments }) {
                #expect(idsAfter.contains(segment.id), "segment \(segment.id) changed identity")
            }
        }
        #expect(movedSeqEnd, "the recorded stream must grow a row, or this test proves nothing")
    }
}
