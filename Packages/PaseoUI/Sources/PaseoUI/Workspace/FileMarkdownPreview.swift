#if canImport(UIKit)
import SwiftUI

/// A Markdown file: the rendered document, or its source when the toggle says so.
struct FileMarkdownPreview: View {
    let render: FileRenderModel?
    let previewAsSource: Bool
    /// The file's size on the host, for the "too large to preview" message.
    let fileSize: Int

    @Environment(\.openURL) private var openURL

    var body: some View {
        if render == nil {
            LoadingState()
        } else if let text = render?.text {
            if previewAsSource {
                FileSourceCode(text: text, render: render)
            } else if text.utf16.count > 200_000 {
                EmptyState(
                    systemImage: "doc.text", title: "File too large to preview",
                    message: "\(WorkspaceFileFormat.bytes(fileSize)) · Switch to Source.")
                    .padding(.horizontal, Space.xxxl)
            } else {
                ScrollView {
                    ClaudeMarkdownView(
                        text, theme: ClaudeProse.theme(bodySize: 14)
                    ) { action in
                        if case .openLink(let url) = action { openURL(url) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.lg)
                }
            }
        } else {
            EmptyState(
                systemImage: "doc.text", title: "No content",
                message: "The host returned no text for this file.")
                .padding(.horizontal, Space.xxxl)
        }
    }
}
#endif
