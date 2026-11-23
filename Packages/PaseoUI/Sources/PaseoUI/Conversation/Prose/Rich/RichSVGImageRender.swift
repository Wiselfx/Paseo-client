#if canImport(UIKit)
import SwiftUI
import UIKit

/// SVG sources drawn as pictures (remote and local image cards, gallery tiles) through the shared
/// offscreen renderer, with the result kept in `RichSnapshotCache` by content, width and scheme.
/// A card that scrolls back, or a second card with the same drawing, reads the render instead of
/// queueing behind the serial renderer again (as inline SVG and web cards already did).
@MainActor
enum RichSVGImageRender {
    /// The cached render, or a fresh one; nil when the renderer produced nothing (or the caller
    /// was cancelled while queued).
    static func image(source: String, width: CGFloat, scale: CGFloat, dark: Bool) async -> UIImage? {
        let content = "svg-image:\(source.hashValue)"
        let key = RichSnapshotCache.key(content: content, width: width, dark: dark)
        if let cached = RichSnapshotCache.image(for: key) { return cached }
        let html = RichHTMLDocument.rawSVG(source: source, dark: dark)
        guard
            let rendered = await RichSnapshotQueue.shared.snapshot(
                html: html, width: width, scale: scale)
        else { return nil }
        RichSnapshotCache.store(rendered, for: key, content: content, dark: dark)
        return rendered
    }
}
#endif
