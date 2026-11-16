import Foundation
import PaseoProtocol
import Testing

@testable import PaseoStore

/// R3 §1: the `TimelineState` digest must equal a full scan of `rows` after every mutation, and the
/// live paths must keep it up incrementally.
@Suite struct TimelineDigestTests {
    // MARK: - Deterministic RNG

    /// SplitMix64: small, seeded, no dependencies. Same generator as `IncrementalTurnBuilderTests`.
    private struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(in range: Range<Int>) -> Int {
            precondition(!range.isEmpty)
            return range.lowerBound + Int(next() % UInt64(range.count))
        }
        mutating func bool() -> Bool { next() & 1 == 1 }
    }

    // MARK: - Wire builders

    private static let decoder = JSONDecoder()
    private static let shellDetail = #"{"type":"shell","command":"ls"}"#
    private static let subAgentDetail =
        #"{"type":"sub_agent","subAgentType":"explore","description":"look","childSessionId":"child-1"}"#

    private static func reasoning(_ text: String = "r") -> String {
        #"{"type":"reasoning","text":"\#(text)"}"#
    }

    private static func assistant(_ text: String = "a") -> String {
        #"{"type":"assistant_message","text":"\#(text)"}"#
    }

    private static func todo(_ text: String = "step") -> String {
        #"{"type":"todo","items":[{"text":"\#(text)","completed":false}]}"#
    }

    private static func compaction(_ status: String) -> String {
        #"{"type":"compaction","status":"\#(status)"}"#
    }

    private static func userMessage(_ text: String = "hi", clientMessageId: String? = nil) -> String {
        let idField = clientMessageId.map { ",\"clientMessageId\":\"\($0)\"" } ?? ""
        return #"{"type":"user_message","text":"\#(text)"\#(idField)}"#
    }

    private static func toolCall(
        _ callId: String, status: String, detail: String = shellDetail, error: String? = nil
    ) -> String {
        let errorField = error.map { ",\"error\":\($0)" } ?? ""
        return #"{"type":"tool_call","callId":"\#(callId)","name":"Bash","status":"\#(status)","detail":\#(detail)\#(errorField)}"#
    }

    /// One live `agent_stream` timeline delta.
    private static func streamPayload(
        seq: Int, epoch: String?, item: String, turnId: String? = "t1"
    ) throws -> AgentStreamPayload {
        let turn = turnId.map { "\"\($0)\"" } ?? "null"
        let epochField = epoch.map { ",\"epoch\":\"\($0)\"" } ?? ""
        let json = #"""
            {"agentId":"agent-1","event":{"type":"timeline","item":\#(item),"turnId":\#(turn)},
             "timestamp":"2026-11-08T21:00:00.000Z","seq":\#(seq)\#(epochField)}
            """#
        return try decoder.decode(AgentStreamPayload.self, from: Data(json.utf8))
    }

    /// One projected page, one entry per `(item, seq)` pair, each row covering a single seq.
    private static func page(
        epoch: String,
        direction: String = "tail",
        entries: [(item: String, seq: Int)],
        maxSeq: Int,
        nextSeq: Int,
        hasOlder: Bool = false,
        reset: Bool = false
    ) throws -> FetchAgentTimelineRequest.Response {
        let rows = entries.map { entry in
            #"""
            {"provider":"pi","item":\#(entry.item),"turnId":"t1",
             "timestamp":"2026-11-08T21:00:00.000Z","seqStart":\#(entry.seq),"seqEnd":\#(entry.seq)}
            """#
        }
        .joined(separator: ",")
        let json = #"""
            {"requestId":"r","agentId":"agent-1","direction":"\#(direction)","epoch":"\#(epoch)",
             "reset":\#(reset),"staleCursor":false,"gap":false,
             "window":{"minSeq":0,"maxSeq":\#(maxSeq),"nextSeq":\#(nextSeq)},
             "hasOlder":\#(hasOlder),"hasNewer":false,"entries":[\#(rows)]}
            """#
        return try decoder.decode(
            FetchAgentTimelineRequest.Response.self, from: Data(json.utf8))
    }

    /// A state with an empty tail page loaded, so live deltas apply from `seq`.
    private static func emptyState(epoch: String = "e1", nextSeq: Int = 1) throws -> TimelineState {
        var state = TimelineState()
        state.applyPage(
            try page(epoch: epoch, entries: [], maxSeq: nextSeq - 1, nextSeq: nextSeq))
        return state
    }

    // MARK: - Reference full scans (the definition the digest must match)

    private static func referenceFailedCalls(
        in rows: [TimelineRow]
    ) -> [TimelineState.FailedToolCall] {
        rows.compactMap { row in
            guard case .toolCall(let call) = row.item, MascotToolError.isFailure(call) else {
                return nil
            }
            return TimelineState.FailedToolCall(callId: call.callId, seq: row.seqEnd)
        }
    }

    private static func referenceRunningSubAgents(in rows: [TimelineRow]) -> Int {
        rows.filter { row in
            guard case .toolCall(let call) = row.item, call.status == .running,
                case .subAgent = call.detail
            else { return false }
            return true
        }.count
    }

    private static func referenceLastCompaction(in rows: [TimelineRow]) -> String? {
        for row in rows.reversed() {
            if case .compaction(let status, _, _) = row.item { return status }
        }
        return nil
    }

    private static func referenceLatestKind(in rows: [TimelineRow]) -> TimelineState.RowKind? {
        guard let last = rows.last else { return nil }
        switch last.item {
        case .reasoning: return .reasoning
        case .toolCall: return .toolCall
        default: return .other
        }
    }

    private static func expectDigest(_ state: TimelineState, step: Int) {
        #expect(
            state.failedToolCalls == referenceFailedCalls(in: state.rows),
            "step \(step): failed tool calls")
        #expect(
            state.runningSubAgentCount == referenceRunningSubAgents(in: state.rows),
            "step \(step): running subagents")
        #expect(
            state.lastCompactionStatus == referenceLastCompaction(in: state.rows),
            "step \(step): last compaction")
        #expect(
            state.latestRowKind == referenceLatestKind(in: state.rows),
            "step \(step): latest row kind")
        #expect(state.latestRowId == state.rows.last?.id, "step \(step): latest row id")

        // First row wins on a shared `seqEnd`, exactly like the map.
        var expected: [Int: Int] = [:]
        for (index, row) in state.rows.enumerated() where expected[row.seqEnd] == nil {
            expected[row.seqEnd] = index
        }
        var matched = true
        for (seq, index) in expected where state.rowIndex(forSeqEnd: seq) != index {
            matched = false
        }
        #expect(matched, "step \(step): seqEnd index")
        #expect(state.rowIndex(forSeqEnd: -1) == nil, "step \(step): never-used seqEnd")
    }

    // MARK: - Property test

    /// Random stream deltas, status changes, pages, prepends, pending sends and resets. After every
    /// single step the digest must match the reference scan.
    @Test func theDigestEqualsAFullScanAfterEveryStep() throws {
        var rng = SplitMix64(seed: 0x5EED_1234)
        var state = try Self.emptyState()
        var epoch = "e1"
        var epochCounter = 1
        var callCounter = 0
        var clientCounter = 0
        var calls: [String] = []
        var pending: [String] = []

        for step in 0..<3200 {
            // Bound the transcript so the reference scans stay cheap; a reset replaces the rows.
            if state.rows.count > 48 {
                epochCounter += 1
                epoch = "e\(epochCounter)"
                let base = (state.nextSeq ?? 1) + 1
                state.applyPage(
                    try Self.page(
                        epoch: epoch,
                        entries: [(Self.reasoning("fresh"), base), (Self.todo(), base + 1)],
                        maxSeq: base + 1, nextSeq: base + 2, reset: true))
            }

            switch rng.int(in: 0..<20) {
            case 0..<6:
                // Text streams onto the tail, or starts a new row.
                guard let seq = state.nextSeq else { break }
                let item = rng.bool() ? Self.reasoning("r") : Self.assistant("a")
                let payload = try Self.streamPayload(seq: seq, epoch: state.epoch, item: item)
                #expect(state.applyStream(payload) == .applied, "step \(step): text")

            case 6..<10:
                // A tool call starts, or an existing one changes status in place.
                guard let seq = state.nextSeq else { break }
                let item: String
                if !calls.isEmpty, rng.int(in: 0..<3) != 0 {
                    let callId = calls[rng.int(in: 0..<calls.count)]
                    let status = ["running", "completed", "failed", "canceled"][rng.int(in: 0..<4)]
                    let detail = rng.int(in: 0..<3) == 0 ? Self.subAgentDetail : Self.shellDetail
                    let error: String? =
                        if status != "failed" {
                            nil
                        } else if rng.bool() {
                            #""AbortError: stopped""#
                        } else {
                            #""boom""#
                        }
                    item = Self.toolCall(callId, status: status, detail: detail, error: error)
                } else {
                    callCounter += 1
                    calls.append("c\(callCounter)")
                    item = Self.toolCall(
                        "c\(callCounter)", status: "running",
                        detail: rng.bool() ? Self.subAgentDetail : Self.shellDetail)
                }
                let payload = try Self.streamPayload(seq: seq, epoch: state.epoch, item: item)
                #expect(state.applyStream(payload) == .applied, "step \(step): tool call")

            case 10:
                guard let seq = state.nextSeq else { break }
                let payload = try Self.streamPayload(
                    seq: seq, epoch: state.epoch,
                    item: Self.compaction(rng.bool() ? "loading" : "completed"))
                #expect(state.applyStream(payload) == .applied, "step \(step): compaction")

            case 11:
                // The daemon echoes a pending send, confirming it in place; or a plain user row.
                guard let seq = state.nextSeq else { break }
                let item: String
                if !pending.isEmpty, rng.bool() {
                    let clientId = pending.removeFirst()
                    item = Self.userMessage("echo", clientMessageId: clientId)
                } else {
                    item = Self.userMessage("plain")
                }
                let payload = try Self.streamPayload(seq: seq, epoch: state.epoch, item: item)
                #expect(state.applyStream(payload) == .applied, "step \(step): user message")

            case 12, 13:
                clientCounter += 1
                let clientId = "local\(clientCounter)"
                pending.append(clientId)
                state.addPendingUserMessage(
                    text: "pending \(clientCounter)", clientMessageId: clientId,
                    timestamp: "2026-11-08T21:00:00.000Z")

            case 14:
                guard !pending.isEmpty else { break }
                let clientId = pending.removeFirst()
                state.removePendingUserMessage(clientMessageId: clientId)

            default:
                // Pages: a fresh tail, a prepend of older rows, or an epoch reset.
                let choice = rng.int(in: 0..<3)
                if choice == 0 {
                    let base = state.nextSeq ?? 1
                    state.applyPage(
                        try Self.page(
                            epoch: epoch,
                            entries: [
                                (Self.reasoning("page"), base),
                                (
                                    Self.toolCall(
                                        "page\(base)", status: "running",
                                        detail: Self.subAgentDetail),
                                    base + 1
                                ),
                            ],
                            maxSeq: base + 1, nextSeq: base + 2, hasOlder: rng.bool()))
                } else if choice == 1, let start = state.startCursor, start.seq > 2 {
                    state.applyPage(
                        try Self.page(
                            epoch: epoch, direction: "before",
                            entries: [
                                (Self.assistant("old"), start.seq - 2),
                                (Self.compaction("completed"), start.seq - 1),
                            ],
                            maxSeq: state.nextSeq ?? start.seq, nextSeq: state.nextSeq ?? start.seq,
                            hasOlder: rng.bool()))
                } else {
                    epochCounter += 1
                    epoch = "e\(epochCounter)"
                    let base = (state.nextSeq ?? 1) + 1
                    state.applyPage(
                        try Self.page(
                            epoch: epoch,
                            entries: [(Self.reasoning("reset"), base), (Self.todo(), base + 1)],
                            maxSeq: base + 1, nextSeq: base + 2, reset: true))
                }
            }

            Self.expectDigest(state, step: step)
        }
    }

    // MARK: - Targeted cases

    @Test func aToolCallThatFailsIsListed() throws {
        var state = try Self.emptyState()
        #expect(
            state.applyStream(
                try Self.streamPayload(
                    seq: 1, epoch: state.epoch, item: Self.toolCall("c1", status: "running")))
                == .applied)
        #expect(state.failedToolCalls.isEmpty)
        #expect(state.runningSubAgentCount == 0)
        #expect(state.latestRowKind == .toolCall)
        #expect(state.latestRowId == "tool:c1")

        #expect(
            state.applyStream(
                try Self.streamPayload(
                    seq: 2, epoch: state.epoch,
                    item: Self.toolCall("c1", status: "failed", error: #""boom""#)))
                == .applied)
        #expect(state.failedToolCalls == [TimelineState.FailedToolCall(callId: "c1", seq: 2)])
        #expect(state.rowIndex(forSeqEnd: 2) == 0)
        #expect(state.rowIndex(forSeqEnd: 1) == nil, "the row's old seqEnd is gone")
    }

    @Test func anAbortErrorIsNotAFailure() throws {
        var state = try Self.emptyState()
        #expect(
            state.applyStream(
                try Self.streamPayload(
                    seq: 1, epoch: state.epoch,
                    item: Self.toolCall("c1", status: "failed", error: #""AbortError: stopped""#)))
                == .applied)
        #expect(state.failedToolCalls.isEmpty)
        #expect(state.latestRowKind == .toolCall)
    }

    @Test func aSubagentStopsCountingWhenItCompletes() throws {
        var state = try Self.emptyState()
        #expect(
            state.applyStream(
                try Self.streamPayload(
                    seq: 1, epoch: state.epoch,
                    item: Self.toolCall(
                        "c1", status: "running", detail: Self.subAgentDetail)))
                == .applied)
        #expect(state.runningSubAgentCount == 1)

        #expect(
            state.applyStream(
                try Self.streamPayload(
                    seq: 2, epoch: state.epoch,
                    item: Self.toolCall(
                        "c1", status: "completed", detail: Self.subAgentDetail)))
                == .applied)
        #expect(state.runningSubAgentCount == 0)
    }

    @Test func theLastCompactionStatusTracksTheLastRow() throws {
        var state = try Self.emptyState()
        #expect(
            state.applyStream(
                try Self.streamPayload(
                    seq: 1, epoch: state.epoch, item: Self.compaction("loading")))
                == .applied)
        #expect(state.lastCompactionStatus == "loading")

        #expect(
            state.applyStream(
                try Self.streamPayload(
                    seq: 2, epoch: state.epoch, item: Self.compaction("completed")))
                == .applied)
        #expect(state.lastCompactionStatus == "completed")

        // A rewriting page recomputes from the rows, so an older row cannot keep the lead.
        state.applyPage(
            try Self.page(
                epoch: state.epoch ?? "e1",
                entries: [(Self.compaction("completed"), 2), (Self.reasoning("after"), 3)],
                maxSeq: 3, nextSeq: 4))
        #expect(state.lastCompactionStatus == "completed")
        #expect(state.latestRowKind == .reasoning)
    }

    @Test func rowIndexFollowsAPrepend() throws {
        var state = TimelineState()
        state.applyPage(
            try Self.page(
                epoch: "e1",
                entries: [(Self.assistant("tail"), 10), (Self.assistant("tail 2"), 11)],
                maxSeq: 11, nextSeq: 12, hasOlder: true))
        #expect(state.rowIndex(forSeqEnd: 10) == 0)
        #expect(state.rowIndex(forSeqEnd: 11) == 1)

        state.applyPage(
            try Self.page(
                epoch: "e1", direction: "before",
                entries: [(Self.assistant("older"), 8), (Self.assistant("older 2"), 9)],
                maxSeq: 11, nextSeq: 12, hasOlder: false))
        #expect(state.rows.map(\.seqEnd) == [8, 9, 10, 11])
        #expect(state.rowIndex(forSeqEnd: 8) == 0)
        #expect(state.rowIndex(forSeqEnd: 10) == 2, "the prepended rows shift the tail")
        #expect(state.rowIndex(forSeqEnd: 11) == 3)
    }

    @Test func anEpochResetRebuildsTheDigest() throws {
        var state = try Self.emptyState()
        #expect(
            state.applyStream(
                try Self.streamPayload(
                    seq: 1, epoch: state.epoch,
                    item: Self.toolCall("c1", status: "failed", error: #""boom""#)))
                == .applied)
        #expect(
            state.applyStream(
                try Self.streamPayload(
                    seq: 2, epoch: state.epoch,
                    item: Self.toolCall(
                        "c2", status: "running", detail: Self.subAgentDetail)))
                == .applied)
        #expect(!state.failedToolCalls.isEmpty)
        #expect(state.runningSubAgentCount == 1)

        state.applyPage(
            try Self.page(
                epoch: "e2", entries: [(Self.reasoning("new epoch"), 5)],
                maxSeq: 5, nextSeq: 6, reset: true))
        #expect(state.failedToolCalls.isEmpty)
        #expect(state.runningSubAgentCount == 0)
        #expect(state.lastCompactionStatus == nil)
        #expect(state.latestRowKind == .reasoning)
        #expect(state.rowIndex(forSeqEnd: 5) == 0)
        #expect(state.rowIndex(forSeqEnd: 1) == nil)
    }
}
