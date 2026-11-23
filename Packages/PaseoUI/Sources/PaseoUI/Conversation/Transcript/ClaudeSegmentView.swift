#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A segment of a turn.

struct ClaudeSegmentView: View {
    let segment: Turn.Segment
    let turnIsRunning: Bool
    /// The turn's newest segment while it runs: its last step is the one happening now.
    var isTail: Bool = false
    let onMarkdown: (MarkdownAction) -> Void
    var highlightedSeq: Int?
    var findTarget: Int?
    var onOpenFile: ((String) -> Void)?

    var body: some View {
        switch segment {
        case .work(let group):
            WorkDigest(
                group: group, isTail: isTail,
                highlightedSeq: highlightedSeq, findTarget: findTarget, onOpenFile: onOpenFile)
        case .prose(let row):
            if case .assistantMessage(let message) = row.item {
                ClaudeProse(
                    markdown: message.text, onAction: onMarkdown, isStreaming: turnIsRunning,
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
