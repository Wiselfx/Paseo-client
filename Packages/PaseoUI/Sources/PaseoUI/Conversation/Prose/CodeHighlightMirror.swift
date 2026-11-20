import Foundation
import Highlighter
#if canImport(UIKit)
import UIKit
#endif

/// A thread-safe copy of the actor's finished highlights (W1), readable without awaiting: a code block
/// whose highlight already exists (the warm-up, an earlier visit) draws it on its first pass, so the block
/// is laid out once instead of plain first and again when the actor answers.
enum CodeHighlightMirror {
    private static let table = ProseCache<CodeHighlightKey, AttributedString>(
        budget: 8 * 1024 * 1024, countLimit: 128, cost: { key, _ in key.count * 4 })

    static func store(_ value: AttributedString, for key: CodeHighlightKey) {
        table.setValue(value, for: key)
    }

    static func value(code: String, language: String?, theme: ClaudeCodeSyntaxTheme) -> AttributedString? {
        guard let key = CodeHighlightKey(code: code, language: language, theme: theme) else { return nil }
        return table.value(for: key)
    }
}
