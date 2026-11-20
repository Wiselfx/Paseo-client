#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// The Tasks track: "Tasks", "{{completed}}/{{total}} tasks", then the rows.
struct ClaudeTodoCard: View {
    let list: TimelineItem.TodoList


    private var completed: Int { list.items.count { $0.completed } }

    var body: some View {
        ClaudeCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Tasks").font(.paseo(.callout, weight: .medium)).foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Text("\(PaseoFormat.integer(completed))/\(PaseoFormat.integer(list.items.count)) tasks")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                }
                ClaudeDivider()
                ForEach(Array(list.items.enumerated()), id: \.offset) { _, todo in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: symbol(for: todo))
                            .font(.glyph(.small))
                            .foregroundStyle(todo.completed ? Palette.successInk : Palette.secondaryInk)
                        Text(todo.status == "in_progress" ? (todo.activeForm ?? todo.text) : todo.text)
                            .font(.paseo(.callout))
                            .foregroundStyle(todo.completed ? Palette.secondaryInk : Palette.ink)
                            .strikethrough(todo.completed, color: Palette.tertiaryInk)
                    }
                }
            }
            .padding(12)
        }
    }

    private func symbol(for todo: TimelineItem.TodoList.Todo) -> String {
        if todo.completed { return "checkmark.circle.fill" }
        return todo.status == "in_progress" ? "circle.dotted" : "circle"
    }
}
#endif
