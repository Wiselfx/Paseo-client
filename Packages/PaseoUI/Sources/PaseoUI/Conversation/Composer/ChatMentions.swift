#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The draft-text half of the mention popover, pure so the draft observer can ask without
/// reading anything else from the conversation (P3).
enum ChatMentions {
    /// The `@token` query while `text` is exactly one mention token after whitespace/start.
    static func query(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        let before = text[..<at]
        let preceded =
            before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n") || before.hasSuffix("\t")
        guard preceded else { return nil }
        let query = String(text[text.index(after: at)...])
        if query.contains(where: { $0.isWhitespace }) { return nil }
        return query
    }
}

extension ClaudeChatView {
    // MARK: Mentions (M8d)

    /// The `@token` query while the draft is exactly one mention token after whitespace/start.
    var mentionQuery: String? { ChatMentions.query(in: store.draft) }

    /// The open workspace's checkout (same pattern as `localImageLoader`).
    var mentionCheckout: CheckoutStore? {
        guard let workspaceId = store.agent?.workspaceId,
            let descriptor = session.workspaceDirectory.workspace(id: workspaceId)
        else { return nil }
        return session.checkout(for: descriptor)
    }

    /// Builds the file index once, then filters locally.
    func loadMentionIndexIfNeeded() async {
        guard let checkout = mentionCheckout else { return }
        await mentionIndex.build(using: checkout.files)
        if let query = mentionQuery {
            mentionMatches = mentionIndex.matches(query: query, recent: recentMentions)
        }
    }

    func handleMentionPick(_ row: MentionIndexRow) {
        Haptics.selection()
        if row.isDirectory {
            // Drill in: keep the popover open, token becomes `@path/`.
            replaceMentionToken(with: row.path + "/")
        } else {
            replaceMentionToken(with: row.path + " ")
            recentMentions.removeAll { $0 == row.path }
            recentMentions.insert(row.path, at: 0)
            if recentMentions.count > 8 { recentMentions.removeLast() }
        }
    }

    /// Replaces the trailing `@token` with `replacement` (mention insert / drill-in).
    func replaceMentionToken(with replacement: String) {
        let text = store.draft
        guard let at = text.lastIndex(of: "@") else { return }
        let before = text[..<at]
        store.draft = String(before) + "@" + replacement
        focused = true
    }

    @ViewBuilder var mentionMenu: some View {
        if mentionQuery != nil, !mentionMatches.isEmpty || mentionIndex.isBuilding {
            MentionMenu(rows: mentionMatches, isBuilding: mentionIndex.isBuilding) { row in
                handleMentionPick(row)
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

}
#endif
