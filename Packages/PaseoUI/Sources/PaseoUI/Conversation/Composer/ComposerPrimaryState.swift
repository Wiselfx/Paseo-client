#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// What the composer's one trailing control is doing right now (D2 §1). The circle never changes
/// size; only its glyph and its fill do, so it reads as one button changing its mind.
enum ComposerPrimaryState: Equatable {
    /// Nothing typed, idle, the host has realtime voice: the waveform starts it.
    case voice
    /// Nothing typed, idle, no voice on this host: a send that cannot go anywhere.
    case unavailable
    /// Text or a finished attachment: send (a long press queues).
    case send
    /// Nothing typed, the agent is working: stop the turn.
    case stop
    /// Voice mode is live on this agent: the live level, and a tap mutes.
    case voiceActive
}
#endif
