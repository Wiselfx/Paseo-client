#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Renders one block. A named view per block kind (P5-B): type erasure hides the block type
/// from SwiftUI's diff engine, so every prose re-render rebuilt the whole block subtree. The
/// concrete type per branch lets unchanged blocks be skipped.
struct MarkdownBlockView: View {
    let block: MarkdownBlock
    /// The block's document-unique path (`String.markdownChild`): nested tables are told apart by it.
    let path: String
    let context: MarkdownRenderContext

    private var theme: ClaudeMarkdownTheme { context.theme }

    var body: some View {
        switch block {
        case .paragraph(let content):
            if content.count == 1, case .image(let image) = content[0],
                let imageContent = context.imageContent
            {
                imageContent(image)
            } else {
                MarkdownInlineText(content: content, theme: theme)
            }
        case .heading(let level, let content):
            MarkdownInlineText(
                content: content, theme: theme,
                font: (theme.headingFonts.isEmpty
                    ? ProseFonts.serif(size: theme.bodySize, relativeTo: .headline, weight: .semibold)
                    : theme.headingFonts[min(max(level - 1, 0), theme.headingFonts.count - 1)])
            ).accessibilityAddTraits(.isHeader)
        case .rule:
            Rectangle().fill(theme.rule).frame(height: 1).accessibilityLabel("Horizontal rule")
        case .quote(let children):
            MarkdownBlockList(blocks: children, path: path, context: context)
                .foregroundStyle(theme.secondary)
                .padding(.horizontal, MarkdownMetrics.quoteHorizontalInset)  // .6em 1em ≈ .6em vertical, 1em horizontal
                .padding(.vertical, MarkdownMetrics.quoteVerticalInset)
                .background(
                    theme.quoteWash,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: Radius.sm,
                        topTrailingRadius: Radius.sm))
                .accessibilityIdentifier("markdown.quote")
        case .list(let start, let items):
            VStack(alignment: .leading, spacing: theme.listSpacing) {
                ForEach(items.identifiedItems()) { identified in
                    HStack(alignment: .firstTextBaseline, spacing: MarkdownMetrics.listMarkerSpacing) {
                        MarkdownListMarker(
                            checked: identified.value.checked, start: start, index: identified.index,
                            theme: theme)
                        MarkdownBlockList(
                            blocks: identified.value.blocks,
                            path: path.markdownChild(identified.index), context: context)
                    }
                }
            }.accessibilityIdentifier("markdown.list")
        case .code(let language, let content):
            MarkdownCodeBlock(
                language: language, content: content, theme: theme,
                isStreaming: context.isStreaming, codeContent: context.codeContent,
                onAction: context.onAction
            ).equatable()
        case .table(let header, let rows, let alignments):
            MarkdownTableView(
                header: header, rows: rows, alignments: alignments, path: path,
                contentVersion: context.tableVersions[path] ?? 0, theme: theme
            ).equatable()
        case .unsupported(let kind, let source):
            if let unsupportedContent = context.unsupportedContent {
                unsupportedContent(kind, source)
            } else {
                Text(verbatim: source).font(theme.codeFont).textSelection(.enabled).contextMenu {
                    Button("Open content") { context.onAction(.unsupported(kind: kind, source: source)) }
                }
            }
        }
    }
}
#endif
