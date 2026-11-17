import Foundation
import PaseoProtocol
import Testing

@testable import PaseoProtocol
@testable import PaseoStore

/// `IncrementalTurnBuilder` reuses the turns after the first one when a history page is prepended
/// (`turnsAfterPrepend`). The result must equal a full `TurnBuilder` walk exactly, and the prepend
/// must not rebuild the whole transcript. This is a Core change with no upstream counterpart.
@Suite struct PrependRebuildTests {
    // MARK: - Deterministic RNG

    /// A seeded linear congruential generator (Knuth's MMIX constants). No dependencies.
    private struct LCG {
        private var state: UInt64

        init(seed: UInt64) { state = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493 }

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }

        /// A value in `range`, or `range.lowerBound` for an empty range.
        mutating func int(_ range: Range<Int>) -> Int {
            guard !range.isEmpty else { return range.lowerBound }
            return range.lowerBound + Int(next() % UInt64(range.count))
        }
    }

    // MARK: - Row source

    /// Builds timelines with turn runs, rows without a `turnId` (some of them user messages), and
    /// every item kind the walk treats differently. Tool call ids are unique across the source.
    private struct RowSource {
        var rng: LCG
        var callCounter = 0

        static let turnPool = ["t0", "t1", "t2", "t3"]
        static let timestamp = "2026-11-08T21:00:00.000Z"

        mutating func rows(count: Int, firstSeq: Int) -> [TimelineRow] {
            var rows: [TimelineRow] = []
            var currentTurn: String?
            for offset in 0..<count {
                // The turn changes now and then, and is sometimes missing on a row.
                if rng.int(0..<4) == 0 {
                    currentTurn = rng.int(0..<5) == 0 ? nil : Self.turnPool[rng.int(0..<Self.turnPool.count)]
                }
                let turnId = rng.int(0..<6) == 0 ? nil : currentTurn
                let seq = firstSeq + offset
                let item = makeItem()
                let id: String
                if case .toolCall(let call) = item {
                    id = "tool:\(call.callId)"
                } else {
                    id = "seq:\(seq)"
                }
                rows.append(
                    TimelineRow(
                        id: id, turnId: turnId, item: item, timestamp: Self.timestamp,
                        seqStart: seq, seqEnd: seq))
            }
            return rows
        }

        private mutating func makeItem() -> TimelineItem {
            switch rng.int(0..<9) {
            case 0: return .userMessage(.init(text: "u\(rng.int(0..<50))"))
            case 1: return .assistantMessage(.init(text: "a\(rng.int(0..<50))"))
            case 2: return .reasoning(.init(text: "r\(rng.int(0..<50))"))
            case 3, 4:
                callCounter += 1
                let status: ToolCall.Status = rng.int(0..<3) == 0 ? .failed : .running
                return .toolCall(
                    ToolCall(
                        callId: "call\(callCounter)", name: "Bash", status: status,
                        detail: .shell(command: "ls", cwd: nil, output: nil, exitCode: nil)))
            case 5: return .todo(TimelineItem.TodoList(items: []))
            case 6: return .error(message: "e\(rng.int(0..<50))")
            case 7: return .notification(level: "info", message: "n\(rng.int(0..<50))")
            default: return .compaction(status: "compacted")
            }
        }
    }

    private static func activeChoice(_ rng: inout LCG) -> String? {
        switch rng.int(0..<5) {
        case 0: return nil
        default: return RowSource.turnPool[rng.int(0..<RowSource.turnPool.count)]
        }
    }

    /// A plain assistant row, as the comparison tests build them.
    private static func assistantRow(seq: Int, turnId: String?) -> TimelineRow {
        TimelineRow(
            id: "seq:\(seq)", turnId: turnId,
            item: .assistantMessage(.init(text: "row \(seq)")),
            timestamp: "2026-11-08T21:00:00.000Z", seqStart: seq, seqEnd: seq)
    }

    // MARK: - Randomized equivalence

    @Test func randomPrependsEqualAFullRebuild() {
        var reusedPrepends = 0
        for seed in UInt64(1)...300 {
            var source = RowSource(rng: LCG(seed: seed))
            var choices = LCG(seed: seed &+ 99)
            let incremental = IncrementalTurnBuilder()

            var rows = source.rows(count: choices.int(0..<40), firstSeq: 1000)
            var active = Self.activeChoice(&choices)
            _ = incremental.turns(from: rows, activeTurnId: active)

            for step in 0..<4 {
                let isPrepend = choices.int(0..<10) < 6
                var next: [TimelineRow]
                if isPrepend {
                    let page = source.rows(
                        count: 1 + choices.int(0..<8), firstSeq: (rows.first?.seqStart ?? 1000) - 50)
                    next = page + rows
                } else {
                    next = rows + source.rows(
                        count: 1 + choices.int(0..<3), firstSeq: (rows.last?.seqStart ?? 1000) + 1)
                }
                if choices.int(0..<3) == 0 { active = Self.activeChoice(&choices) }

                let got = incremental.turns(from: next, activeTurnId: active)
                let want = TurnBuilder.turns(from: next, activeTurnId: active)
                #expect(got == want, "seed \(seed), step \(step), prepend \(isPrepend)")
                if isPrepend, !rows.isEmpty, incremental.turnsBuiltLastUpdate < want.count {
                    reusedPrepends += 1
                }
                rows = next
            }
        }
        // The reuse path must be the common case, or the test proves little.
        #expect(reusedPrepends > 100, "reused \(reusedPrepends) prepends")
    }

    // MARK: - Deterministic cases

    /// The old first row has no `turnId` and is not a user message, so it joined no draft: its key was
    /// `untracked:<id>`. After the prepend it joins the prepended page's last turn. Reusing the old
    /// second turn would split one turn in two, so this must take the general path.
    @Test func aPrependedPageThatJoinsAnUntrackedFirstRowIsRebuilt() {
        let incremental = IncrementalTurnBuilder()
        let rows = [
            Self.assistantRow(seq: 10, turnId: nil),
            Self.assistantRow(seq: 11, turnId: "A"),
        ]
        _ = incremental.turns(from: rows, activeTurnId: nil)

        let prepended = [Self.assistantRow(seq: 5, turnId: "A")] + rows
        let got = incremental.turns(from: prepended, activeTurnId: nil)
        #expect(got == TurnBuilder.turns(from: prepended, activeTurnId: nil))
        #expect(got.count == 1, "the page, the untracked row and the old second row are one turn")
    }

    @Test func aPrependReusesTheTurnsAfterTheFirstOne() {
        let rows = (0..<500).map { index in
            Self.assistantRow(seq: index, turnId: "t\(index / 10)")
        }
        let incremental = IncrementalTurnBuilder()
        _ = incremental.turns(from: rows, activeTurnId: nil)

        let page = (-3 ..< 0).map { Self.assistantRow(seq: $0, turnId: "older") }
        let prepended = page + rows
        let got = incremental.turns(from: prepended, activeTurnId: nil)

        #expect(got == TurnBuilder.turns(from: prepended, activeTurnId: nil))
        // The page and the first old turn are rebuilt: 2 of 51 turns.
        #expect(incremental.turnsBuiltLastUpdate == 2)
        #expect(got.count == 51)
    }

    @Test func aPrependThatJoinsTheFirstTurnRebuildsOnlyThatTurn() {
        // The page continues turn t0. The old first turn is the only one rebuilt.
        let rows = (0..<500).map { index in
            Self.assistantRow(seq: index, turnId: "t\(index / 10)")
        }
        let incremental = IncrementalTurnBuilder()
        _ = incremental.turns(from: rows, activeTurnId: nil)

        let page = (-2 ..< 0).map { Self.assistantRow(seq: $0, turnId: "t0") }
        let prepended = page + rows
        let got = incremental.turns(from: prepended, activeTurnId: nil)

        #expect(got == TurnBuilder.turns(from: prepended, activeTurnId: nil))
        #expect(incremental.turnsBuiltLastUpdate == 1)
        #expect(got.count == 50)
    }

    @Test func aPrependWithANewActiveTurnRefreshesTheTurnsThatNeedIt() {
        let rows = (0..<100).map { index in
            Self.assistantRow(seq: index, turnId: "t\(index / 10)")
        }
        let incremental = IncrementalTurnBuilder()
        _ = incremental.turns(from: rows, activeTurnId: nil)

        // The running turn is one the reader already has: its phase comes from the new active id.
        let page = (-2 ..< 0).map { Self.assistantRow(seq: $0, turnId: "older") }
        let running = page + rows
        let runningGot = incremental.turns(from: running, activeTurnId: "t3")
        #expect(runningGot == TurnBuilder.turns(from: running, activeTurnId: "t3"))
        #expect(runningGot.first { $0.turnId == "t3" }?.phase == .running)

        // The active turn ends: the old running turn returns to completed, with the next prepend.
        let older = (-4 ..< -2).map { Self.assistantRow(seq: $0, turnId: "older0") }
        let ended = older + running
        let endedGot = incremental.turns(from: ended, activeTurnId: nil)
        #expect(endedGot == TurnBuilder.turns(from: ended, activeTurnId: nil))
        #expect(endedGot.first { $0.turnId == "t3" }?.phase == .completed)
    }

    // MARK: - TimelineState path

    /// Wire page builder for `TimelineState.applyPage`. Each entry is `(item JSON, seq)`.
    private static func page(
        direction: String, epoch: String, entries: [(item: String, seq: Int, turnId: String)],
        nextSeq: Int, hasOlder: Bool
    ) throws -> FetchAgentTimelineRequest.Response {
        let rows = entries.map { entry in
            #"{"provider":"pi","item":\#(entry.item),"turnId":"\#(entry.turnId)","timestamp":"2026-11-08T21:00:00.000Z","seqStart":\#(entry.seq),"seqEnd":\#(entry.seq)}"#
        }.joined(separator: ",")
        let json = #"""
            {"requestId":"r","agentId":"agent-1","direction":"\#(direction)","epoch":"\#(epoch)",
             "reset":false,"staleCursor":false,"gap":false,
             "window":{"minSeq":0,"maxSeq":\#(nextSeq - 1),"nextSeq":\#(nextSeq)},
             "hasOlder":\#(hasOlder),"hasNewer":false,"entries":[\#(rows)]}
            """#
        return try JSONDecoder().decode(FetchAgentTimelineRequest.Response.self, from: Data(json.utf8))
    }

    @Test func aStatePrependKeepsTheDigestAndTheIncrementalTurns() throws {
        let user = #"{"type":"user_message","text":"hi"}"#
        let assistant = #"{"type":"assistant_message","text":"ok"}"#
        let shell = #"{"type":"shell","command":"ls"}"#
        let failed = #"{"type":"tool_call","callId":"c1","name":"Bash","status":"failed","detail":\#(shell),"error":"boom"}"#
        let running = #"{"type":"tool_call","callId":"c2","name":"Agent","status":"running","detail":{"type":"sub_agent","subAgentType":"explore","description":"look","childSessionId":"child-1"}}"#
        let olderFailed = #"{"type":"tool_call","callId":"c0","name":"Bash","status":"failed","detail":\#(shell),"error":"boom"}"#

        var state = TimelineState()
        state.applyPage(
            try Self.page(
                direction: "tail", epoch: "e1",
                entries: [(user, 10, "t1"), (failed, 11, "t1"), (running, 12, "t1"), (assistant, 13, "t1")],
                nextSeq: 14, hasOlder: true))

        let incremental = IncrementalTurnBuilder()
        _ = incremental.turns(from: state.rows, activeTurnId: "t1")

        state.applyPage(
            try Self.page(
                direction: "before", epoch: "e1",
                entries: [(user, 1, "t0"), (olderFailed, 2, "t0"), (assistant, 3, "t0")],
                nextSeq: 4, hasOlder: false))

        // The digest is the full-scan value: the prepended failure comes first, in row order.
        #expect(state.failedToolCalls == [
            TimelineState.FailedToolCall(callId: "c0", seq: 2),
            TimelineState.FailedToolCall(callId: "c1", seq: 11),
        ])
        #expect(state.runningSubAgentCount == 1)
        #expect(state.latestPromptSeq == 10, "the newest prompt is in the tail, not the page")
        #expect(state.rows.map(\.seqStart) == [1, 2, 3, 10, 11, 12, 13])

        let got = incremental.turns(from: state.rows, activeTurnId: "t1")
        #expect(got == TurnBuilder.turns(from: state.rows, activeTurnId: "t1"))
        // The page's turn and the old first turn make up the whole rebuilt prefix here.
        #expect(incremental.turnsBuiltLastUpdate == 2)
    }
}
