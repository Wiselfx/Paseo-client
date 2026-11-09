#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Assistant prose with rich-content blocks interleaved in document order: Markdown
/// chunks render through `ClaudeMarkdownView`; detector blocks render through their
/// card views. Detection is memoized (`RichContentCache`), so streaming deltas stay cheap.
struct ClaudeRichDocument: View {
    let markdown: String
    let theme: ClaudeMarkdownTheme
    let onAction: (MarkdownAction) -> Void
    let localImageLoader: ((String) async -> UIImage?)?

    var body: some View {
        let pieces = richPieces(markdown)
        let indices = pieces.indices
        VStack(alignment: .leading, spacing: theme.blockSpacing) {
            ForEach(indices, id: \.self) { index in
                switch pieces[index] {
                case .markdown(let chunk):
                    let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        ClaudeMarkdownView(trimmed, theme: theme, onAction: onAction)
                    }
                case .block(let block):
                    ClaudeRichBlockView(block: block, localImageLoader: localImageLoader)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
