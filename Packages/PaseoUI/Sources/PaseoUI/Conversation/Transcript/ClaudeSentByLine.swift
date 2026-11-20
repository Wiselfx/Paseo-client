#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// "Sent by {{name}}" above a message you sent (upstream `user-message/index.tsx:95`). The name
/// is the sending agent's live title, then the sender's own title, then its id
/// (`TurnSummary.senderName`). Copy: `turnSummary.sentBy` (`en.ts:2151`).
struct ClaudeSentByLine: View {
    let sender: TimelineItem.AgentMessage.Sender
    @Environment(\.chatActions) private var actions

    /// A sender with no title anywhere falls back to its id (upstream does the same). A full
    /// UUID is noise on a chat row, so the view shows its first eight characters.
    private var name: String {
        let resolved = TurnSummary.senderName(
            agentTitle: actions?.agentTitle(sender.id), senderTitle: sender.title,
            senderID: sender.id)
        guard resolved == sender.id, UUID(uuidString: resolved) != nil else { return resolved }
        return String(resolved.prefix(8))
    }

    var body: some View {
        Text(TurnSummary.sentByLabel(name: name))
            .font(.paseo(.code))
            .foregroundStyle(Palette.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
#endif
