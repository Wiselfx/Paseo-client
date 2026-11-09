#if canImport(UIKit)
import PaseoStore
import SwiftUI

enum ClaudeChatSheet: String, Identifiable {
    case controls
    case subagents
    case backgroundWork
    case turnNav
    var id: String { rawValue }
}


/// A rewind awaiting the can't-undo confirmation (M7d).
struct PendingRewind: Identifiable {
    let messageId: String
    let scope: RewindScope
    var id: String { "\(messageId)/\(scope)" }
}

/// What kind of rewind-based action is pending confirmation (M7h).
enum MessageActionKind: String {
    case edit
    case rerun
}

/// A message action awaiting the can't-undo confirmation (M7h).
struct PendingMessageAction: Identifiable {
    let messageId: String
    let text: String
    let kind: MessageActionKind
    var id: String { "\(kind.rawValue)/\(messageId)" }
}

#endif
