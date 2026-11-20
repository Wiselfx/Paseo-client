#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import Synchronization
import UIKit
import UniformTypeIdentifiers

/// One pending find scroll: the located message (the daemon's `seq` and `role`), resolved to a row by
/// the transcript against the turns it holds.
struct FindJump: Equatable {
    var seq: Int
    var role: AgentTimelineSearchRequest.Role
    /// Stepped backward: the last occurrence in the message is the one to show (upstream
    /// `navigate`: `occurrence = direction === 1 ? 0 : -1`).
    var backward: Bool
}
#endif
