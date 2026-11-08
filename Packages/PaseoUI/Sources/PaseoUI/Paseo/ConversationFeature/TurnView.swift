import PaseoStore
import SwiftUI

/// One turn, the way Claude for iOS shows it:
///
///     [your bubble]
///     Completed in 4s ›            ← collapses everything but the final answer
///       ⌄ 2 thoughts, 1 tool call  ← each work group collapses on its own
///       …
///     final answer
///
/// While the turn runs it stays open and the header is a shimmering quip.
struct TurnView: View {
    let turn: Turn
    let onOpenURL: (URL) -> Void
    /// Nil until the user taps, so the default can follow the turn's phase.
    @State private var userExpanded: Bool?

    private var isRunning: Bool { turn.phase == .running }
    private var isExpanded: Bool { userExpanded ?? isRunning }

    /// The answer shown even when collapsed: the last segment, if it's prose and the turn is done.
    private var finalProse: TimelineRow? {
        guard !isRunning, case .prose(let row)? = turn.segments.last else { return nil }
        return row
    }

    private var bodySegments: [Turn.Segment] {
        finalProse == nil ? turn.segments : Array(turn.segments.dropLast())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let row = turn.userMessage, case .userMessage(let message) = row.item {
                UserBubble(text: message.text, isPending: row.isPending)
            }
            if isRunning || !bodySegments.isEmpty {
                header
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(bodySegments) { segment in
                        SegmentView(segment: segment, turnIsRunning: isRunning, onOpenURL: onOpenURL)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let finalProse, case .assistantMessage(let message) = finalProse.item {
                Prose(message.text, onOpenURL: onOpenURL)
            }
        }
        .onChange(of: isRunning) { _, running in
            // A finished turn folds itself away unless the user chose otherwise.
            if !running { withAnimation(.snappy(duration: 0.35)) { userExpanded = nil } }
        }
    }

    @ViewBuilder private var header: some View {
        let expanded = Binding(get: { isExpanded }, set: { userExpanded = $0 })
        switch turn.phase {
        case .running:
            DisclosureHeader(isExpanded: expanded) { WorkingLabel(seed: turn.id) }
        case .completed:
            DisclosureHeader(isExpanded: expanded) {
                Text(turn.duration.map(DurationText.completed) ?? "Completed")
                    .font(Typeset.chrome)
                    .foregroundStyle(Palette.secondaryInk)
            }
        case .failed(let message):
            DisclosureHeader(isExpanded: expanded) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Typeset.chrome)
                    .foregroundStyle(Palette.failure)
                    .lineLimit(2)
            }
        }
    }
}

struct SegmentView: View {
    let segment: Turn.Segment
    let turnIsRunning: Bool
    let onOpenURL: (URL) -> Void

    var body: some View {
        switch segment {
        case .work(let group):
            WorkGroupView(group: group, turnIsRunning: turnIsRunning)
        case .prose(let row):
            if case .assistantMessage(let message) = row.item {
                Prose(message.text, onOpenURL: onOpenURL)
            }
        case .todo(let row):
            if case .todo(let list) = row.item { TodoCard(list: list) }
        case .notice(let row):
            NoticeRow(item: row.item)
        }
    }
}
