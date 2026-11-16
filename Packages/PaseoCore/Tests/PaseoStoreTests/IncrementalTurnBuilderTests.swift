import Foundation
import Testing
import PaseoProtocol
@testable import PaseoProtocol
@testable import PaseoStore

/// P4: `IncrementalTurnBuilder` must always equal `TurnBuilder`, and must not rebuild turns that
/// cannot have changed.
@Suite struct IncrementalTurnBuilderTests {
    // MARK: - Deterministic RNG

    /// SplitMix64: small, seeded, no dependencies.
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

    // MARK: - Row factory

    /// Builds plausible rows: unique seq ranges, stable ids, turn ids repeated within a turn and
    /// occasionally missing so the "rows without a turn id join the current turn" rule is hit.
    private struct Factory {
        var rng: SplitMix64
        var seq = 0
        var turnCounter = 0
        var callCounter = 0
        var clientCounter = 0
        var seconds = 0
        var turnRowCount = 1..<7

        mutating func timestamp() -> String {
            seconds += 1
            return String(format: "2026-11-08T21:%02d:%02d.000Z", (seconds / 60) % 60, seconds % 60)
        }

        mutating func makeRow(
            id: String, turnId: String?, item: TimelineItem, pending: Bool = false
        ) -> TimelineRow {
            seq += 1
            return TimelineRow(
                id: id, turnId: turnId, item: item, timestamp: timestamp(),
                seqStart: seq, seqEnd: seq, isPending: pending)
        }

        mutating func makeItem(status: ToolCall.Status = .running) -> TimelineItem {
            switch rng.int(in: 0..<8) {
            case 0: return .userMessage(.init(text: "u\(rng.int(in: 0..<100))"))
            case 1: return .assistantMessage(.init(text: "a\(rng.int(in: 0..<100))"))
            case 2: return .reasoning(.init(text: "r\(rng.int(in: 0..<100))"))
            case 3:
                callCounter += 1
                return .toolCall(ToolCall(
                    callId: "call\(callCounter)", name: "Bash", status: status,
                    detail: .shell(command: "ls", cwd: nil, output: nil, exitCode: nil)))
            case 4: return .todo(TimelineItem.TodoList(items: []))
            case 5: return .error(message: "e\(rng.int(in: 0..<100))")
            case 6: return .notification(level: "info", message: "n\(rng.int(in: 0..<100))")
            default: return .compaction(status: "compacted")
            }
        }

        /// One turn: an optional user message (sometimes still pending), then a run of items.
        mutating func makeTurn() -> [TimelineRow] {
            var rows: [TimelineRow] = []
            let turnId: String? = rng.bool() ? "t\(turnCounter)" : nil
            turnCounter += 1
            if rng.int(in: 0..<3) != 0 {
                let pending = rng.int(in: 0..<5) == 0
                let clientId = "c\(clientCounter)"
                if pending { clientCounter += 1 }
                let id = pending ? "local:\(clientId)" : "seq:\(seq + 1)"
                rows.append(makeRow(
                    id: id, turnId: pending ? nil : turnId,
                    item: .userMessage(.init(
                        text: "hello \(turnCounter)", clientMessageId: pending ? clientId : nil)),
                    pending: pending))
            }
            for _ in 0..<rng.int(in: turnRowCount) {
                let item = makeItem()
                let id = if case .toolCall = item { "tool:call\(callCounter)" } else { "seq:\(seq + 1)" }
                rows.append(makeRow(id: id, turnId: turnId, item: item))
            }
            return rows
        }

        mutating func makeTranscript(turns: Int) -> [TimelineRow] {
            var rows: [TimelineRow] = []
            for _ in 0..<turns { rows.append(contentsOf: makeTurn()) }
            return rows
        }

