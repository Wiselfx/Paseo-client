#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Your prompt at the head of a turn: the "Sent by" line, the bubble with its rewind menu, and the
/// find wash. The folded and the full turn draw it the same way, so it lives here once.
struct TurnPrompt: View {
    let row: TimelineRow
    let message: TimelineItem.UserMessage
    /// The scopes the rewind menu offers; empty hides it.
    var rewindChoices: [RewindScope] = []
    var rewindInFlight: Bool = false
    /// This prompt is the find match the row should flash.
    var isHighlighted: Bool = false
    /// Called with (scope, messageId); the transcript presents the confirmation dialog.
    var onRewind: ((RewindScope, String) -> Void)?

    /// Upstream shows the rewind control only on an acknowledged message with text
    /// (message.tsx:422 showTrailingRow, :514 hasText, :530 messageId). The provider has to
    /// acknowledge the prompt before it can be rewound to.
    private var rewindable: Bool {
        message.messageId != nil && !message.text.isEmpty && !row.isPending && !rewindChoices.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let sender = message.sender {
                // "Sent by {{name}}" above the bubble (upstream `user-message/index.tsx:95`,
                // rendered from `message.tsx:481`), named by `agentTitle` (see `ClaudeSentByLine`).
                ClaudeSentByLine(sender: sender)
            }
            ClaudeUserBubble(
                text: message.text, isPending: row.isPending,
                rewindChoices: rewindable ? rewindChoices : [],
                onRewind: rewindable ? { scope in onRewind?(scope, message.messageId ?? "") } : nil,
                rewindInFlight: rewindInFlight,
                clientMessageId: message.clientMessageId,
                sentAt: PaseoDate.parse(row.timestamp)
            )
            .rowAnchor(row.seqEnd)
            .background { FindWash(highlighted: isHighlighted) }
        }
    }
}
#endif
