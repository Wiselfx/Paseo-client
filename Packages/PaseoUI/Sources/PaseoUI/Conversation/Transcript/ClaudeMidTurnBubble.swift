#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A message you sent while the turn was running, shown as the same bubble as the turn's first
/// message. Upstream shows a user message as a normal row wherever it falls in the stream
/// (`packages/app/src/agent-stream/layout.ts:330-331`). Drawn in two places, never both at once:
/// in place among the work when the work is shown, after the summary when it is folded.
struct ClaudeMidTurnBubble: View {
    let row: TimelineRow
    var highlightedSeq: Int?

    var body: some View {
        if case .userMessage(let message) = row.item {
            VStack(alignment: .leading, spacing: 14) {
                if let sender = message.sender {
                    ClaudeSentByLine(sender: sender)
                }
                // No rewind on a steered message: it is not a rewind point here.
                ClaudeUserBubble(
                    text: message.text, isPending: row.isPending,
                    rewindChoices: [], onRewind: nil,
                    clientMessageId: message.clientMessageId,
                    sentAt: PaseoDate.parse(row.timestamp)
                )
                .rowAnchor(row.seqEnd)
                .background { FindWash(highlighted: highlightedSeq == row.seqEnd) }
            }
        }
    }
}
#endif
