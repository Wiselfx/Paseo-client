#if canImport(UIKit)
import SwiftUI

/// The image at its fitted size; tap opens the shared full-screen viewer (G3 §4.6).
/// Pinch and drag-down dismiss live there, not inline.
struct FileImagePreview: View {
    let render: FileRenderModel?
    let relPath: String
    let fileName: String
    /// The zoom transition's namespace, shared with the viewer's other full-screen covers.
    let namespace: Namespace.ID

    @State private var showImageViewer = false

    var body: some View {
        if let render, case .image(let data, let image) = render.payload {
            Button {
                showImageViewer = true
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: "file-image:\(relPath)", in: namespace)
            .accessibilityLabel("Image \(fileName)")
            .accessibilityHint("Opens full screen")
            .fullScreenCover(isPresented: $showImageViewer) {
                MediaViewerView(
                    items: [
                        MediaViewerItem(
                            id: "file-image:\(relPath)",
                            thumbnail: image,
                            fullSource: .data(data, "file-image:\(relPath)"),
                            fileName: fileName,
                            alt: fileName,
                            filePath: nil)
                    ],
                    sourceID: "file-image:\(relPath)",
                    namespace: namespace,
                    onClose: { showImageViewer = false },
                    selection: .constant(0))
            }
        } else if render == nil {
            LoadingState()
        } else {
            EmptyState(
                systemImage: "photo", title: "Image can't be shown",
                message: "The host sent image bytes this view can't decode.")
                .padding(.horizontal, Space.xxxl)
        }
    }
}
#endif
