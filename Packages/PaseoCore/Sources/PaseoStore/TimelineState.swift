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
        fatalError("T2: not implemented")
    }

    /// Applies one live event. See T2 for the merge rules.
    public mutating func applyStream(_ payload: AgentStreamPayload) -> StreamResult {
        fatalError("T2: not implemented")
    }

    /// Shows a just-sent message immediately. Replaced when the daemon echoes a user_message
    /// with the same `clientMessageId`.
    public mutating func addPendingUserMessage(text: String, clientMessageId: String, timestamp: String) {
        fatalError("T2: not implemented")
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
