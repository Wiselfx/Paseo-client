#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One row of a provider subagent's timeline. A struct rather than a `@ViewBuilder` method so
/// each `ForEach` element is exactly one view of one type: the branch taken is not part of the
/// row's identity, and the lazy stack keeps its fast path as older pages are prepended.
struct SubagentTimelineRow: View {
    let row: ProviderSubagentTimelineRequest.Response.Row

    var body: some View {
        switch row.item {
        case .userMessage(let message):
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("TASK")
                    .font(.paseo(.caption2, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.tertiaryInk)
                Text(message.text)
                    .font(.paseo(.processTitle))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .assistantMessage(let message):
            Text(message.text)
                .font(.paseo(.processTitle))
                .foregroundStyle(Palette.ink)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        case .reasoning(let reasoning):
            Text(reasoning.text.replacing("\n", with: " "))
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.tertiaryInk)
                .lineLimit(2)
        case .toolCall(let call):
            ToolCallLine(call: call)
        case .todo(let list):
            Text("Todo · \(PaseoFormat.integer(list.items.count)) item\(list.items.count == 1 ? "" : "s")")
                .font(.paseo(.codeSmall))
                .foregroundStyle(Palette.tertiaryInk)
        case .error(let message):
            Text(message)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.failureInk)
        case .notification(let level, let message):
            Text("\(level) · \(message)")
                .font(.paseo(.caption))
                .foregroundStyle(Palette.tertiaryInk)
        case .compaction:
            Text("Compacted")
                .font(.paseo(.caption))
                .foregroundStyle(Palette.tertiaryInk)
        case .unknown:
            Text("Unknown item")
                .font(.paseo(.caption))
                .foregroundStyle(Palette.tertiaryInk)
        }
    }
}
#endif
