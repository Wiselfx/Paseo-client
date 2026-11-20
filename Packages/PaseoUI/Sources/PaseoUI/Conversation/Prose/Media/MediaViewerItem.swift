#if canImport(UIKit)
import SwiftUI
import UIKit
import VisionKit

// MARK: - MediaViewerItem (G3 §4.6)

// NOTE: RemoteImagePipeline/G3: `fullSource == nil` means the thumbnail *is* the full image
// (an SVG snapshot, a Files-panel bitmap). Nothing refetches in that case.

/// One page of the shared full-screen viewer: values only (R-2). The thumbnail is the
/// display-size pixels the card already holds, so the viewer opens instantly; the full
/// image streams in behind it (full-resolution off main, neighbours ±1 preloaded).
struct MediaViewerItem: Equatable, @unchecked Sendable {
    /// Stable per content: the URL string or daemon path. Drives pager identity.
    let id: String
    /// What the card already drew. Always present in practice; nil falls back to the fetch.
    let thumbnail: UIImage?
    /// Where the full image comes from. Nil renders the thumbnail at full size.
    let fullSource: MediaSource?
    let fileName: String
    let alt: String
    /// The daemon path, when there is one: enables Show in Files. Nil for remote content.
    let filePath: String?

    static func == (lhs: MediaViewerItem, rhs: MediaViewerItem) -> Bool {
        lhs.id == rhs.id
    }
}
#endif
