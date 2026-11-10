import Foundation
import PaseoProtocol

/// Incremental counterpart to `TurnBuilder`.
///
/// `TurnBuilder.turns(from:activeTurnId:)` walks every row on every call, so a long chat pays
/// O(rows) turn construction per streamed token even though only the newest turn changed. This
/// type keeps the turns it last built and the row range each came from, so an update rebuilds only
/// the turns from the one containing the change onward and reuses the rest. The result is always
/// exactly `TurnBuilder.turns(from:activeTurnId:)` for the same input.
///
/// How it stays exact:
/// - Rows are grouped into contiguous runs, so the turns before the first changed row cannot move:
///   their key sequence is produced by rows that are unchanged. Turns that end at or before the
///   first changed row are therefore reused as-is, and a turn that starts there still starts there.
/// - `TurnBuilder` is then run over the remaining rows only. Its grouping is local (a row's key is
///   its own `turnId`, the id of a pending user message, or the draft's current key), so starting
///   the walk at a real boundary yields the same turns a full walk would from there.
/// - If the change is exactly at a turn boundary the previous turn may absorb the new row, so the
///   rebuild starts one turn earlier. A change at row 0 (prepended page, replaced timeline) is a
///   full rebuild, which is rare.
/// - `activeTurnId` only feeds `phase`/`endedAt`, and only for turns whose `turnId` is the old or
///   the new active id. Those turns are the only ones refreshed; no row walk is needed.
internal final class IncrementalTurnBuilder {
    /// The rows `turns` were built from.
    private var rows: [TimelineRow] = []
    /// Turns, in order.
    private var turns: [Turn] = []
    /// The half-open row range each turn was built from: ascending, contiguous, covering `rows`.
    private var ranges: [Range<Int>] = []
    private var activeTurnId: String?

    /// How many turns the last `turns(from:activeTurnId:)` call constructed. Zero when nothing had
    /// to be built. Reuse probe for `IncrementalTurnBuilderTests`.
    internal private(set) var turnsBuiltLastUpdate = 0
    /// How many row comparisons the last `turns(from:activeTurnId:)` call performed. The
    /// streaming fast path must keep this near the changed run, not the transcript length.
    internal private(set) var rowsComparedLastUpdate = 0

    internal init() {}

    /// Returns exactly `TurnBuilder.turns(from: newRows, activeTurnId: activeTurnId)`.
    internal func turns(from newRows: [TimelineRow], activeTurnId: String?) -> [Turn] {
        let previousActiveTurnId = self.activeTurnId
        let activeChanged = activeTurnId != previousActiveTurnId
        let firstChange = firstChangedRow(rows, newRows)

        // Same rows: only the active turn's phase/endedAt can differ.
        if firstChange == rows.count && firstChange == newRows.count {
            self.activeTurnId = activeTurnId
            turnsBuiltLastUpdate = activeChanged
                ? refreshActiveTurns(
                    in: turns.indices, previous: previousActiveTurnId, activeTurnId: activeTurnId)
                : 0
            return turns
        }

        let rebuildStart = rebuildStart(forFirstChange: firstChange)
        let reusedCount = reusedTurnCount(endingAtOrBefore: rebuildStart)

        // Drop the stale tail in place instead of copying the reused prefix: a streamed
        // token would otherwise allocate a fresh turns array per update. The reused turns
        // keep their identity, so SwiftUI still sees unchanged values above the tail.
        if turns.count > reusedCount {
            turns.removeLast(turns.count - reusedCount)
            ranges.removeLast(ranges.count - reusedCount)
        }
        let rebuilt = TurnBuilder.turns(
            from: Array(newRows[rebuildStart...]), activeTurnId: activeTurnId)
        var offset = rebuildStart
        for turn in rebuilt {
            let count = Self.rowCount(of: turn)
            turns.append(turn)
            ranges.append(offset..<(offset + count))
            offset += count
        }

        rows = newRows
        self.activeTurnId = activeTurnId

        var built = rebuilt.count
        if activeChanged {
            // The rebuilt tail was walked with the new active id already; only reused turns need it.
            built += refreshActiveTurns(
                in: 0..<reusedCount, previous: previousActiveTurnId, activeTurnId: activeTurnId)
        }
        turnsBuiltLastUpdate = built
        return turns
    }

    // MARK: - Where to rebuild from

