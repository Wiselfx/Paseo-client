import Foundation
import PaseoProtocol

/// One row the conversation shows. Built from projected `TimelineEntry` pages and live
/// `agent_stream` deltas, which `TimelineState` merges into the same shape.
public struct TimelineRow: Sendable, Hashable, Identifiable {
    /// Stable across merges, so SwiftUI keeps view identity while text streams in:
    /// `tool:<callId>` for tool calls, `local:<clientMessageId>` for a pending user message,
    /// `seq:<seqStart>` for everything else.
    public var id: String
    public var turnId: String?
    public var item: TimelineItem
    /// ISO-8601, from the daemon.
    public var timestamp: String
    public var seqStart: Int
    public var seqEnd: Int
    /// A user message we showed before the daemon confirmed it.
    public var isPending: Bool

    public init(id: String, turnId: String?, item: TimelineItem, timestamp: String, seqStart: Int, seqEnd: Int, isPending: Bool = false) {
        self.id = id; self.turnId = turnId; self.item = item; self.timestamp = timestamp
        self.seqStart = seqStart; self.seqEnd = seqEnd; self.isPending = isPending
    }
}

/// The timeline of one agent as a pure value. No I/O: the store feeds it pages and stream
/// payloads and acts on what `applyStream` returns (e.g. fetch `.after` on a gap).
///
/// IMPLEMENTATION TICKET: docs/tickets/T2-timeline-reducer.md
public struct TimelineState: Sendable, Equatable {
    /// Identity of the daemon's timeline. Rows from different epochs never mix.
    public private(set) var epoch: String?
    /// Oldest first.
    public private(set) var rows: [TimelineRow]
    /// The `seq` the next live timeline event must carry. Nil until the first page arrives.
    public private(set) var nextSeq: Int?
    public private(set) var hasOlder: Bool

    public init() {
        epoch = nil
        rows = []
        nextSeq = nil
        hasOlder = false
    }

    public enum StreamResult: Sendable, Equatable {
        case applied
        /// Already covered by a page or an earlier event (`seq < nextSeq`). Nothing changed.
        case duplicate
        /// Events were missed. Nothing changed; the store must fetch `.after` from the last cursor.
        case gap(expected: Int, received: Int)
        /// Different epoch than ours. Nothing changed; the store must reload the tail.
        case epochChanged
        /// Not a timeline event, or no page loaded yet. Nothing changed.
        case ignored
    }

    /// Merges a fetched page. See T2 for tail/before/after and reset semantics.
    public mutating func applyPage(_ page: FetchAgentTimelineRequest.Response) {
        var pageRows = page.entries.map { Self.row(from: $0) }

        // A page can already contain a message we still show as pending (sent, then the page
        // was fetched before the stream echo arrived). Confirm it in place: the page row takes
        // the pending row's id so the bubble keeps its view identity.
        var pending = rows.filter(\.isPending)
        if !pending.isEmpty {
            for index in pageRows.indices {
                guard case .userMessage(let message) = pageRows[index].item, let clientId = message.clientMessageId,
                    let pendingIndex = pending.firstIndex(where: { $0.id == "local:\(clientId)" })
                else { continue }
                pageRows[index].id = pending[pendingIndex].id
                pending.remove(at: pendingIndex)
            }
        }

        if page.reset || (epoch != nil && epoch != page.epoch) {
            rows = pageRows + pending
        } else {
            let existing = rows.filter { !$0.isPending }
            let mergedIntervals = Self.mergeIntervals(pageRows.map { ($0.seqStart, $0.seqEnd) })
            let kept = existing.filter { !Self.overlapsAny($0.seqStart, $0.seqEnd, intervals: mergedIntervals) }
            var merged = kept + pageRows
            merged.sort { $0.seqStart < $1.seqStart }
            rows = merged + pending
        }

        epoch = page.epoch
        switch page.direction {
        case .tail, .after:
            nextSeq = page.window.nextSeq
        case .before:
            if nextSeq == nil { nextSeq = page.window.nextSeq }
        }
        switch page.direction {
        case .tail, .before:
            // A window merged in above the loaded range (U5 prompt jump) does not move the floor:
            // whatever was older before it is still older than it, so keep the flag as it was.
            if page.direction == .before, let pageStart = pageRows.first?.seqStart,
                let oldest = rows.first(where: { !$0.isPending })?.seqStart, pageStart > oldest
            {
                break
            }
            hasOlder = page.hasOlder
        case .after:
            break
        }
    }

    /// Applies one live event. See T2 for the merge rules.
    public mutating func applyStream(_ payload: AgentStreamPayload) -> StreamResult {
        guard case .timeline(let item, let turnId) = payload.event, let seq = payload.seq else {
            return .ignored
        }
        guard let expected = nextSeq else { return .ignored }
        if let payloadEpoch = payload.epoch, payloadEpoch != epoch { return .epochChanged }
        if seq < expected { return .duplicate }
        if seq > expected { return .gap(expected: expected, received: seq) }

        merge(item: item, turnId: turnId, seq: seq, timestamp: payload.timestamp)
        nextSeq = expected + 1
        return .applied
    }

    /// Shows a just-sent message immediately. Replaced when the daemon echoes a user_message
    /// with the same `clientMessageId`.
    public mutating func addPendingUserMessage(text: String, clientMessageId: String, timestamp: String) {
        let seq = nextSeq ?? 0
        let item = TimelineItem.userMessage(TimelineItem.UserMessage(text: text, clientMessageId: clientMessageId))
        rows.append(TimelineRow(id: "local:\(clientMessageId)", turnId: nil, item: item, timestamp: timestamp, seqStart: seq, seqEnd: seq, isPending: true))
    }

