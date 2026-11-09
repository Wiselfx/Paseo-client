#if canImport(UIKit)
import SwiftUI
import UIKit
import PaseoStore

/// M8b: the composer's queue affordances. `ComposerQueueStore` keeps one `MessageQueue` per
/// agent out of the view tree so the queue survives switching agents (the chat view is recreated
/// per agent). Lost on relaunch by design. `QueueSendButton` is the send control with the
/// long-press-to-queue gesture (medium haptic).

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

/// Medium-weight impact for the long-press queue gesture (the one-place `Haptics` enum has no
/// medium style).
@MainActor enum QueueHaptics {
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    static func mediumImpact() {
        medium.impactOccurred()
    }
}

/// The send control: tap sends (steers a running turn); long-press queues the draft for after
/// the turn (medium haptic). Matches the orange-circle look of the previous send button.
struct QueueSendButton: View {
    let isRunning: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onQueue: () -> Void

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 17, weight: .medium))
            .frame(width: 36, height: 36)
            .foregroundStyle(.white)
            .background(ClaudePalette.orange, in: .circle)
            .opacity(canSend ? 1 : 0.4)
            .contentShape(.rect)
            // exclusively(before:): the tap only fires when the long-press fails first, so a
            // long-press never also sends.
            .gesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in onQueue() }
                    .exclusively(before: TapGesture().onEnded { onSend() })
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isRunning ? "Send and steer" : "Send message")
            .accessibilityHint("Tap to send; long press to queue it for after the turn")
            .accessibilityAction(named: "Queue message") { onQueue() }
    }
}
#endif
