import PaseoStore
import SwiftUI

/// "2 thoughts, 1 tool call": a card of steps, each of which opens on its own.
struct WorkGroupView: View {
    let group: Turn.WorkGroup
    let turnIsRunning: Bool
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureHeader(isExpanded: $expanded, chevronLeading: true) {
                Text(group.summary)
                    .font(Typeset.serif(17))
                    .foregroundStyle(Palette.secondaryInk)
            }
            if expanded {
                Card {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider().overlay(Palette.hairline) }
                            StepView(row: row, isLive: turnIsRunning && index == group.rows.count - 1)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

/// One thought or tool call inside a work group.
struct StepView: View {
    let row: TimelineRow
    /// The newest step of a running turn: open by default so you can watch it.
    let isLive: Bool
    @State private var userExpanded: Bool?

    private var isExpanded: Bool { userExpanded ?? isLive }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureHeader(isExpanded: Binding(get: { isExpanded }, set: { userExpanded = $0 })) { label }
            if isExpanded {
                detail.transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var label: some View {
        switch row.item {
        case .reasoning(let reasoning):
            HStack(spacing: 8) {
                Text("Thought").font(Typeset.chromeEmphasis).foregroundStyle(Palette.secondaryInk)
                if !isExpanded {
                    Text(reasoning.text.replacingOccurrences(of: "\n", with: " "))
                        .font(Typeset.chrome)
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                }
            }
        case .toolCall(let call):
            let presentation = ToolCallPresentation(call)
            HStack(spacing: 8) {
                Image(systemName: presentation.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 18)
                Text(presentation.title).font(Typeset.chromeEmphasis).foregroundStyle(Palette.ink)
                if let subtitle = presentation.subtitle {
                    Text(subtitle)
                        .font(Typeset.chrome)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                StatusDot(status: presentation.status.codeBlockStatus)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var detail: some View {
        switch row.item {
        case .reasoning(let reasoning):
            Text(reasoning.text)
                .font(Typeset.proseSecondary)
                .foregroundStyle(Palette.secondaryInk)
                .textSelection(.enabled)
        case .toolCall(let call):
            ToolCallDetailView(call: call)
        default:
            EmptyView()
        }
    }
}

extension ToolCallPresentation.Status {
    var codeBlockStatus: OutputBlock.Status {
        switch self {
        case .running: .running
        case .succeeded: .succeeded
        case .failed, .canceled: .failed
        }
    }
}
