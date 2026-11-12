import Foundation
import PaseoProtocol

/// One exchange: what you asked, the work the agent did, and what it said.
/// This is the unit the chat renders; see ARCHITECTURE.md "The turn".
public struct Turn: Sendable, Equatable, Identifiable {
    /// View identity: the id of the turn's first row. Stable while the turn streams and when a
    /// pending user message is confirmed (rows keep their ids; see `TimelineRow.id`).
    public var id: String
    /// The daemon's turn id. Nil for a turn that is only a pending message so far, or for rows
    /// the daemon sent without one.
    public var turnId: String?
    /// The row whose item is `.userMessage`, if the turn starts with one. Not repeated in `segments`.
    public var userMessage: TimelineRow?
    /// Everything after the user message, in order.
    public var segments: [Segment]
    public var phase: Phase
    /// Timestamp of the turn's first row.
    public var startedAt: Date?
    /// Timestamp of the turn's last row. Nil while running.
    public var endedAt: Date?
    /// The turn's file changes (G6 C11), or nil when it changed nothing. Computed
    /// with the turn, so the incremental tail rebuild recomputes only rebuilt turns.
    public var changeSummary: TurnChangeSummary? = nil
    /// The turn's todo/plan state (Phase C §9.2), or nil when the turn has neither.
    /// An O(rows) scan with no parsing, so it runs on every rebuild — including the
    /// running tail — and the card updates live.
    public var todoState: TurnTodoState? = nil

    public enum Phase: Sendable, Equatable {
        case running
        case completed
        /// The turn contains an `.error` item; carries its message.
        case failed(String)
    }

    public enum Segment: Sendable, Equatable, Identifiable {
        /// A run of consecutive reasoning and tool-call rows: the collapsible
        /// "2 thoughts, 1 tool call" group.
        case work(WorkGroup)
        /// An assistant message.
        case prose(TimelineRow)
        case todo(TimelineRow)
        /// Error, notification, compaction, plugin or unknown items.
        case notice(TimelineRow)

        public var id: String {
            switch self {
            case .work(let group): "work:\(group.rows.first?.id ?? "")"
            case .prose(let row), .todo(let row), .notice(let row): row.id
            }
        }
    }

    public struct WorkGroup: Sendable, Equatable {
        /// Only `.reasoning` and `.toolCall` rows.
        public var rows: [TimelineRow]
        public var thoughtCount: Int { rows.count { if case .reasoning = $0.item { true } else { false } } }
        public var toolCallCount: Int { rows.count { if case .toolCall = $0.item { true } else { false } } }
        /// True while any tool call in the group is still running.
        public var isActive: Bool {
            rows.contains { if case .toolCall(let call) = $0.item { !call.status.isTerminal } else { false } }
        }
    }

    /// Wall-clock length of the turn, for "Completed in 4s". Nil while running.
    public var duration: TimeInterval? {
        guard let startedAt, let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}

/// Groups timeline rows into turns. Pure and cheap enough to run on every change.
///
/// IMPLEMENTATION TICKET: docs/tickets/T3-turn-builder.md
public enum TurnBuilder {
    /// - Parameter activeTurnId: the agent's `activeTurn?.turnId`. That turn is `.running`.
    public static func turns(from rows: [TimelineRow], activeTurnId: String?) -> [Turn] {
        var turns: [Turn] = []
        var draft: TurnDraft?

        func closeDraft() {
            guard var current = draft else { return }
            current.flushWork()
            turns.append(current.finish(activeTurnId: activeTurnId))
            draft = nil
        }

        for row in rows {
            // Grouping key: the daemon's turn id; rows without one join the current turn.
            // A user message without one (just sent, not confirmed) always starts a new turn.
            let startsPendingTurn = row.turnId == nil && { if case .userMessage = row.item { true } else { false } }()
            let key: String
            if let turnId = row.turnId {
                key = turnId
            } else if let current = draft, !startsPendingTurn {
                key = current.key
            } else {
                key = "untracked:\(row.id)"
            }

            if draft == nil || draft?.key != key {
                closeDraft()
                draft = TurnDraft(key: key, turnId: row.turnId, id: row.id)
            }
            draft?.add(row)
        }
        closeDraft()
        return turns
    }
}

/// Accumulates one turn while rows are walked in order.
private struct TurnDraft {
    /// Grouping key while walking rows.
    var key: String
    var turnId: String?
    /// The first row's id.
    var id: String

    init(key: String, turnId: String?, id: String) {
        self.key = key
        self.turnId = turnId
        self.id = id
    }

    private var rows: [TimelineRow] = []
    private var userMessage: TimelineRow?
    private var segments: [Turn.Segment] = []
    private var workRows: [TimelineRow] = []

    mutating func add(_ row: TimelineRow) {
        let isFirst = rows.isEmpty
        rows.append(row)

        if isFirst, case .userMessage = row.item {
            userMessage = row
            return
        }

        switch row.item {
        case .reasoning, .toolCall:
            workRows.append(row)
        case .assistantMessage:
            flushWork()
            segments.append(.prose(row))
        case .todo:
            flushWork()
            segments.append(.todo(row))
        default:
            flushWork()
            segments.append(.notice(row))
        }
    }

    mutating func flushWork() {
        guard !workRows.isEmpty else { return }
        segments.append(.work(Turn.WorkGroup(rows: workRows)))
        workRows = []
    }

    func finish(activeTurnId: String?) -> Turn {
        let isRunning = turnId != nil && turnId == activeTurnId
        let startedAt = rows.first.flatMap { PaseoDate.parse($0.timestamp) }
        let endedAt = isRunning ? nil : rows.last.flatMap { PaseoDate.parse($0.timestamp) }

        let phase: Turn.Phase
        if isRunning {
            phase = .running
        } else if let errorMessage = rows.lazy.compactMap({ row -> String? in
            if case .error(let message) = row.item { return message }
            return nil
        }).first {
            phase = .failed(errorMessage)
        } else {
            phase = .completed
        }

        var finished = Turn(id: id, turnId: turnId, userMessage: userMessage, segments: segments, phase: phase, startedAt: startedAt, endedAt: endedAt)
        // The card only shows at turn end: a running tail is rebuilt on every stream
        // event, so parsing its diffs here would cost O(diff size) per token on main.
        finished.changeSummary = isRunning ? nil : TurnChangeSummary.summarize(turn: finished)
        finished.todoState = TurnTodoState.reduce(turn: finished)
        return finished
    }
}

/// Daemon timestamps are ISO-8601 with fractional seconds (`2026-11-08T20:56:19.869Z`).
public enum PaseoDate {
    public static func parse(_ string: String) -> Date? {
        if let date = try? Date(string, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(string, strategy: .iso8601)
    }
}
