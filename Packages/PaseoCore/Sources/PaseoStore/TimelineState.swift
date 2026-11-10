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
    /// The newest non-pending user message's `seqStart`. Maintained incrementally so
    /// `ConversationStore` can read it in O(1) instead of scanning every row on every
    /// streamed token. Pending sends are excluded: they are not in the daemon's index yet.
    internal private(set) var latestPromptSeq: Int?

    // MARK: Digest (R3): O(1) reads maintained alongside `rows`
    //
    // Every property below is exactly what a full scan of `rows` would give (see `rebuildDigest`).
    // The live paths update them incrementally; only page merges and pending-message removal pay
    // for a full recompute.

    /// One failed tool call, in row order. `seq` is that row's `seqEnd`.
    public struct FailedToolCall: Sendable, Equatable {
        public var callId: String
        public var seq: Int

        public init(callId: String, seq: Int) {
            self.callId = callId
            self.seq = seq
        }
    }

    /// The kind of the newest row, for the mascot's activity signal.
    public enum RowKind: Sendable, Equatable {
        case reasoning, toolCall, other
    }

    /// Rows with a `.toolCall` that failed with something other than an AbortError, in row order.
    public private(set) var failedToolCalls: [FailedToolCall] = []
    /// Rows whose tool call is `.running` with a `.subAgent` detail.
    public private(set) var runningSubAgentCount = 0
    /// `status` of the last `.compaction` row.
    public private(set) var lastCompactionStatus: String?
    /// Kind of `rows.last`.
    public private(set) var latestRowKind: RowKind?
    /// `id` of `rows.last`.
    public private(set) var latestRowId: String?

    /// `seqEnd` -> index of the first row with that `seqEnd`. Rows are the source of truth;
    /// this only saves the scan. A pending send can briefly share a `seqEnd` with a live row.
    private var rowIndexBySeqEnd: [Int: Int] = [:]
    /// Row index of each entry in `failedToolCalls`, parallel to it, so an entry can be inserted in
    /// row order without a scan of `rows`.
    private var failedToolRowIndexes: [Int] = []
    /// `seqEnd`s currently shared by more than one row. Only these need a repair scan when the
    /// first occurrence moves; a plain row index is O(1) to keep.
    private var duplicatedSeqEnds: Set<Int> = []
    private var lastCompactionRowIndex: Int?

    public init() {
        epoch = nil
        rows = []
        nextSeq = nil
        hasOlder = false
        latestPromptSeq = nil
        rebuildDigest()
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
        let signpost = PaseoSignpost.log.beginInterval("timeline page")
        defer { PaseoSignpost.log.endInterval("timeline page", signpost) }
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

        // A page can rewrite or drop rows anywhere, so the newest prompt is recomputed from
        // the merged rows. This is not the per-token path.
        latestPromptSeq = Self.newestPromptSeq(in: rows)
        // A page can rewrite or drop rows anywhere: recompute the digest from scratch.
        rebuildDigest()
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
        // Live merges only append or update in place, so the newest prompt can only move
        // when the last non-pending row became a user message.
        refreshLatestPromptSeq()
        return .applied
    }

    /// Shows a just-sent message immediately. Replaced when the daemon echoes a user_message
    /// with the same `clientMessageId`.
    public mutating func addPendingUserMessage(text: String, clientMessageId: String, timestamp: String) {
        let seq = nextSeq ?? 0
        let item = TimelineItem.userMessage(TimelineItem.UserMessage(text: text, clientMessageId: clientMessageId))
        rows.append(TimelineRow(id: "local:\(clientMessageId)", turnId: nil, item: item, timestamp: timestamp, seqStart: seq, seqEnd: seq, isPending: true))
        digestDidInsertRow(at: rows.count - 1)
    }

    /// Drops an optimistic user message that the daemon never accepted. A confirmed message is
    /// kept: only rows still marked pending are removed.
    public mutating func removePendingUserMessage(clientMessageId: String) {
        rows.removeAll { $0.isPending && $0.id == "local:\(clientMessageId)" }
        // Removal can drop a row anywhere in the index map: recompute it.
        rebuildDigest()
    }

    private mutating func merge(item: TimelineItem, turnId: String?, seq: Int, timestamp: String) {
        switch item {
        case .reasoning:
            if appendText(seq: seq, turnId: turnId, text: reasoningText(item), isReasoning: true) { return }
        case .assistantMessage:
            if appendText(seq: seq, turnId: turnId, text: assistantText(item), isReasoning: false) { return }
        case .toolCall(let call):
            if let index = rows.firstIndex(where: { $0.id == "tool:\(call.callId)" }) {
                let oldItem = rows[index].item
                let oldSeqEnd = rows[index].seqEnd
                rows[index].item = Self.presentedItem(item)
                rows[index].seqEnd = seq
                digestDidChangeRow(at: index, from: oldItem, oldSeqEnd: oldSeqEnd)
                return
            }
        case .userMessage(let message):
            if let clientMessageId = message.clientMessageId,
               let index = rows.firstIndex(where: { $0.isPending && $0.id == "local:\(clientMessageId)" }) {
                let oldItem = rows[index].item
                let oldSeqEnd = rows[index].seqEnd
                rows[index].item = item
                rows[index].isPending = false
                rows[index].seqStart = seq
                rows[index].seqEnd = seq
                rows[index].turnId = turnId
                rows[index].timestamp = timestamp
                digestDidChangeRow(at: index, from: oldItem, oldSeqEnd: oldSeqEnd)
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
        let oldItem = rows[index].item
        let oldSeqEnd = rows[index].seqEnd
        switch (isReasoning, oldItem) {
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
        digestDidChangeRow(at: index, from: oldItem, oldSeqEnd: oldSeqEnd)
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
        let index: Int
        if let lastNonPending = rows.lastIndex(where: { !$0.isPending }) {
            index = lastNonPending + 1
        } else {
            index = 0
        }
        rows.insert(row, at: index)
        digestDidInsertRow(at: index)
    }

    // MARK: Digest maintenance

    /// Brings every digest property back to its full-scan value. O(rows); only page merges and the
    /// removal of a pending message call it.
    private mutating func rebuildDigest() {
        failedToolCalls = []
        failedToolRowIndexes = []
        runningSubAgentCount = 0
        lastCompactionStatus = nil
        lastCompactionRowIndex = nil
        rowIndexBySeqEnd = [:]
        duplicatedSeqEnds = []
        for (index, row) in rows.enumerated() {
            if let entry = Self.failedCall(of: row) {
                failedToolCalls.append(entry)
                failedToolRowIndexes.append(index)
            }
            if Self.isRunningSubAgent(row.item) { runningSubAgentCount += 1 }
            if case .compaction(let status, _, _) = row.item {
                lastCompactionStatus = status
                lastCompactionRowIndex = index
            }
            if rowIndexBySeqEnd[row.seqEnd] == nil {
                rowIndexBySeqEnd[row.seqEnd] = index
            } else {
                duplicatedSeqEnds.insert(row.seqEnd)
            }
        }
        refreshLatestRow()
    }

    /// A row was inserted at `index`. The live paths only insert after the last non-pending row, so
    /// the rows that move are pending ones (none, or one in practice).
    private mutating func digestDidInsertRow(at index: Int) {
        guard index >= 0, index < rows.count else { return }
        if index + 1 < rows.count {
            // Backwards, so a `seqEnd` shared by several moved rows only shifts the one that owned
            // the map (the first occurrence); a forward walk would shift it once per duplicate.
            for moved in stride(from: rows.count - 1, through: index + 1, by: -1) {
                let seqEnd = rows[moved].seqEnd
                if rowIndexBySeqEnd[seqEnd] == moved - 1 {
                    rowIndexBySeqEnd[seqEnd] = moved
                }
            }
        }
        let row = rows[index]
        insertSeqIndex(seqEnd: row.seqEnd, index: index)
        if let entry = Self.failedCall(of: row) {
            insertFailedEntry(entry, rowIndex: index)
        }
        if Self.isRunningSubAgent(row.item) { runningSubAgentCount += 1 }
        if case .compaction(let status, _, _) = row.item, index >= (lastCompactionRowIndex ?? -1) {
            lastCompactionStatus = status
            lastCompactionRowIndex = index
        }
        refreshLatestRow()
    }

    /// The item or `seqEnd` of the row at `index` changed in place.
    private mutating func digestDidChangeRow(
        at index: Int, from oldItem: TimelineItem, oldSeqEnd: Int
    ) {
        guard index >= 0, index < rows.count else { return }
        let row = rows[index]
        if let callId = Self.toolCallId(of: oldItem) { removeFailedEntry(callId: callId) }
        if let entry = Self.failedCall(of: row) { insertFailedEntry(entry, rowIndex: index) }
        if Self.isRunningSubAgent(oldItem) { runningSubAgentCount -= 1 }
        if Self.isRunningSubAgent(row.item) { runningSubAgentCount += 1 }
        // A compaction keeps its type when it changes in place, so only its status can move. A
        // later compaction row keeps winning.
        if case .compaction(let status, _, _) = row.item, index >= (lastCompactionRowIndex ?? -1) {
            lastCompactionStatus = status
            lastCompactionRowIndex = index
        }
        if oldSeqEnd != row.seqEnd {
            removeSeqIndex(seqEnd: oldSeqEnd, owner: index)
            insertSeqIndex(seqEnd: row.seqEnd, index: index)
        }
        refreshLatestRow()
    }

    private mutating func refreshLatestRow() {
        latestRowId = rows.last?.id
        latestRowKind = rows.last.map { Self.rowKind(of: $0.item) }
    }

    /// First row wins: the map holds the smallest index for a `seqEnd`.
    private mutating func insertSeqIndex(seqEnd: Int, index: Int) {
        guard let existing = rowIndexBySeqEnd[seqEnd] else {
            rowIndexBySeqEnd[seqEnd] = index
            return
        }
        duplicatedSeqEnds.insert(seqEnd)
        if existing > index { rowIndexBySeqEnd[seqEnd] = index }
    }

    private mutating func removeSeqIndex(seqEnd: Int, owner: Int) {
        guard rowIndexBySeqEnd[seqEnd] == owner else { return }
        rowIndexBySeqEnd[seqEnd] = nil
        // Only a shared `seqEnd` can have another owner; a plain one is done in O(1).
        guard duplicatedSeqEnds.contains(seqEnd), owner + 1 < rows.count else { return }
        if let next = rows[(owner + 1)...].firstIndex(where: { $0.seqEnd == seqEnd }) {
            rowIndexBySeqEnd[seqEnd] = next
        }
    }

    /// Inserts in row order, so the result matches a scan of `rows`.
    private mutating func insertFailedEntry(_ entry: FailedToolCall, rowIndex: Int) {
        let position =
            failedToolRowIndexes.firstIndex(where: { $0 > rowIndex }) ?? failedToolRowIndexes.count
        failedToolCalls.insert(entry, at: position)
        failedToolRowIndexes.insert(rowIndex, at: position)
    }

    private mutating func removeFailedEntry(callId: String) {
        guard let position = failedToolCalls.firstIndex(where: { $0.callId == callId }) else { return }
        failedToolCalls.remove(at: position)
        failedToolRowIndexes.remove(at: position)
    }

    private static func failedCall(of row: TimelineRow) -> FailedToolCall? {
        guard case .toolCall(let call) = row.item, MascotToolError.isFailure(call) else { return nil }
        return FailedToolCall(callId: call.callId, seq: row.seqEnd)
    }

    private static func toolCallId(of item: TimelineItem) -> String? {
        guard case .toolCall(let call) = item else { return nil }
        return call.callId
    }

    private static func isRunningSubAgent(_ item: TimelineItem) -> Bool {
        guard case .toolCall(let call) = item, call.status == .running, case .subAgent = call.detail
        else { return false }
        return true
    }

    private static func rowKind(of item: TimelineItem) -> RowKind {
        switch item {
        case .reasoning: return .reasoning
        case .toolCall: return .toolCall
        default: return .other
        }
    }

    /// Recomputes the newest prompt from the end. Used after a page merge, which can drop or
    /// rewrite rows anywhere.
    private static func newestPromptSeq(in rows: [TimelineRow]) -> Int? {
        rows.last { row in
            guard !row.isPending else { return false }
            if case .userMessage = row.item { return true }
            return false
        }?.seqStart
    }

    /// Updates the cached newest prompt when the last non-pending row is a user message.
    /// Live merges never remove rows, so an unchanged last row means the prompt is unchanged.
    private mutating func refreshLatestPromptSeq() {
        if let last = rows.last(where: { !$0.isPending }), case .userMessage = last.item {
            latestPromptSeq = last.seqStart
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

    /// The index of the first row whose `seqEnd` is `seq`, or nil. O(1): the map is maintained
    /// alongside `rows`, so the transcript does not scan per visible turn.
    public func rowIndex(forSeqEnd seq: Int) -> Int? {
        rowIndexBySeqEnd[seq]
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
