#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The full-screen viewer for an image tapped inside a sentence — the same `MediaViewerView`
/// the image cards use, so zoom, share and the chrome look identical everywhere.
struct InlineProseImageViewer: View {
    let item: InlineProseImage
    let onClose: () -> Void

    @Namespace private var zoom

    private var source: String {
        item.markdown.source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isRemote: Bool {
        let lower = source.lowercased()
        return ["http://", "https://", "data:", "blob:"].contains { lower.hasPrefix($0) }
    }

    private var fileName: String {
        let base = isRemote
            ? URL(string: source)?.lastPathComponent
            : (source as NSString).lastPathComponent
        guard let base, !base.isEmpty else { return "image" }
        return base
    }

    var body: some View {
        MediaViewerView(
            items: [
                MediaViewerItem(
                    id: "inline:\(source)",
                    thumbnail: item.uiImage,
                    fullSource: isRemote
                        ? MediaPipeline.target(for: source).map(MediaSource.remote) : nil,
                    fileName: fileName,
                    alt: item.markdown.alt.isEmpty ? fileName : item.markdown.alt,
                    filePath: isRemote ? nil : source)
            ],
            sourceID: "inline:\(source)",
            namespace: zoom,
            onClose: onClose,
            selection: .constant(0))
    }
}
#endif