        /// Streams one token onto the tail: usually appends text to the last row, sometimes starts a
        /// new row. Deterministic, so the full and incremental timings see the same updates.
        mutating func appendTailToken(to rows: inout [TimelineRow], index: Int) {
            guard let last = rows.lastIndex(where: { !$0.isPending }) else { return }
            if index % 3 == 2 {
                appendTailRow(to: &rows, after: last)
                return
            }
            switch rows[last].item {
            case .reasoning(var reasoning):
                reasoning.text += "x"
                rows[last].item = .reasoning(reasoning)
            case .assistantMessage(var message):
                message.text += "x"
                rows[last].item = .assistantMessage(message)
            default:
                appendTailRow(to: &rows, after: last)
            }
        }

        private mutating func appendTailRow(to rows: inout [TimelineRow], after index: Int) {
            let seq = rows[index].seqEnd + 1
            rows.append(TimelineRow(
                id: "seq:\(seq)", turnId: rows[index].turnId,
                item: .reasoning(.init(text: "tail")),
                timestamp: "2026-11-08T21:59:59.000Z", seqStart: seq, seqEnd: seq))
        }
    }

    // MARK: - Editable world

    /// A transcript plus the edit scripts the ticket lists. Every edit goes through this type so
    /// the property test and the targeted test drive the same code.
    private struct World {
        var factory: Factory
        var rows: [TimelineRow] = []
        var activeTurnId: String?

        init(seed: UInt64) { factory = Factory(rng: SplitMix64(seed: seed)) }

        mutating func appendTurn() { rows.append(contentsOf: factory.makeTurn()) }

        mutating func appendToLastTurn() {
            guard let last = rows.last else { return }
            let turnId = last.turnId
            let item = factory.makeItem()
            let id = if case .toolCall = item { "tool:call\(factory.callCounter)" } else { "seq:\(factory.seq + 1)" }
            rows.append(factory.makeRow(id: id, turnId: turnId, item: item))
        }

        mutating func updateLastText() {
            guard let index = rows.lastIndex(where: { !$0.isPending }) else { return }
            switch rows[index].item {
            case .reasoning(var reasoning):
                reasoning.text += "x"
                rows[index].item = .reasoning(reasoning)
            case .assistantMessage(var message):
                message.text += "x"
                rows[index].item = .assistantMessage(message)
            default: break
            }
        }

        /// Flips a tool call's status near the end of the transcript; lands on the tail turn most of
        /// the time and a few turns back otherwise.
        mutating func updateToolStatus() {
            let lower = max(0, rows.count - 30)
            let isToolCall: (TimelineRow) -> Bool = { if case .toolCall = $0.item { true } else { false } }
            guard let index = rows[lower...].firstIndex(where: isToolCall)
                ?? rows.firstIndex(where: isToolCall) else { return }
            guard case .toolCall(var call) = rows[index].item else { return }
            call.status = call.status == .completed ? .running : .completed
            rows[index].item = .toolCall(call)
        }

        mutating func prependPage() {
            var page = factory.makeTurn()
            let firstSeq = rows.first?.seqStart ?? 1
            for index in page.indices {
                page[index].seqStart = firstSeq - page.count + index
                page[index].seqEnd = page[index].seqStart
                page[index].id = "old\(firstSeq - page.count + index):\(page[index].id)"
            }
            rows.insert(contentsOf: page, at: 0)
        }

        mutating func removePending() {
            guard let index = rows.lastIndex(where: \.isPending) else { return }
            rows.remove(at: index)
        }

        mutating func replaceAll() {
            factory.rng = SplitMix64(seed: factory.rng.next())
            rows = factory.makeTranscript(turns: factory.rng.int(in: 1..<6))
        }

        /// Retags a row's turn id: merges it into the previous turn or splits a new one off. This is
        /// the "change lands exactly on a turn boundary" case.
        mutating func retagRow() {
            guard rows.count > 1 else { return }
            let index = factory.rng.int(in: 1..<rows.count)
            switch factory.rng.int(in: 0..<3) {
            case 0: rows[index].turnId = rows[index - 1].turnId
            case 1: rows[index].turnId = "t\(factory.turnCounter)"
            default: rows[index].turnId = nil
            }
        }

