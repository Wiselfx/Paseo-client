import Foundation
import PaseoProtocol

// MARK: - TurnTodoState (Phase C §9.2)

// NOTE: The todo/plan tool calls of a turn become one state, replaced in place as
// updates arrive: every `todo` timeline item carries a full snapshot list, so the
// latest row IS the state (no accumulation), and the latest `plan` tool call is the
// plan. The card shows this state live — including on the running turn — and
// collapses to a one-line summary when every todo is done.
//
// Provider table (frozen upstream `packages/server/src/server/agent/providers/`):
// - claude: `TodoWrite` plus the ID-based `TaskCreate`/`TaskUpdate`/`TaskList`
//   accumulate into canonical `todo` snapshots
//   (`claude/tool-call-mapper.ts:3`, `:72-106`); `ExitPlanMode` maps to the `plan`
//   kind (`claude/agent.ts:1158`). `acp-agent.ts` also forwards `plan` session
//   updates (`:3263`, `:3923`).
// - opencode: the `todowrite` tool maps to `todo` items
//   (`opencode-agent.ts:2098` via `mapOpenCodeTodosToTimelineItems` at `:2148`).
//   The v2 directory has no todowrite tool.
// - pi: no built-in todo tool; goal/todo extensions emit `todo` items directly
//   (`pi/extensions/pi-goal-x/index.ts:69`, `pi/extensions/rpiv-todo/index.ts:38`,
//   `pi/extensions/pi-example-todo/index.ts:29`).

/// One turn's todo/plan state: the latest snapshot list plus the latest plan text.
/// Nil when the turn has neither: most turns show no card at all.
public struct TurnTodoState: Sendable, Equatable {
    /// The latest todo snapshot, in order. Nil when the turn never had todos.
    public var todos: [TimelineItem.TodoList.Todo]?
    /// The latest plan text. Nil when the turn never presented a plan.
    public var plan: String?
    /// Every todo completed (and at least one): the card collapses to one line.
    public var isComplete: Bool

    public init(
        todos: [TimelineItem.TodoList.Todo]? = nil, plan: String? = nil, isComplete: Bool = false
    ) {
        self.todos = todos
        self.plan = plan
        self.isComplete = isComplete
    }

    /// Reduces a turn to its todo/plan state: the LAST `todo` row's full snapshot
    /// plus the LAST `plan` tool call. O(rows), no parsing — cheap enough to run
    /// on every tail rebuild, so the card updates live while the turn runs.
    public static func reduce(turn: Turn) -> TurnTodoState? {
        var todos: [TimelineItem.TodoList.Todo]?
        var plan: String?
        for segment in turn.segments {
            switch segment {
            case .todo(let row):
                if case .todo(let list) = row.item { todos = list.items }
            case .work(let group):
                for row in group.rows {
                    guard case .toolCall(let call) = row.item else { continue }
                    if case .plan(let text) = call.detail { plan = text }
                }
            default:
                break
            }
        }
        guard todos != nil || plan != nil else { return nil }
        let complete = todos.map { !$0.isEmpty && $0.allSatisfy(\.completed) } ?? false
        return TurnTodoState(todos: todos, plan: plan, isComplete: complete)
    }
}
