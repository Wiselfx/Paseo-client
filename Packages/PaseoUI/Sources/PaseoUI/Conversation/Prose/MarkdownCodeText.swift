#if canImport(UIKit)
import SwiftUI

/// The text of one fenced code block. First paint is plain mono in ink; the highlighted tokens
/// swap in from the actor with the same font and metrics, so there is no layout jump (R9 §1).
/// A host's `codeContent` replaces the highlighter.
///
/// `maxLines` draws only the first lines of the text. The inline block sets it and the expand sheet
/// does not. The cut happens before the highlighter or the host sees the text, so a capped block
/// highlights and lays out just the lines it shows.
struct MarkdownCodeText: View {
    let language: String?
    let content: String
    let theme: ClaudeMarkdownTheme
    let isStreaming: Bool
    let codeContent: ((String?, String) -> AttributedString)?
    /// The most lines to draw; nil draws every line.
    var maxLines: Int? = nil

    var body: some View {
        let shown = maxLines.map { Self.leadingLines(of: content, maxLines: $0) } ?? content
        if let codeContent {
            Text(codeContent(language, shown))
                .font(theme.codeFont)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .codeTypeScale()
        } else {
            ClaudeHighlightedCode(
                language: language, content: shown, theme: theme,
                isStreaming: isStreaming
            )
            .textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: false)
            .codeTypeScale()
        }
    }

    /// The number of lines in `text`. A line ends at LF or CRLF, and a final break ends the last line
    /// rather than starting an empty one, so 24 lines with a trailing newline count as 24. It is a
    /// byte count, not a walk over characters, because the inline block runs it on every body pass.
    static func lineCount(of text: String) -> Int {
        guard let last = text.utf8.last else { return 0 }
        return text.utf8.count(where: { $0 == 0x0A }) + (last == 0x0A ? 0 : 1)
    }

    /// The first `maxLines` lines of `text`, joined with LF, or `text` itself (no copy) when no line
    /// follows them. The split stops after the `maxLines`-th break, so a very long text is never
    /// split whole.
    static func leadingLines(of text: String, maxLines: Int) -> String {
        let pieces = text.split(
            maxSplits: maxLines, omittingEmptySubsequences: false, whereSeparator: isLineBreak)
        // At most maxLines + 1 pieces, and the last one is the unscanned rest. An empty rest means
        // the text ends on the break of its last line, so there is nothing to cut.
        guard pieces.count > maxLines, let rest = pieces.last, !rest.isEmpty else { return text }
        return pieces.prefix(maxLines).joined(separator: "\n")
    }

    /// LF, or the CRLF pair, which Swift reads as one Character.
    private static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r\n"
    }
}
#endif
