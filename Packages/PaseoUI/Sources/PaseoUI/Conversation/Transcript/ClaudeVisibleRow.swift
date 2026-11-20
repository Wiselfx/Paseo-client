#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A row that stays in the chat while the work is folded: a message you sent mid-turn
/// (`ClaudeMidTurnBubble`) or a compaction marker (`ClaudeCompactionMarker`, the same marker
/// `ClaudeNoticeRow` draws in place). Upstream keeps both visible (`turn-collapse/model.ts:102`).
struct ClaudeVisibleRow: View {
    let row: TimelineRow
    var highlightedSeq: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if case .compaction(let status, let trigger, let preTokens) = row.item {
            ClaudeCompactionMarker(status: status, trigger: trigger, preTokens: preTokens)
                .rowAnchor(row.seqEnd)
                .background {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(Palette.warning.opacity(highlightedSeq == row.seqEnd ? 0.18 : 0))
                        .animation(Motion.settle.resolved(reduceMotion: reduceMotion), value: highlightedSeq)
                }
        } else {
            ClaudeMidTurnBubble(row: row, highlightedSeq: highlightedSeq)
        }
    }
}
#endif