        mutating func changeActiveTurnId() {
            guard factory.turnCounter > 0 else { return }
            activeTurnId = factory.rng.bool()
                ? "t\(factory.rng.int(in: 0..<factory.turnCounter))" : nil
        }
    }

    private static func expectEqual(
        _ world: World, _ incremental: IncrementalTurnBuilder, _ step: Int
    ) {
        let expected = TurnBuilder.turns(from: world.rows, activeTurnId: world.activeTurnId)
        let actual = incremental.turns(from: world.rows, activeTurnId: world.activeTurnId)
        #expect(actual == expected, "step \(step)")
    }

    // MARK: - 1. Equivalence property test

    @Test func matchesTurnBuilderThroughRandomEdits() {
        var world = World(seed: 0x5EED_1234_ABCD_0001)
        world.rows = world.factory.makeTranscript(turns: 4)
        let incremental = IncrementalTurnBuilder()
        var steps = 0
        var editKinds = Set<Int>()

        for _ in 0..<6000 {
            let kind = world.factory.rng.int(in: 0..<10)
            editKinds.insert(kind)
            switch kind {
            case 0, 1: world.appendTurn()
            case 2: world.appendToLastTurn()
            case 3: world.updateLastText()
            case 4: world.updateToolStatus()
            case 5: world.prependPage()
            case 6: world.removePending()
            case 7: world.replaceAll()
            case 8: world.retagRow()
            default: world.changeActiveTurnId()
            }
            Self.expectEqual(world, incremental, steps)
            steps += 1
        }
        #expect(steps == 6000)
        #expect(editKinds.count == 10)
    }

    /// A second seed, so a failure is not a one-off.
    @Test func matchesTurnBuilderThroughRandomEditsSecondSeed() {
        var world = World(seed: 0xDEAD_BEEF_0BAD_F00D)
        world.rows = world.factory.makeTranscript(turns: 12)
        let incremental = IncrementalTurnBuilder()
        for step in 0..<3000 {
            switch world.factory.rng.int(in: 0..<10) {
            case 0, 1: world.appendTurn()
            case 2: world.appendToLastTurn()
            case 3: world.updateLastText()
            case 4: world.updateToolStatus()
            case 5: world.prependPage()
            case 6: world.removePending()
            case 7: world.replaceAll()
            case 8: world.retagRow()
            default: world.changeActiveTurnId()
            }
            Self.expectEqual(world, incremental, step)
        }
    }

    // MARK: - 2. Targeted edit kinds

    @Test func targetedEditKindsStayEqual() {
        var world = World(seed: 7)
        world.rows = world.factory.makeTranscript(turns: 6)
        let incremental = IncrementalTurnBuilder()
        var step = 0
        Self.expectEqual(world, incremental, step)

        world.appendTurn(); step += 1; Self.expectEqual(world, incremental, step)
        world.appendToLastTurn(); step += 1; Self.expectEqual(world, incremental, step)
        world.updateLastText(); step += 1; Self.expectEqual(world, incremental, step)
        world.updateToolStatus(); step += 1; Self.expectEqual(world, incremental, step)
        world.prependPage(); step += 1; Self.expectEqual(world, incremental, step)
        world.removePending(); step += 1; Self.expectEqual(world, incremental, step)
        world.replaceAll(); step += 1; Self.expectEqual(world, incremental, step)
        world.retagRow(); step += 1; Self.expectEqual(world, incremental, step)
        world.changeActiveTurnId(); step += 1; Self.expectEqual(world, incremental, step)
        world.changeActiveTurnId(); step += 1; Self.expectEqual(world, incremental, step)
        world.appendTurn(); step += 1; Self.expectEqual(world, incremental, step)
    }

