#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import Synchronization
import UIKit
import UniformTypeIdentifiers

/// The pipeline registration ticket: workspace id plus the token that owns the entry.
/// Written once, read in `deinit`. `Mutex`-guarded (the codebase's lock) so the box is
/// `Sendable` without isolation acrobatics.
final class DaemonFetchRegistration: @unchecked Sendable {
    struct Change: Sendable {
        /// The workspace whose entry is still registered and must be torn down.
        var previous: (workspaceID: String, token: UUID)?
        /// Identifies the pending registration, so an actor hop that lands after the id moved
        /// on does not overwrite the newer entry.
        var generation: Int
    }

    private struct State {
        var workspaceID: String?
        var token: UUID?
        var generation = 0
    }

    private let state = Mutex<State>(State())

    /// Starts following `workspaceID`. Nil when the id did not change (the entry, or the
    /// registration in flight, still owns it). Otherwise the previous entry is returned for
    /// the caller to unregister, and the token is cleared until `settle` records the new one.
    func begin(workspaceID: String?) -> Change? {
        state.withLock { state in
            guard state.workspaceID != workspaceID else { return nil }
            var previous: (workspaceID: String, token: UUID)?
            if let oldID = state.workspaceID, let oldToken = state.token {
                previous = (oldID, oldToken)
            }
            state.workspaceID = workspaceID
            state.token = nil
            state.generation += 1
            return Change(previous: previous, generation: state.generation)
        }
    }

    /// Records the token for `generation` when it is still the current one. False means the id
    /// moved on while the registration was in flight: the caller must unregister its token.
    func settle(token: UUID, generation: Int) -> Bool {
        state.withLock { state in
            guard state.generation == generation, state.workspaceID != nil else { return false }
            state.token = token
            return true
        }
    }

    func snapshot() -> (workspaceID: String?, token: UUID?) {
        state.withLock { ($0.workspaceID, $0.token) }
    }
}
#endif
