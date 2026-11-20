#if canImport(UIKit)
import OSLog
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// Serializes offscreen renders: one at a time, in the order asked for — SVG snapshots
/// and mermaid renders share the tail because they share the one offscreen view.
/// It is main-actor rather than an `actor` because its resource (`WKWebView`) is main-actor bound;
/// the queueing guarantee is the same.
@MainActor
final class RichSnapshotQueue {
    static let shared = RichSnapshotQueue()
    private var tail: Task<Void, Never>?

    func snapshot(html: String, width: CGFloat, scale: CGFloat, maxHeight: CGFloat? = nil) async -> UIImage? {
        let previous = tail
        let result: UIImage? = await withCheckedContinuation { continuation in
            let task = Task { @MainActor in
                _ = await previous?.value
                let image = await RichWebSnapshotRenderer.shared.snapshot(
                    html: html, width: width, scale: scale, maxHeight: maxHeight)
                continuation.resume(returning: image)
            }
            tail = task
        }
        return result
    }

    func mermaid(source: String, dark: Bool, slotWidth: CGFloat) async -> MermaidRenderOutcome {
        let previous = tail
        let result: MermaidRenderOutcome = await withCheckedContinuation { continuation in
            let task = Task { @MainActor in
                _ = await previous?.value
                let outcome = await RichWebSnapshotRenderer.shared.renderMermaid(
                    source: source, dark: dark, slotWidth: slotWidth)
                continuation.resume(returning: outcome)
            }
            tail = task
        }
        return result
    }
}
#endif
