import Foundation
import Highlighter
#if canImport(UIKit)
import UIKit
#endif

/// Identity of one highlight: theme, canonical language, the source's hash and length. Never the source
/// itself, so a cache does not retain every streamed revision of a block.
struct CodeHighlightKey: Hashable, Sendable {
    let theme: ClaudeCodeSyntaxTheme
    let language: String
    let hash: Int
    let count: Int

    init?(code: String, language: String?, theme: ClaudeCodeSyntaxTheme) {
        guard !code.isEmpty, code.utf16.count <= CodeHighlighter.maximumHighlightedUTF16Length,
            let canonical = CodeHighlightCore.canonicalLanguage(language)
        else { return nil }
        self.theme = theme
        self.language = canonical
        self.hash = code.hashValue
        self.count = code.utf16.count
    }
}
