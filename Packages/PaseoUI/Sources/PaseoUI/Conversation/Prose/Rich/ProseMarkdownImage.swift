#if canImport(UIKit)
import SwiftUI
import UIKit

/// One image in assistant prose (`![alt](url)`).
///
/// Remote (`http`, `https`, and also `data:`/`blob:` — a markdown image is always an *image*
/// request, whatever the extension says) goes through `RichRemoteImage` and the shared
/// `RemoteImageLoader`: sized `URLCache`, a `Paseo/…` User-Agent, downsampled decode off main,
/// SVG through the snapshot renderer, and an honest failure card. Anything else is a workspace
/// path → `RichLocalImage`, which reads through `RichActions` in the environment (8 MiB daemon
/// read cap, G1 §1.2); a failed/missing read falls back to the path chip.
struct ProseMarkdownImage: View {
    let image: MarkdownImage

    var body: some View {
        if isRemote {
            RichRemoteImage(urlString: image.source, alt: image.alt)
        } else {
            RichLocalImage(path: localPath, alt: image.alt)
        }
    }

    /// A markdown image destination is never a file on this phone: `http(s)` is the normal
    /// case, `data:` is inline pixels, `blob:` is a browser handle (it gets an honest card
    /// rather than being mistaken for a workspace path and shown as a path chip).
    private var isRemote: Bool {
        let source = image.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["http://", "https://", "data:", "blob:"] where source.hasPrefix(scheme) {
            return true
        }
        return false
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
