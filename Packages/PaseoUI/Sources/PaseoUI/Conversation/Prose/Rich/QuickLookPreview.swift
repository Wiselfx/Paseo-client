#if canImport(UIKit)
import PDFKit
import PaseoStore
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - QuickLookPresenter (G10 C10)

// NOTE: RemoteImagePipeline/G10: `QLPreviewController` for non-text file kinds after a
// tap-gated download. Text, code and image files keep opening in the workspace file
// viewer (the existing path); Quick Look covers PDF, CSV, Office, archives and the
// audio/video fallbacks.

/// A `QLPreviewController` showing one downloaded file. UIKit-owned (R-3): SwiftUI only
/// presents and dismisses it.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(
            _ controller: QLPreviewController, previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif
