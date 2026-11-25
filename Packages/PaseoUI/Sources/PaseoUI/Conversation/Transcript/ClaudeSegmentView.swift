#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A segment of a turn.
///
/// Equatable on its value inputs, like `TurnRow` and `ClaudeMarkdownView`, so a finished segment
/// of a running turn skips its body while the tail streams. The closures are not compared on
/// purpose: they are methods of the stable `ChatActions`.
struct ClaudeSegmentView: View, Equatable {
    let segment: Turn.Segment
    let turnIsRunning: Bool
    /// The turn's newest segment while it runs: its last step is the one happening now. Only its
    /// prose streams; an older prose segment runs no reveal loop of its own.
    var isTail: Bool = false
    let onMarkdown: (MarkdownAction) -> Void
    var highlightedSeq: Int?
    var findTarget: Int?
    var onOpenFile: ((String) -> Void)?

    /// Equal inputs skip `body`, so a streamed token re-evaluates only the segment it changed.
    /// Statements, not one `&&` chain, as in `ClaudeMarkdownView`.
    nonisolated static func == (lhs: ClaudeSegmentView, rhs: ClaudeSegmentView) -> Bool {
        guard lhs.segment == rhs.segment else { return false }
        guard lhs.turnIsRunning == rhs.turnIsRunning else { return false }
        guard lhs.isTail == rhs.isTail else { return false }
        guard lhs.highlightedSeq == rhs.highlightedSeq else { return false }
        return lhs.findTarget == rhs.findTarget
    }

    var body: some View {
        switch segment {
        case .work(let group):
            WorkDigest(
                group: group, isTail: isTail,
                highlightedSeq: highlightedSeq, findTarget: findTarget, onOpenFile: onOpenFile)
        case .prose(let row):
            if case .assistantMessage(let message) = row.item {
                // Only the tail streams: an older prose segment of a running turn runs no reveal
                // loop, and its paced backlog drains once it stops being the tail.
                ClaudeProse(
                    markdown: message.text, onAction: onMarkdown,
                    isStreaming: turnIsRunning && isTail,
                    revealKey: row.id, revealsFresh: isTail)
                    .rowAnchor(row.seqEnd)
                    .background { FindWash(highlighted: highlightedSeq == row.seqEnd) }
            }
        case .todo:
            // The per-turn card above owns todos now: a row here would duplicate it.
            EmptyView()
        case .notice(let row):
            // A message sent mid-turn is a notice row in the model (Turn.swift TurnDraft.add).
            if case .userMessage = row.item {
                ClaudeMidTurnBubble(row: row, highlightedSeq: highlightedSeq)
            } else {
                ClaudeNoticeRow(item: row.item)
            }
        }
    }
}
#endif
