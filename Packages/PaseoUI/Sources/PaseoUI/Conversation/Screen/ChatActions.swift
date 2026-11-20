#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import Synchronization
import UIKit
import UniformTypeIdentifiers

// MARK: - Actions

/// The transcript's verbs, in the environment so a turn row can call them without taking a dozen
/// closures in its init (R6 §4). One instance per open agent, created by `ChatController`.
///
/// It is `@Observable` only so a flag can change without rebuilding the rows; the closures
/// themselves are stable for the controller's life.
@MainActor @Observable final class ChatActions {
    /// Opens the workspace file viewer at a path (prose links, Read/Edit/Write rows).
    var openFile: (String) -> Void = { _ in }
    /// Markdown interactions that are not links: copy code, and anything else the prose reports.
    var markdown: (MarkdownAction) -> Void = { _ in }
    /// Asks for the can't-undo confirmation of a rewind (scope + message id).
    var rewind: (RewindScope, String) -> Void = { _, _ in }
    /// Fork at the row above `row` (nil for the in-flight fork of the whole timeline).
    var fork: ((ClaudeForkTarget, TimelineRow) async -> Void)?
    /// The running turn's fork: no boundary.
    var forkInFlight: ((ClaudeForkTarget) async -> Void)?
    /// Reads a workspace image for prose. Decoded off main and cached by (workspace, path).
    var loadImage: (String) async -> UIImage? = { _ in nil }
    /// An agent's live title by id, for "Sent by" (upstream `user-message/index.tsx:95`).
    var agentTitle: (String) -> String? = { _ in nil }
    /// Opens a diff whole, in the chat's diff sheet (an inline diff shows its first lines).
    var showDiff: (ClaudeDiffDocument) -> Void = { _ in }

    /// What this agent and host can actually do with a turn, as one value the rows compare
    /// (R-2). Recomputed by `ChatController` when the agent snapshot, the host features or the
    /// workspace capabilities change — never in a row body (R-1).
    var availability = TurnActionAvailability()

    private let store: ConversationStore

    init(store: ConversationStore) {
        self.store = store
    }
}
#endif
