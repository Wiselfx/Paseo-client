import Foundation

/// A client-side queue of messages waiting for the running turn to end. One instance per agent.
///
/// While a turn runs, a plain send still steers (`activeTurnBehavior: "steer"`); the queue is the
/// alternative for "hold this until the turn is done". Each idle edge sends the head of the
/// queue; the caller must call `finishSending()` when that send settles so a later idle edge
/// can flush the next message.
///
/// Pure logic, no I/O: persistence (the queue is lost on relaunch) is the caller's choice.
public struct MessageQueue: Sendable, Equatable {
    public struct QueuedMessage: Sendable, Equatable, Identifiable {
        public let id: UUID
        public var text: String

        public init(text: String, id: UUID = UUID()) {
            self.id = id
            self.text = text
        }
    }

    public private(set) var messages: [QueuedMessage] = []
    /// True while a dequeued message's send is in flight. Guards the idle-edge flush so an
    /// `activeTurnId` flicker (idle → running → idle in quick succession) can't double-send.
    public private(set) var isSending = false

    public init() {}

    public var isEmpty: Bool { messages.isEmpty }
    public var count: Int { messages.count }
    /// The head of the queue, without removing it. Nil while a send is in flight.
    public var head: QueuedMessage? { messages.first }

    /// Adds a message. Empty or whitespace-only text is rejected; the trimmed text is stored.
    @discardableResult
    public mutating func enqueue(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        messages.append(QueuedMessage(text: trimmed))
        return true
    }

    /// Replaces a queued message's text with the trimmed value. Returns false when the id is
    /// unknown or the text is empty.
    @discardableResult
    public mutating func edit(_ id: QueuedMessage.ID, to text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return false }
        messages[index].text = trimmed
        return true
    }

    /// Removes a message.
    public mutating func remove(_ id: QueuedMessage.ID) {
        messages.removeAll { $0.id == id }
    }

    /// Removes and returns a message's text: "Edit" (back into the draft) and "Send now".
    /// Works for any position and regardless of `isSending`. Nil when the id is unknown.
    public mutating func take(_ id: QueuedMessage.ID) -> String? {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return nil }
        return messages.remove(at: index).text
    }

    /// Idle-edge dequeue: pops the head only when idle and no send is in flight, and marks the
    /// send busy. Two nil edges in a row therefore yield exactly one message.
    public mutating func dequeueNext(isIdle: Bool) -> QueuedMessage? {
        guard isIdle, !isSending, let next = messages.first else { return nil }
        messages.removeFirst()
        isSending = true
        return next
    }

    /// Called by the caller when the send of a dequeued message settles (accepted or failed).
    public mutating func finishSending() {
        isSending = false
    }
}
