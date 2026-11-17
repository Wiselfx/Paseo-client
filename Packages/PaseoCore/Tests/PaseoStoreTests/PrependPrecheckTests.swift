import Foundation
import PaseoProtocol
import Testing

@testable import PaseoProtocol
@testable import PaseoStore

/// The O(1) precheck in `turnsAfterPrepend` must not divert a pure append into the prepend path: an
/// append still takes the general path, with the same built count as before the precheck existed.
/// (`turnsBuiltLastUpdate`/`rowsComparedLastUpdate` are the counters the incremental suite pins.)
@Suite struct PrependPrecheckTests {
    private func makeRows(_ count: Int) -> [TimelineRow] {
        (0..<count).map { index in
            TimelineRow(
                id: "seq:\(index)",
                turnId: "t\(index / 10)",
                item: .assistantMessage(.init(text: "row \(index)")),
                timestamp: "2026-11-08T21:00:00.000Z",
                seqStart: index,
                seqEnd: index)
        }
    }

    @Test func aPureAppendIntoTheLastTurnBuildsOneTurn() {
        let rows = makeRows(500)
        let incremental = IncrementalTurnBuilder()
        _ = incremental.turns(from: rows, activeTurnId: nil)

        let appended = rows + [
            TimelineRow(
                id: "seq:500", turnId: "t49",
                item: .assistantMessage(.init(text: "new")),
                timestamp: "2026-11-08T21:00:01.000Z", seqStart: 500, seqEnd: 500)
        ]
        let actual = incremental.turns(from: appended, activeTurnId: nil)

        #expect(actual == TurnBuilder.turns(from: appended, activeTurnId: nil))
        #expect(incremental.turnsBuiltLastUpdate == 1, "general path rebuilds only the last turn")
        #expect(
            incremental.rowsComparedLastUpdate <= 2,
            "the precheck bails before the O(rows) equality walk")
    }

    @Test func aPureAppendStartingANewTurnBuildsTwoTurns() {
        let rows = makeRows(500)
        let incremental = IncrementalTurnBuilder()
        _ = incremental.turns(from: rows, activeTurnId: nil)

        let appended = rows + [
            TimelineRow(
                id: "seq:500", turnId: "t50",
                item: .assistantMessage(.init(text: "new turn")),
                timestamp: "2026-11-08T21:00:01.000Z", seqStart: 500, seqEnd: 500)
        ]
        let actual = incremental.turns(from: appended, activeTurnId: nil)

        #expect(actual == TurnBuilder.turns(from: appended, activeTurnId: nil))
        #expect(incremental.turnsBuiltLastUpdate == 2, "general path rebuilds the last turn plus the new one")
        #expect(
            incremental.rowsComparedLastUpdate <= 2,
            "the precheck bails before the O(rows) equality walk")
    }
}
