import Foundation
import PaseoProtocol
import Testing

@testable import PaseoProtocol
@testable import PaseoStore

/// P5-A: the incremental builder must not walk the whole transcript on a streamed token.
/// `TimelineState.appendText` bumps `seqEnd` on every token, so the cheap row version is
/// enough to find the changed run.
@Suite struct IncrementalTurnBuilderComparisonTests {
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

    @Test func aTailTokenComparesOnlyTheChangedRun() {
        let rows = makeRows(500)
        let incremental = IncrementalTurnBuilder()
        _ = incremental.turns(from: rows, activeTurnId: nil)

        var updated = rows
        let last = updated.count - 1
        if case .assistantMessage(var message) = updated[last].item {
            message.text += "x"
            updated[last].item = .assistantMessage(message)
        }
        updated[last].seqEnd = 999

        _ = incremental.turns(from: updated, activeTurnId: nil)

        #expect(incremental.turnsBuiltLastUpdate <= 2)
        #expect(incremental.rowsComparedLastUpdate <= 3, "a tail token must not scan the transcript")
        #expect(
            incremental.turns(from: updated, activeTurnId: nil)
                == TurnBuilder.turns(from: updated, activeTurnId: nil))
    }

    @Test func aPureAppendDoesNotScanTheTranscript() {
        let rows = makeRows(500)
        let incremental = IncrementalTurnBuilder()
        _ = incremental.turns(from: rows, activeTurnId: nil)

        let appended = rows + [
            TimelineRow(
                id: "seq:999", turnId: "t49",
                item: .assistantMessage(.init(text: "new")),
                timestamp: "2026-11-08T21:00:01.000Z", seqStart: 999, seqEnd: 999)
        ]

        _ = incremental.turns(from: appended, activeTurnId: nil)

        #expect(incremental.turnsBuiltLastUpdate <= 2)
        #expect(incremental.rowsComparedLastUpdate <= 2)
        #expect(
            incremental.turns(from: appended, activeTurnId: nil)
                == TurnBuilder.turns(from: appended, activeTurnId: nil))
    }

    @Test func aContentOnlyRewriteAtTheTailIsFound() {
        var rows = makeRows(500)
        // A tool call in the tail whose status fills in without moving its seq.
        rows[498].item = .toolCall(ToolCall(
            callId: "call-498", name: "Bash", status: .running,
            detail: .shell(command: "ls", cwd: nil, output: nil, exitCode: nil)))
        let incremental = IncrementalTurnBuilder()
        _ = incremental.turns(from: rows, activeTurnId: nil)

        var updated = rows
        updated[498].item = .toolCall(ToolCall(
            callId: "call-498", name: "Bash", status: .completed,
            detail: .shell(command: "ls", cwd: nil, output: nil, exitCode: nil)))
        // A real token on the last row, so the fast path walks the tail.
        updated[499].seqEnd = 999

        let turns = incremental.turns(from: updated, activeTurnId: nil)

        #expect(turns == TurnBuilder.turns(from: updated, activeTurnId: nil))
        #expect(incremental.rowsComparedLastUpdate <= 4, "the rewrite is at the tail")
    }

    @Test func aMiddleEditStillWalksForward() {
        let rows = makeRows(500)
        let incremental = IncrementalTurnBuilder()
        _ = incremental.turns(from: rows, activeTurnId: nil)

        var edited = rows
        edited[10].seqEnd = 999

        _ = incremental.turns(from: edited, activeTurnId: nil)

        #expect(incremental.rowsComparedLastUpdate > 2)
        #expect(
            incremental.turns(from: edited, activeTurnId: nil)
                == TurnBuilder.turns(from: edited, activeTurnId: nil))
    }

    @Test func aPrependedPageIsAFullRebuild() {
        let rows = makeRows(500)
        let incremental = IncrementalTurnBuilder()
        _ = incremental.turns(from: rows, activeTurnId: nil)

        let prepended = [
            TimelineRow(
                id: "seq:-1", turnId: "t-1",
                item: .userMessage(.init(text: "older")),
                timestamp: "2026-11-08T20:59:59.000Z", seqStart: -1, seqEnd: -1)
        ] + rows

        _ = incremental.turns(from: prepended, activeTurnId: nil)

        #expect(incremental.rowsComparedLastUpdate > 2)
        #expect(
            incremental.turns(from: prepended, activeTurnId: nil)
                == TurnBuilder.turns(from: prepended, activeTurnId: nil))
    }
}
