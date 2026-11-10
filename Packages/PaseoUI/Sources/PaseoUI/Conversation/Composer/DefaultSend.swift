#if canImport(UIKit)
import Foundation

/// M8c: what the send button does while an agent's turn is running. Persisted as
/// `paseo.defaultSend` (`steer` | `queue` | `interrupt`) and set in Settings → General → Chat.
///
/// Idle, tap always starts a new turn. While running:
/// - `steer` (default): tap steers the turn; long-press queues for after it (M8b).
/// - `queue`: tap queues the message; long-press steers.
/// - `interrupt`: tap interrupts the turn and sends; long-press queues (opposite-of-default
///   between steer and queue; interrupt has no opposite there).
///
/// Wire values for `activeTurnBehavior` on `SendAgentMessageRequest` are `steer` / `interrupt`
/// (`ActiveTurnBehaviorSchema`, messages.ts:1292).
enum DefaultSendBehavior: String, CaseIterable {
    case steer
    case queue
    case interrupt

    static let storageKey = "paseo.defaultSend"

    var label: String {
        switch self {
        case .steer: "Steer"
        case .queue: "Queue"
        case .interrupt: "Interrupt"
        }
    }

    var topNote: String {
        switch self {
        case .steer: "Long-press queues"
        case .queue: "Long-press steers"
        case .interrupt: "Tap interrupts the turn"
        }
    }
}
#endif
