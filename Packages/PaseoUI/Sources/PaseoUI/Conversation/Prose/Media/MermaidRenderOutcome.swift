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
#endif
