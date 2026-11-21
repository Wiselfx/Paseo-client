#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// A stack of markdown blocks: the document itself, a quote's children or one list item's
/// blocks. Quotes and lists render their children through another `MarkdownBlockList`; being
/// named views, the two can contain each other without type erasure, so SwiftUI keeps the
/// concrete subtree to diff.
struct MarkdownBlockList: View {
    let blocks: [MarkdownBlock]
    /// The path of the block (or list item) these blocks are the children of; empty for the
    /// document. A child's own path is this one plus its position (`String.markdownChild`).
    let path: String
    let context: MarkdownRenderContext

    var body: some View {
        VStack(alignment: .leading, spacing: context.theme.blockSpacing) {
            ForEach(blocks.identifiedBlocks()) { identified in
                MarkdownBlockView(
                    block: identified.value, path: path.markdownChild(identified.index),
                    context: context)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
