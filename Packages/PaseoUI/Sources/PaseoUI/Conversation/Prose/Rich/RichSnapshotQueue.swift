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
///
/// A requester that is cancelled while its job is still queued (the card scrolled away) makes
/// the job skip its render when its turn comes. A job already rendering runs to the end.
@MainActor
final class RichSnapshotQueue {
    static let shared = RichSnapshotQueue()
    private var tail: Task<Void, Never>?

    func snapshot(html: String, width: CGFloat, scale: CGFloat, maxHeight: CGFloat? = nil) async -> UIImage? {
        let ticket = RenderTicket()
        let previous = tail
        let job = Task { @MainActor () -> UIImage? in
            _ = await previous?.value
            if ticket.isCancelled { return nil }
            return await RichWebSnapshotRenderer.shared.snapshot(
                html: html, width: width, scale: scale, maxHeight: maxHeight)
        }
        tail = Task { _ = await job.value }
        return await withTaskCancellationHandler {
            await job.value
        } onCancel: {
            ticket.cancel()
        }
    }

    func mermaid(source: String, dark: Bool, slotWidth: CGFloat) async -> MermaidRenderOutcome {
        let ticket = RenderTicket()
        let previous = tail
        let job = Task { @MainActor () -> MermaidRenderOutcome in
            _ = await previous?.value
            if ticket.isCancelled { return .unavailable }
            return await RichWebSnapshotRenderer.shared.renderMermaid(
                source: source, dark: dark, slotWidth: slotWidth)
        }
        tail = Task { _ = await job.value }
        return await withTaskCancellationHandler {
            await job.value
        } onCancel: {
            ticket.cancel()
        }
    }
}
#endif
