#if canImport(UIKit)
import SwiftUI

/// An SVG file: decoded from the daemon's base64 image bytes and rendered by the sandboxed
/// web view, fitted to the width. No scripts can run (UX spec §6).
struct FileSVGPreview: View {
    let render: FileRenderModel?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let render, case .svg(let source) = render.payload {
            SandboxedHTMLView(
                html: WorkspaceFileWebDocument.svg(source, dark: colorScheme == .dark),
                heightFloor: 0, heightCeiling: 0, onHeightChange: { _ in },
                fillsFrame: true, allowsScripts: false,
                onExternalNavigation: nil, previewFiles: nil)
        } else if render == nil {
            LoadingState()
        } else {
            EmptyState(
                systemImage: "photo", title: "Image can't be shown",
                message: "The host sent SVG bytes this view can't decode.")
                .padding(.horizontal, Space.xxxl)
        }
    }
}
#endif
