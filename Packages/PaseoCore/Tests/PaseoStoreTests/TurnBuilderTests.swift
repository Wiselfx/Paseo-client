import Foundation
import Testing
import PaseoProtocol
@testable import PaseoStore

/// Acceptance tests for T3. Do not weaken these to make an implementation pass.
@Suite struct TurnBuilderTests {
    @Test func fixtureTimelineBecomesTwoTurns() throws {
        let rows = Load.rows(try Load.page().entries)
        let turns = TurnBuilder.turns(from: rows, activeTurnId: nil)
        #expect(turns.count == 2)

        // Turn 1 starts with a tool call (a system prompt delivered as a tool), so no user message.
        #expect(turns[0].userMessage == nil)
        #expect(turns[0].segments.count == 2)
        guard case .work(let firstWork) = turns[0].segments[0], case .prose = turns[0].segments[1] else {
            Issue.record("turn 1 should be [work, prose]"); return
        }
        #expect(firstWork.toolCallCount == 1)
        #expect(firstWork.thoughtCount == 1)

        // Turn 2: user message, then reasoning + 5 tools + reasoning as ONE work group, then prose.
        let turn = turns[1]
        guard case .userMessage(let message)? = turn.userMessage?.item else { Issue.record("missing user message"); return }
        #expect(message.text.hasPrefix("Think briefly first"))
        #expect(turn.segments.count == 2)
        guard case .work(let work) = turn.segments[0], case .prose(let prose) = turn.segments[1] else {
            Issue.record("turn 2 should be [work, prose]"); return
        }
        #expect(work.thoughtCount == 2)
        #expect(work.toolCallCount == 5)
        #expect(!work.isActive)
        #expect(prose.seqStart == 18)
        #expect(turn.phase == .completed)
        #expect(turn.id == "47c9ec71-6933-42d8-b8c9-8984cc788c70")
        let duration = try #require(turn.duration)
        #expect(duration >= 0 && duration < 600)
    }

    @Test func activeTurnIsRunning() throws {
        let rows = Load.rows(try Load.page().entries)
        let turns = TurnBuilder.turns(from: rows, activeTurnId: "47c9ec71-6933-42d8-b8c9-8984cc788c70")
        #expect(turns[1].phase == .running)
        #expect(turns[1].endedAt == nil)
        #expect(turns[0].phase == .completed)
    }

    @Test func errorFailsTheTurn() {
        let rows = [
            row("seq:1", "t1", .userMessage(.init(text: "hi"))),
            row("seq:2", "t1", .error(message: "rate limited")),
        ]
        let turns = TurnBuilder.turns(from: rows, activeTurnId: nil)
        #expect(turns.first?.phase == .failed("rate limited"))
        #expect(turns.first?.segments.count == 1)
    }

    @Test func proseSplitsWorkGroups() {
        let rows = [
            row("seq:1", "t1", .reasoning(.init(text: "a"))),
            row("seq:2", "t1", .assistantMessage(.init(text: "checking"))),
            row("seq:3", "t1", .reasoning(.init(text: "b"))),
        ]
        let segments = TurnBuilder.turns(from: rows, activeTurnId: nil).first?.segments ?? []
        #expect(segments.map(\.id) == ["work:seq:1", "seq:2", "work:seq:3"])
    }

    @Test func rowsWithoutTurnIdJoinThePreviousTurn() {
        let rows = [
            row("seq:1", nil, .notification(level: "info", message: "orphan first")),
            row("seq:2", "t1", .userMessage(.init(text: "hi"))),
            row("seq:3", nil, .assistantMessage(.init(text: "hello"))),
        ]
        let turns = TurnBuilder.turns(from: rows, activeTurnId: nil)
        #expect(turns.map(\.id) == ["orphan:seq:1", "t1"])
        #expect(turns[1].segments.map(\.id) == ["seq:3"])
    }

    private func row(_ id: String, _ turnId: String?, _ item: TimelineItem) -> TimelineRow {
        let seq = Int(id.split(separator: ":").last!)!
        return TimelineRow(id: id, turnId: turnId, item: item, timestamp: "2026-11-08T21:00:0\(seq).000Z", seqStart: seq, seqEnd: seq)
    }
}
