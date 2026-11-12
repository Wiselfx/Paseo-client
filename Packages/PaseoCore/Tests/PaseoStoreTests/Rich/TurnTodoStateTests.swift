import Foundation
import Testing

@testable import PaseoProtocol
@testable import PaseoStore

// Phase C §9.2: the todo/plan tool calls of a turn become one state.
struct TurnTodoStateTests {
    private func todoRow(
        id: String, turnId: String = "t1", seq: Int, items: [TimelineItem.TodoList.Todo]
    ) -> TimelineRow {
        TimelineRow(
            id: id, turnId: turnId,
            item: .todo(TimelineItem.TodoList(items: items)),
            timestamp: "2026-01-01T00:00:00Z", seqStart: seq, seqEnd: seq)
    }

    private func planRow(id: String, turnId: String = "t1", seq: Int, text: String) -> TimelineRow {
        TimelineRow(
            id: id, turnId: turnId,
            item: .toolCall(ToolCall(
                callId: id, name: "ExitPlanMode", status: .completed, detail: .plan(text: text))),
            timestamp: "2026-01-01T00:00:00Z", seqStart: seq, seqEnd: seq)
    }

    private func todo(text: String, completed: Bool, status: String? = nil) -> TimelineItem.TodoList.Todo
    {
        TimelineItem.TodoList.Todo(
            text: text, completed: completed, id: nil, status: status, activeForm: nil)
    }

    private func turn(_ rows: [TimelineRow], activeTurnId: String? = nil) -> Turn {
        let turns = TurnBuilder.turns(from: rows, activeTurnId: activeTurnId)
        #expect(turns.count == 1)
        return turns[0]
    }

    @Test("a turn without todos or plans has no state")
    func emptyTurnHasNoState() {
        let row = TimelineRow(
            id: "u", turnId: "t1",
            item: .userMessage(TimelineItem.UserMessage(text: "go")),
            timestamp: "2026-01-01T00:00:00Z", seqStart: 0, seqEnd: 0)
        #expect(turn([row]).todoState == nil)
    }

    @Test("the latest todo snapshot wins")
    func latestSnapshotWins() {
        let state = turn([
            todoRow(id: "d1", seq: 1, items: [todo(text: "a", completed: false)]),
            todoRow(
                id: "d2", seq: 2,
                items: [
                    todo(text: "a", completed: true), todo(text: "b", completed: false)
                ]),
        ]).todoState
        #expect(state?.todos?.map(\.text) == ["a", "b"])
        #expect(state?.isComplete == false)
    }

    @Test("all done collapses")
    func allDoneCollapses() {
        let state = turn([
            todoRow(
                id: "d1", seq: 1,
                items: [todo(text: "a", completed: true), todo(text: "b", completed: true)]),
        ]).todoState
        #expect(state?.isComplete == true)
    }

    @Test("the latest plan wins and rides with todos")
    func latestPlanWins() {
        let state = turn([
            planRow(id: "p1", seq: 1, text: "first"),
            todoRow(id: "d1", seq: 2, items: [todo(text: "a", completed: false)]),
            planRow(id: "p2", seq: 3, text: "second"),
        ]).todoState
        #expect(state?.plan == "second")
        #expect(state?.todos?.count == 1)
        #expect(state?.isComplete == false)
    }

    @Test("the state updates on the running turn")
    func runningTurnHasState() {
        let built = turn(
            [todoRow(id: "d1", seq: 1, items: [todo(text: "a", completed: false)])],
            activeTurnId: "t1")
        #expect(built.phase == .running)
        #expect(built.todoState?.todos?.count == 1)
    }
}
