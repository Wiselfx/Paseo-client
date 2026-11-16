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
#endif