    /// A change exactly on a turn boundary can merge the new row into the previous turn. The builder
    /// must start one turn earlier, or it would keep a stale turn.
    @Test func turnBoundaryChangeMergesCorrectly() {
        let rows = [
            row("seq:1", "t1", .assistantMessage(.init(text: "one"))),
            row("seq:2", "t2", .assistantMessage(.init(text: "two"))),
            row("seq:3", "t2", .assistantMessage(.init(text: "three"))),
            row("seq:4", "t3", .assistantMessage(.init(text: "four"))),
        ]
        let incremental = IncrementalTurnBuilder()
        #expect(incremental.turns(from: rows, activeTurnId: nil).count == 3)

        // Row 2 (the start of turn 2) joins turn 1, so turn 2 shrinks to its second row.
        var merged = rows
        merged[1].turnId = "t1"
        let afterMerge = incremental.turns(from: merged, activeTurnId: nil)
        #expect(afterMerge == TurnBuilder.turns(from: merged, activeTurnId: nil))
        #expect(afterMerge.map(\.id) == ["seq:1", "seq:3", "seq:4"])
        #expect(afterMerge[0].segments.count == 2)

        // And back: a turn splits off again at the same boundary.
        let afterSplit = incremental.turns(from: rows, activeTurnId: nil)
        #expect(afterSplit == TurnBuilder.turns(from: rows, activeTurnId: nil))
        #expect(afterSplit.count == 3)
    }

    /// Removing a pending message that started a turn changes the key of the untracked rows after it.
    @Test func removingPendingTurnStartStaysEqual() {
        let rows = [
            row("seq:1", "t1", .assistantMessage(.init(text: "done"))),
            TimelineRow(
                id: "local:c1", turnId: nil,
                item: .userMessage(.init(text: "hello", clientMessageId: "c1")),
                timestamp: "2026-11-08T21:00:02.000Z", seqStart: 2, seqEnd: 2, isPending: true),
            row("seq:3", nil, .reasoning(.init(text: "hm"))),
            row("seq:4", nil, .assistantMessage(.init(text: "hi"))),
        ]
        let incremental = IncrementalTurnBuilder()
        let before = incremental.turns(from: rows, activeTurnId: nil)
        #expect(before.map(\.id) == ["seq:1", "local:c1"])
        #expect(before.count == 2)

        var removed = rows
        removed.remove(at: 1)
        let after = incremental.turns(from: removed, activeTurnId: nil)
        #expect(after == TurnBuilder.turns(from: removed, activeTurnId: nil))
        #expect(after.map(\.id) == ["seq:1"])
    }

    /// Editing one row in the middle of a long transcript must not silently keep stale turns after
    /// it; a middle change is the case a tail-only comparison would get wrong.
    @Test func middleEditRebuildsEverythingAfterIt() {
        var factory = Factory(rng: SplitMix64(seed: 11))
        let rows = factory.makeTranscript(turns: 25)
        let incremental = IncrementalTurnBuilder()
        let initial = incremental.turns(from: rows, activeTurnId: nil)
        #expect(initial == TurnBuilder.turns(from: rows, activeTurnId: nil))
        #expect(initial.count > 20)

        var edited = rows
        let isToolCall: (TimelineRow) -> Bool = { if case .toolCall = $0.item { true } else { false } }
        guard let index = edited.firstIndex(where: isToolCall), index < edited.count / 2 else {
            Issue.record("factory should produce a tool call early"); return
        }
        guard case .toolCall(var call) = edited[index].item else { return }
        call.status = .completed
        edited[index].item = .toolCall(call)

        let after = incremental.turns(from: edited, activeTurnId: nil)
        #expect(after == TurnBuilder.turns(from: edited, activeTurnId: nil))
    }

    @Test func activeTurnIdChangeOnlyRefreshesTheActiveTurn() {
        var factory = Factory(rng: SplitMix64(seed: 5))
        let rows = factory.makeTranscript(turns: 6)
        let active = rows.compactMap(\.turnId).first
        let incremental = IncrementalTurnBuilder()
        let before = incremental.turns(from: rows, activeTurnId: nil)
        #expect(before == TurnBuilder.turns(from: rows, activeTurnId: nil))

        let after = incremental.turns(from: rows, activeTurnId: active)
        #expect(after == TurnBuilder.turns(from: rows, activeTurnId: active))
        #expect(incremental.turnsBuiltLastUpdate <= 2)
        // Only the active turn may differ.
        for (old, new) in zip(before, after) where old.turnId != active {
            #expect(old == new)
        }
    }

    @Test func pendingRowConfirmationKeepsIdentity() {
        let done = TimelineRow(
            id: "seq:1", turnId: "t1", item: .assistantMessage(.init(text: "previous")),
            timestamp: "2026-11-08T21:00:01.000Z", seqStart: 1, seqEnd: 1)
        var pending = TimelineRow(
            id: "local:c1", turnId: nil,
            item: .userMessage(.init(text: "next", clientMessageId: "c1")),
            timestamp: "2026-11-08T21:00:02.000Z", seqStart: 2, seqEnd: 2, isPending: true)
        let incremental = IncrementalTurnBuilder()
        let before = incremental.turns(from: [done, pending], activeTurnId: nil)
        #expect(before.map(\.id) == ["seq:1", "local:c1"])

        pending.isPending = false
        pending.turnId = "t2"
        let reasoning = TimelineRow(
            id: "seq:3", turnId: "t2", item: .reasoning(.init(text: "hm")),
            timestamp: "2026-11-08T21:00:03.000Z", seqStart: 3, seqEnd: 3)
        let after = incremental.turns(from: [done, pending, reasoning], activeTurnId: "t2")
        #expect(after == TurnBuilder.turns(from: [done, pending, reasoning], activeTurnId: "t2"))
        #expect(after.map(\.id) == ["seq:1", "local:c1"])
        #expect(after.last?.phase == .running)
    }

    @Test func unchangedInputBuildsNothing() {
        var world = World(seed: 3)
        world.rows = world.factory.makeTranscript(turns: 8)
        let incremental = IncrementalTurnBuilder()
        let first = incremental.turns(from: world.rows, activeTurnId: nil)
        #expect(incremental.turnsBuiltLastUpdate > 0)
        let second = incremental.turns(from: world.rows, activeTurnId: nil)
        #expect(incremental.turnsBuiltLastUpdate == 0)
        #expect(first == second)
    }

    // MARK: - 3. Reuse check

    @Test func tailUpdatesDoNotRebuildEarlierTurns() {
        var factory = Factory(rng: SplitMix64(seed: 99))
        factory.turnRowCount = 1..<20
        let rows = factory.makeTranscript(turns: 40)
        let incremental = IncrementalTurnBuilder()
        let first = incremental.turns(from: rows, activeTurnId: nil)
        #expect(first.count >= 30)
        let earlier = Array(first.dropLast())

        var working = rows
        factory.appendTailToken(to: &working, index: 0)
        let afterAppend = incremental.turns(from: working, activeTurnId: nil)
        #expect(incremental.turnsBuiltLastUpdate <= 2)
        #expect(Array(afterAppend.prefix(earlier.count)) == earlier)
        #expect(afterAppend == TurnBuilder.turns(from: working, activeTurnId: nil))

        factory.appendTailToken(to: &working, index: 1)
        let afterUpdate = incremental.turns(from: working, activeTurnId: nil)
        #expect(incremental.turnsBuiltLastUpdate <= 2)
        #expect(Array(afterUpdate.prefix(earlier.count)) == earlier)

        factory.appendTailToken(to: &working, index: 2)
        let afterNewRow = incremental.turns(from: working, activeTurnId: nil)
        #expect(incremental.turnsBuiltLastUpdate <= 2)
        #expect(Array(afterNewRow.prefix(earlier.count)) == earlier)
        #expect(afterNewRow == TurnBuilder.turns(from: working, activeTurnId: nil))
    }

