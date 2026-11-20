#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// An inline prose image the reader tapped (H5 round 2). A workspace path arrives already
/// decoded; a remote source is left to the viewer, which loads it through `MediaPipeline`.
struct InlineProseImage: Identifiable {
    let markdown: MarkdownImage
    let uiImage: UIImage?

    var id: String { markdown.source }
}
#endif
