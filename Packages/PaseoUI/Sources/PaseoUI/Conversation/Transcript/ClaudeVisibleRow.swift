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

    var body: some View {
        if case .compaction(let status, let trigger, let preTokens) = row.item {
            ClaudeCompactionMarker(status: status, trigger: trigger, preTokens: preTokens)
                .rowAnchor(row.seqEnd)
                .background { FindWash(highlighted: highlightedSeq == row.seqEnd) }
        } else {
            ClaudeMidTurnBubble(row: row, highlightedSeq: highlightedSeq)
        }
    }
}
#endif