    /// A streamed token must not touch the turns above the last one. The row count of the reused
    /// turns is the only thing the builder keeps, so the check above covers turn values; this one
    /// pins the built count for a long transcript with a running turn.
    @Test func streamingRunBuildsOneTurnPerUpdate() {
        var factory = Factory(rng: SplitMix64(seed: 1234))
        factory.turnRowCount = 1..<20
        var rows = factory.makeTranscript(turns: 60)
        let activeTurnId = rows.last?.turnId
        let incremental = IncrementalTurnBuilder()
        _ = incremental.turns(from: rows, activeTurnId: activeTurnId)
        for index in 0..<120 {
            factory.appendTailToken(to: &rows, index: index)
            _ = incremental.turns(from: rows, activeTurnId: activeTurnId)
            #expect(incremental.turnsBuiltLastUpdate <= 2, "update \(index)")
        }
    }

    // MARK: - 4. Timing

    @Test func timingLongTranscript() {
        var factory = Factory(rng: SplitMix64(seed: 42))
        factory.turnRowCount = 1..<20
        var rows: [TimelineRow] = []
        while rows.count < 5000 {
            rows.append(contentsOf: factory.makeTurn())
        }
        let turnCount = TurnBuilder.turns(from: rows, activeTurnId: nil).count

        var fullFactory = factory
        var working = rows
        let fullStart = Date()
        for index in 0..<200 {
            fullFactory.appendTailToken(to: &working, index: index)
            _ = TurnBuilder.turns(from: working, activeTurnId: nil)
        }
        let fullTime = Date().timeIntervalSince(fullStart)

        var incrementalFactory = factory
        working = rows
        let incremental = IncrementalTurnBuilder()
        _ = incremental.turns(from: working, activeTurnId: nil)
        var maxBuilt = 0
        let incrementalStart = Date()
        for index in 0..<200 {
            incrementalFactory.appendTailToken(to: &working, index: index)
            _ = incremental.turns(from: working, activeTurnId: nil)
            maxBuilt = max(maxBuilt, incremental.turnsBuiltLastUpdate)
        }
        let incrementalTime = Date().timeIntervalSince(incrementalStart)

        print(
            "P4 timing: \(rows.count) rows / \(turnCount) turns, 200 tail updates — "
            + "full \(String(format: "%.1f", fullTime * 1000)) ms, "
            + "incremental \(String(format: "%.1f", incrementalTime * 1000)) ms, "
            + "max turns built per update \(maxBuilt)")

        #expect(maxBuilt <= 2)
        #expect(incremental.turns(from: working, activeTurnId: nil)
            == TurnBuilder.turns(from: working, activeTurnId: nil))
    }

    // MARK: - Fixture

    @Test func matchesTurnBuilderOnRecordedTimeline() throws {
        let rows = Load.rows(try Load.page().entries)
        let incremental = IncrementalTurnBuilder()
        var activeTurnId: String?
        for step in 0..<20 {
            // Warm, then apply a no-op and an active change.
            let turns = incremental.turns(from: rows, activeTurnId: activeTurnId)
            #expect(turns == TurnBuilder.turns(from: rows, activeTurnId: activeTurnId), "step \(step)")
            activeTurnId = step % 2 == 0 ? turns.last?.turnId : nil
        }
    }

    private func row(_ id: String, _ turnId: String?, _ item: TimelineItem) -> TimelineRow {
        let seq = Int(id.split(separator: ":").last ?? "1") ?? 1
        return TimelineRow(
            id: id, turnId: turnId, item: item,
            timestamp: "2026-11-08T21:00:0\(seq).000Z", seqStart: seq, seqEnd: seq)
    }
}