    /// The first row index where the two row arrays differ, or `min(count)` when one is a prefix of
    /// the other.
    ///
    /// The streaming fast path compares the newest rows first using a cheap row version
    /// (`id`, `turnId`, seq range, pending flag and item kind). A live merge changes a
    /// contiguous run at the tail, so walking backwards over differing versions finds the
    /// first change in O(changed rows). The one row where the run stops is compared in full,
    /// so a page that rewrites a row's content without moving its seq is still found. Only
    /// when the newest row is unchanged — a middle edit, a prepended page, a removal — does
    /// it fall back to a full forward `==` walk, which is not the per-token path.
    private func firstChangedRow(_ oldRows: [TimelineRow], _ newRows: [TimelineRow]) -> Int {
        let shared = min(oldRows.count, newRows.count)
        guard shared > 0 else {
            rowsComparedLastUpdate = 0
            return 0
        }

        // Fast path: the newest shared row changed. Walk backwards over the changed run.
        rowsComparedLastUpdate = 1
        if Self.version(of: oldRows[shared - 1]) != Self.version(of: newRows[shared - 1]) {
            var index = shared - 1
            while index > 0 {
                rowsComparedLastUpdate += 1
                if Self.version(of: oldRows[index - 1]) != Self.version(of: newRows[index - 1]) {
                    index -= 1
                } else if oldRows[index - 1] == newRows[index - 1] {
                    return index
                } else {
                    // Same metadata, different content: a page rewrote a row in place without
                    // moving its seq (a tool call whose detail filled in, for example).
                    index -= 1
                }
            }
            return 0
        }

        // A pure append leaves every existing row at its index. Detect it by the last
        // existing row so appending a row does not scan the transcript either. Full equality
        // (not just the version) so a page that rewrites the last row's content while adding
        // rows after it is not mistaken for an append.
        if newRows.count > oldRows.count {
            rowsComparedLastUpdate += 1
            if newRows[oldRows.count - 1] == oldRows[oldRows.count - 1] {
                return oldRows.count
            }
        }

        // The newest row is unchanged and this is not a pure append: a middle edit, a
        // prepended page, or a removal. Walk forward with full equality.
        var index = 0
        while index < shared {
            rowsComparedLastUpdate += 1
            if oldRows[index] == newRows[index] {
                index += 1
            } else {
                break
            }
        }
        return index
    }

    /// A cheap per-row version: identity plus the fields a merge can move without changing the
    /// row's id. Comparing two is O(1) (ids are short), so the streaming fast path does not
    /// walk the transcript. Item content with identical metadata is caught by the full-equality
    /// check where the changed run stops.
    private struct RowVersion: Equatable {
        let id: String
        let turnId: String?
        let seqStart: Int
        let seqEnd: Int
        let isPending: Bool
        let itemKind: ItemKind
    }

    private enum ItemKind: Equatable {
        case userMessage, assistantMessage, reasoning, toolCall, todo, error, notification, compaction, unknown
    }

    private static func version(of row: TimelineRow) -> RowVersion {
        RowVersion(
            id: row.id, turnId: row.turnId, seqStart: row.seqStart, seqEnd: row.seqEnd,
            isPending: row.isPending, itemKind: itemKind(of: row.item))
    }

    private static func itemKind(of item: TimelineItem) -> ItemKind {
        switch item {
        case .userMessage: return .userMessage
        case .assistantMessage: return .assistantMessage
        case .reasoning: return .reasoning
        case .toolCall: return .toolCall
        case .todo: return .todo
        case .error: return .error
        case .notification: return .notification
        case .compaction: return .compaction
        case .unknown: return .unknown
        }
    }

    /// The row the rebuild starts at: the start of the turn that contains the first changed row, one
    /// turn earlier if the change is exactly a turn boundary (the previous turn may absorb it), or
    /// the start of the last turn for a pure append (it may grow or be followed by a new turn).
    private func rebuildStart(forFirstChange firstChange: Int) -> Int {
        guard !turns.isEmpty else { return 0 }
        guard firstChange < rows.count else {
            return ranges[ranges.count - 1].lowerBound
        }
        let index = turnIndex(containing: firstChange)
        if ranges[index].lowerBound == firstChange && index > 0 {
            return ranges[index - 1].lowerBound
        }
        return ranges[index].lowerBound
    }

    /// The turn that owns `rowIndex`. `ranges` is ascending and contiguous.
    private func turnIndex(containing rowIndex: Int) -> Int {
        var low = 0
        var high = ranges.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if ranges[mid].lowerBound <= rowIndex { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// How many leading turns end at or before `rowIndex`.
    private func reusedTurnCount(endingAtOrBefore rowIndex: Int) -> Int {
        var low = 0
        var high = ranges.count
        while low < high {
            let mid = (low + high) / 2
            if ranges[mid].upperBound <= rowIndex { low = mid + 1 } else { high = mid }
        }
        return low
    }

    // MARK: - Active turn

    /// Rebuilds the turns whose `phase`/`endedAt` read the active turn id: the old active turn and
    /// the new one. Nothing else in a `Turn` depends on `activeTurnId`.
    /// - Returns: how many turns were rebuilt.
    @discardableResult
    private func refreshActiveTurns(
        in indices: Range<Int>, previous: String?, activeTurnId: String?
    ) -> Int {
        var built = 0
        for index in indices {
            guard let turnId = turns[index].turnId,
                turnId == activeTurnId || turnId == previous
            else { continue }
            let refreshed = TurnBuilder.turns(
                from: Array(rows[ranges[index]]), activeTurnId: activeTurnId)
            guard let turn = refreshed.first else { continue }
            turns[index] = turn
            built += 1
        }
        return built
    }

    // MARK: - Row bookkeeping

    /// How many rows a turn owns. `Turn` does not store the count, but every row a turn was built
    /// from is represented exactly once in its `userMessage` and `segments`.
    private static func rowCount(of turn: Turn) -> Int {
        var count = turn.userMessage == nil ? 0 : 1
        for segment in turn.segments {
            switch segment {
            case .work(let group): count += group.rows.count
            case .prose, .todo, .notice: count += 1
            }
        }
        return count
    }
}
