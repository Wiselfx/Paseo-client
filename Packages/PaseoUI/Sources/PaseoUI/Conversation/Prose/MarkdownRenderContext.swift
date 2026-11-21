#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// What every block view of one document needs: the theme, the stream flag, the host's
/// callbacks and the table versions. Handed down through the recursive block views as one value.
struct MarkdownRenderContext {
    let theme: ClaudeMarkdownTheme
    /// True while the producing turn runs: code blocks wait for their fence to close before
    /// they ask the highlighter (R9 §1).
    let isStreaming: Bool
    let onAction: (MarkdownAction) -> Void
    let imageContent: ((MarkdownImage) -> AnyView)?
    let codeContent: ((String?, String) -> AttributedString)?
    let unsupportedContent: ((MarkdownUnsupportedKind, String) -> AnyView)?
    /// The document's table content versions, by table path (`MarkdownDocumentModel.tableVersions`).
    let tableVersions: [String: Int]
}
#endif
