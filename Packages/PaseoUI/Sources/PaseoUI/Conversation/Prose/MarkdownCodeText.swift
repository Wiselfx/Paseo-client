#if canImport(UIKit)
import SwiftUI

/// The text of one fenced code block. First paint is plain mono in ink; the highlighted tokens
/// swap in from the actor with the same font and metrics, so there is no layout jump (R9 §1).
/// A host's `codeContent` replaces the highlighter.
struct MarkdownCodeText: View {
    let language: String?
    let content: String
    let theme: ClaudeMarkdownTheme
    let isStreaming: Bool
    let codeContent: ((String?, String) -> AttributedString)?

    var body: some View {
        if let codeContent {
            Text(codeContent(language, content))
                .font(theme.codeFont)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .codeTypeScale()
        } else {
            ClaudeHighlightedCode(
                language: language, content: content, theme: theme,
                isStreaming: isStreaming
            )
            .textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: false)
            .codeTypeScale()
        }
    }
}
#endif