    /// Drops an optimistic user message that the daemon never accepted. A confirmed message is
    /// kept: only rows still marked pending are removed.
    public mutating func removePendingUserMessage(clientMessageId: String) {
        rows.removeAll { $0.isPending && $0.id == "local:\(clientMessageId)" }
    }

    private mutating func merge(item: TimelineItem, turnId: String?, seq: Int, timestamp: String) {
        switch item {
        case .reasoning:
            if appendText(seq: seq, turnId: turnId, text: reasoningText(item), isReasoning: true) { return }
        case .assistantMessage:
            if appendText(seq: seq, turnId: turnId, text: assistantText(item), isReasoning: false) { return }
        case .toolCall(let call):
            if let index = rows.firstIndex(where: { $0.id == "tool:\(call.callId)" }) {
                rows[index].item = Self.presentedItem(item)
                rows[index].seqEnd = seq
                return
            }
        case .userMessage(let message):
            if let clientMessageId = message.clientMessageId,
               let index = rows.firstIndex(where: { $0.isPending && $0.id == "local:\(clientMessageId)" }) {
                rows[index].item = item
                rows[index].isPending = false
                rows[index].seqStart = seq
                rows[index].seqEnd = seq
                rows[index].turnId = turnId
                rows[index].timestamp = timestamp
                return
            }
        default:
            break
        }
        appendRow(item: item, turnId: turnId, seq: seq, timestamp: timestamp)
    }

    private func reasoningText(_ item: TimelineItem) -> String? {
        if case .reasoning(let reasoning) = item { return reasoning.text }
        return nil
    }

    private func assistantText(_ item: TimelineItem) -> String? {
        if case .assistantMessage(let message) = item { return message.text }
        return nil
    }

    private mutating func appendText(seq: Int, turnId: String?, text: String?, isReasoning: Bool) -> Bool {
        guard let text, let index = rows.lastIndex(where: { !$0.isPending }) else { return false }
        guard rows[index].turnId == turnId else { return false }
        switch (isReasoning, rows[index].item) {
        case (true, .reasoning(var reasoning)):
            reasoning.text += text
            rows[index].item = .reasoning(reasoning)
        case (false, .assistantMessage(var message)):
            message.text += text
            rows[index].item = .assistantMessage(message)
        default:
            return false
        }
        rows[index].seqEnd = seq
        return true
    }

    private mutating func appendRow(item: TimelineItem, turnId: String?, seq: Int, timestamp: String) {
        let id: String
        if case .toolCall(let call) = item {
            id = "tool:\(call.callId)"
        } else {
            id = "seq:\(seq)"
        }
        let row = TimelineRow(id: id, turnId: turnId, item: Self.presentedItem(item), timestamp: timestamp, seqStart: seq, seqEnd: seq)
        if let lastNonPending = rows.lastIndex(where: { !$0.isPending }) {
            rows.insert(row, at: lastNonPending + 1)
        } else {
            rows.insert(row, at: 0)
        }
    }

    private static func row(from entry: TimelineEntry) -> TimelineRow {
        let id: String
        if case .toolCall(let call) = entry.item {
            id = "tool:\(call.callId)"
        } else {
            id = "seq:\(entry.seqStart)"
        }
        return TimelineRow(id: id, turnId: entry.turnId, item: Self.presentedItem(entry.item), timestamp: entry.timestamp, seqStart: entry.seqStart, seqEnd: entry.seqEnd, isPending: false)
    }

    /// Presentation projection (upstream `app/src/agent-stream/presentation.ts:88-103`): an
    /// agent-sourced tool call whose `agentMessage.event == "message"` renders as a user
    /// message with `text` + `sender` (row id keeps the tool-call id, like upstream
    /// `id: item.id`). Our wire tool calls are all agent-sourced — there is no orchestrator
    /// payload on the wire — so `agentMessage` itself is the source signal. Every other
    /// event (and a missing `agentMessage`) leaves the tool call untouched.
    static func presentedItem(_ item: TimelineItem) -> TimelineItem {
        guard case .toolCall(let call) = item, let message = call.agentMessage, message.event == .message else {
            return item
        }
        return .userMessage(TimelineItem.UserMessage(text: message.text, sender: message.sender))
    }

    private static func mergeIntervals(_ intervals: [(Int, Int)]) -> [(Int, Int)] {
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var merged: [(Int, Int)] = []
        for interval in sorted {
            if let last = merged.last, last.1 >= interval.0 {
                merged[merged.count - 1].1 = max(last.1, interval.1)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private static func overlapsAny(_ start: Int, _ end: Int, intervals: [(Int, Int)]) -> Bool {
        var low = 0
        var high = intervals.count - 1
        var candidate = -1
        while low <= high {
            let mid = (low + high) / 2
            if intervals[mid].0 <= end {
                candidate = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard candidate >= 0 else { return false }
        return intervals[candidate].1 >= start
    }

    /// Cursor for `FetchAgentTimelineRequest(direction: .after)` after a gap.
    public var endCursor: TimelineCursor? {
        guard let epoch, let last = rows.last(where: { !$0.isPending }) else { return nil }
        return TimelineCursor(epoch: epoch, seq: last.seqEnd)
    }

    /// Cursor for `FetchAgentTimelineRequest(direction: .before)` to load older history.
    public var startCursor: TimelineCursor? {
        guard let epoch, let first = rows.first(where: { !$0.isPending }) else { return nil }
        return TimelineCursor(epoch: epoch, seq: first.seqStart)
    }
}
