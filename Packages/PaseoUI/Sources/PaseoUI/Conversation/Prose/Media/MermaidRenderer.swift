#if canImport(UIKit)
import Foundation
import UIKit

// MARK: - MermaidRenderer (G4 C9, D2)

// NOTE: RemoteImagePipeline/G4: the render itself moved into `RichWebSnapshotRenderer`
// (one offscreen view, one window, one serial queue for SVG snapshots and mermaid
// renders). This file keeps the outcome type and the SVG cache for the live view.


/// What one offscreen mermaid render produced.
enum MermaidRenderOutcome: Sendable {
    /// The rendered SVG (for the live artifact view), the snapshot at screen scale, and
    /// the natural aspect ratio (for the reserved box).
    case diagram(image: UIImage, aspectRatio: CGFloat, svg: String)
    /// Mermaid refused the source: the card shows the source as code plus this message
    /// (upstream shows the source on syntax errors too).
    case error(message: String)
    /// No scene, no bundle, or WebKit refused: the card shows one honest failure line.
    case unavailable
}

/// The rendered SVG per diagram, keyed by (source, scheme): the snapshot cache holds
/// pixels, this holds the vector for the artifact page's live view. Bounded and
/// in-memory like every transcript cache.
enum MermaidSVGCache {
    nonisolated(unsafe) private static let table: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 32
        return cache
    }()

    static func string(for key: String) -> String? {
        table.object(forKey: key as NSString).map { String($0) }
    }

    static func store(_ svg: String, for key: String) {
        table.setObject(svg as NSString, forKey: key as NSString)
    }
}
#endif
