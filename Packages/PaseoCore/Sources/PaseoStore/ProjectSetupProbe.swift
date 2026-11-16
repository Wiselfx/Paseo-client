import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Lazily answers "does this project's `paseo.json` define worktree setup commands?" for the
/// sidebar's "Set up worktree scripts" callout, by reading the config through M2.11's
/// `ProjectConfigStore`.
///
/// The read goes through a throwaway `ProjectConfigStore` per project, never the shared
/// `HostSession.projectConfig`: the shared store carries the Project page's drafts and
/// optimistic-concurrency revision, and a background check that reloaded it would swap another
/// project's object underneath an open Project page.
///
/// One read per repoRoot per session (cached). A failed read is remembered as "unknown" so the
/// callout stays quiet instead of nagging on every appearance.
///
/// IMPLEMENTATION TICKET: docs/tickets/M2.13-dsh-sidebar.md
@MainActor @Observable
public final class ProjectSetupProbe {
    /// repoRoot → whether `worktree.setup` in paseo.json holds at least one command.
    public private(set) var hasSetupCommands: [String: Bool] = [:]
    /// repoRoots whose read failed, cached so they are not retried on every appearance.
    public private(set) var failed: Set<String> = []
    private var inFlight: Set<String> = []

    private let client: any DaemonClient

    public init(client: any DaemonClient) {
        self.client = client
    }

    /// One read per repoRoot. Safe to call from `.task` on every appear.
    public func check(repoRoot: String) async {
        guard hasSetupCommands[repoRoot] == nil,
            !failed.contains(repoRoot),
            !inFlight.contains(repoRoot)
        else { return }
        inFlight.insert(repoRoot)
        defer { inFlight.remove(repoRoot) }

        let store = ProjectConfigStore(client: client)
        await store.load(repoRoot: repoRoot)
        guard store.phase == .ready else {
            failed.insert(repoRoot)
            return
        }
        let (setup, _) = ProjectConfigEditor.worktreeCommands(store.config)
        hasSetupCommands[repoRoot] = !setup.isEmpty
    }
}
