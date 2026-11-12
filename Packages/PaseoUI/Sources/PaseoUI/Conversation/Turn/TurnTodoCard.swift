#if canImport(UIKit)
import PaseoStore
import SwiftUI

// MARK: - TurnTodoCard (Phase C §9.2)

// NOTE: The todo/plan tool calls of a turn become one state, replaced in place as
// updates arrive (`Turn.state`). One card per turn: the latest snapshot while work
// runs (expanded), a one-line summary when everything is done. The list reuses
// `ClaudeTodoCard`; the plan reuses the tool detail's text style.

/// One turn's todo/plan state. Values only (R-2): no closures, interaction state is
/// not part of identity.
struct TurnTodoCard: View, Equatable {
    let state: TurnTodoState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: Bool

    init(state: TurnTodoState) {
        self.state = state
        _expanded = State(initialValue: !state.isComplete)
    }

    /// Compared for `==`; interaction state is not part of identity (the TurnRow
    /// pattern: the row's inputs decide re-renders, not its disclosure).
    nonisolated static func == (lhs: TurnTodoCard, rhs: TurnTodoCard) -> Bool {
        lhs.state == rhs.state
    }

    private var doneCount: Int { state.todos?.count { $0.completed } ?? 0 }
    private var totalCount: Int { state.todos?.count ?? 0 }

    private var summaryText: String {
        if state.todos == nil { return "Plan" }
        if state.isComplete { return "\(totalCount) tasks done" }
        return "\(doneCount) of \(totalCount) tasks"
    }

    var body: some View {
        if expanded {
            expandedCard
        } else {
            Button {
                withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                    expanded = true
                }
                Haptics.selection()
            } label: {
                PaseoCard(content:
                    HStack(spacing: Space.sm) {
                        Image(
                            systemName: state.isComplete
                                ? "checkmark.circle.fill" : "circle.dotted"
                        )
                        .font(.glyph(.regular, weight: .medium))
                        .foregroundStyle(
                            state.isComplete ? Palette.successInk : Palette.secondaryInk)
                        .accessibilityHidden(true)
                        Text(summaryText)
                            .font(.paseo(.callout))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down")
                            .font(.glyph(.small, weight: .semibold))
                            .foregroundStyle(Palette.secondaryInk)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Metrics.rowCardMinHeight - Space.md * 2)
                    .contentShape(.rect))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summaryText)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Expands the task list")
        }
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let todos = state.todos {
                ClaudeTodoCard(list: TimelineItem.TodoList(items: todos))
            }
            if let plan = state.plan {
                PaseoCard(content:
                    Text(plan)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading))
            }
            Button {
                withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                    expanded = false
                }
                Haptics.selection()
            } label: {
                Text("Show less")
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse the task list")
        }
    }
}
#endif
