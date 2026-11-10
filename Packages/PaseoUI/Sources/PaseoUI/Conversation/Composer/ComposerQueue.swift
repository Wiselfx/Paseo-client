#if canImport(UIKit)
import SwiftUI
import UIKit
import PaseoStore

/// M8b: the composer's queue affordances. `ComposerQueueStore` keeps one `MessageQueue` per
/// agent out of the view tree so the queue survives switching agents (the chat view is recreated
/// per agent). Lost on relaunch by design. The send control itself is `ComposerPrimaryButton`.

/// One `MessageQueue` per agent, kept at app scope. Values are structs; mutations go through
/// `mutate(_:_:)` so reads/writes stay atomic.
@MainActor @Observable
final class ComposerQueueStore {
    static let shared = ComposerQueueStore()

    private var queues: [String: MessageQueue] = [:]

    private init() {}

    /// The queue for one agent. An empty value when nothing is queued.
    func queue(for agentId: String) -> MessageQueue {
        queues[agentId] ?? MessageQueue()
    }

    func mutate(_ agentId: String, _ body: (inout MessageQueue) -> Void) {
        var queue = queues[agentId] ?? MessageQueue()
        body(&queue)
        queues[agentId] = queue
    }
}
#endif
