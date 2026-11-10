#if canImport(UIKit)
import SwiftUI
import UIKit

/// One image in assistant prose (`![alt](url)`): remote http(s) via `RichRemoteImage`
/// (AsyncImage, 320 pt cap, tap → the full-screen media viewer), anything else resolved as a
/// workspace path through the caller's `localImageLoader` (8 MiB daemon read cap) →
/// `RichLocalImage` with the same viewer. A failed/missing read falls back to the path chip.
struct ProseMarkdownImage: View {
    let image: MarkdownImage
    let localImageLoader: ((String) async -> UIImage?)?

    var body: some View {
        if isRemote {
            RichRemoteImage(urlString: image.source, alt: image.alt)
        } else {
            RichLocalImage(path: localPath, alt: image.alt, loader: localImageLoader)
        }
    }

    private var isRemote: Bool {
        let source = image.source.lowercased()
        return source.hasPrefix("http://") || source.hasPrefix("https://")
    }

    /// Absolute/`~`/relative paths pass through; `file://` is unwrapped to its path.
    private var localPath: String {
        if image.source.hasPrefix("file://"), let url = URL(string: image.source), url.isFileURL {
            return url.path
        }
        return image.source
    }
}
#endif
