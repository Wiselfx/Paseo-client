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

    internal init() {}

    /// Returns exactly `TurnBuilder.turns(from: newRows, activeTurnId: activeTurnId)`.
    internal func turns(from newRows: [TimelineRow], activeTurnId: String?) -> [Turn] {
        let previousActiveTurnId = self.activeTurnId
        let activeChanged = activeTurnId != previousActiveTurnId
        let firstChange = Self.firstChangedRow(rows, newRows)

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

        var rebuiltTurns = Array(turns[0..<reusedCount])
        var rebuiltRanges = Array(ranges[0..<reusedCount])
        let rebuilt = TurnBuilder.turns(
            from: Array(newRows[rebuildStart...]), activeTurnId: activeTurnId)
        var offset = rebuildStart
        for turn in rebuilt {
            let count = Self.rowCount(of: turn)
            rebuiltTurns.append(turn)
            rebuiltRanges.append(offset..<(offset + count))
            offset += count
        }

        rows = newRows
        turns = rebuiltTurns
        ranges = rebuiltRanges
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
    /// the other. The rows are wide structs, so compare their storage bytes and only fall back to
    /// `==` when a byte difference is not a value difference (struct padding is not part of the
    /// value and two copies of equal rows can differ there). `memcmp` stops at the first change.
    private static func firstChangedRow(_ oldRows: [TimelineRow], _ newRows: [TimelineRow]) -> Int {
        let shared = min(oldRows.count, newRows.count)
        guard shared > 0 else { return 0 }
        let stride = MemoryLayout<TimelineRow>.stride
        let size = MemoryLayout<TimelineRow>.size
        var first = shared
        oldRows.withUnsafeBytes { oldBytes in
            newRows.withUnsafeBytes { newBytes in
                guard let oldBase = oldBytes.baseAddress, let newBase = newBytes.baseAddress else {
                    return
                }
                for index in 0..<shared {
                    if memcmp(oldBase + index * stride, newBase + index * stride, size) != 0 {
                        first = index
                        return
                    }
                }
            }
        }
        var index = first
        while index < shared && oldRows[index] == newRows[index] { index += 1 }
        return index
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
