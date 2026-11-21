#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// An HTML page with the Preview / Source control: Preview is the sandboxed web view, Source the
/// highlighted markup (UX spec §6).
///
/// The web view fills the viewer. An HTML page runs its own JavaScript in a non-persistent store
/// (E3 §3.3): without it most real pages are blank. A top-level navigation opens in Safari,
/// never inside the preview.
struct FileHTMLPreview: View {
    let render: FileRenderModel?
    let previewAsSource: Bool
    /// The file's size on the host, for the "too large to preview" message.
    let fileSize: Int
    let checkout: CheckoutStore
    /// Workspace-relative path, the base for the page's relative references.
    let relativePath: String
    let onExternalNavigation: (URL) -> Void

    @Environment(\.colorScheme) private var colorScheme

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
                SandboxedHTMLView(
                    html: WorkspaceFileWebDocument.html(
                        text, dark: colorScheme == .dark,
                        baseHref: PreviewFileScheme.baseHref(
                            workspaceId: checkout.workspaceId, filePath: relativePath)),
                    heightFloor: 0, heightCeiling: 0, onHeightChange: { _ in },
                    fillsFrame: true, allowsScripts: true,
                    onExternalNavigation: onExternalNavigation,
                    previewFiles: PreviewFileSource(
                        files: checkout.files, workspaceId: checkout.workspaceId))
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
