#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import Synchronization
import UIKit
import UniformTypeIdentifiers

// MARK: - Find state

/// The find-in-conversation session's view state. The matches themselves live in
/// `ConversationStore.search`, so they survive view churn; this is what the views draw.
@MainActor @Observable final class ChatFind {
    var isOpen = false
    var query = ""
    var index = 0
    /// The seqEnd whose row flashes after a step.
    var flash: Int?
    /// The row of the current match, resolved by the transcript against the loaded turns (the
    /// located seq can be a message that has streamed on since). Its turn is held open and drawn
    /// as the match. Nil when the match is not loaded or find is closed.
    var rowSeq: Int?
    /// Stepping scrolled the transcript during this find session: closing find then returns the reader.
    /// Survives `reset()` like `anchor`; the transcript clears it once it has acted.
    var moved = false
    /// The turn the reader was nearest when find opened (nil: they were at the end); closing restores
    /// it when stepping moved them. Survives `reset()`: the transcript reads it after the close.
    var anchor: String?
    /// The same place as a timeline position (the first row's seq of that turn): a turn's id is its first
    /// row's id, which changes when an older page prepends rows to a partial turn, a position does not.
    /// Set by the transcript when find opens; nil: the reader was at the end.
    var anchorSeq: Int?
    /// A scroll the transcript owes after a step or a search result. Cleared by the transcript.
    var jump: FindJump?
    var task: Task<Void, Never>?

    func reset() {
        task?.cancel()
        task = nil
        query = ""
        index = 0
        flash = nil
        rowSeq = nil
        jump = nil
    }
}
#endif
