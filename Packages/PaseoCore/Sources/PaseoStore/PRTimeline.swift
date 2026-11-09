import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// The pull-request timeline for the PR pane: reviews and comments (plus unknown kinds kept
/// verbatim), with the typed `not_found|forbidden|unknown` error as observable state.
///
/// Vended by `GitExtrasStore.timeline(for:)`; capabilities are read by the view from the PR
/// status itself — this store performs no gate of its own.
///
/// IMPLEMENTATION TICKET: docs/tickets/M3i-pr-pane.md
@MainActor @Observable
public final class PullRequestTimelineStore: Identifiable {
    public nonisolated let workspaceId: String
    public nonisolated var id: String { workspaceId }
    public nonisolated let cwd: String

    public private(set) var items: [PullRequestTimelineItem] = []
    /// The typed error, when the daemon refused or the forge doesn't serve timelines.
    public private(set) var error: PullRequestTimelineError?
    public private(set) var isLoading = false
    public private(set) var truncated = false

    private let client: any DaemonClient

    internal init(workspaceId: String, cwd: String, client: any DaemonClient) {
        self.workspaceId = workspaceId
        self.cwd = cwd
        self.client = client
    }

    /// Refetches the timeline for the PR the caller already knows (from the PR status).
    /// No PR facts means no request — a calm typed error instead.
    public func load(prNumber: Int, repoOwner: String?, repoName: String?) async {
        let owner = repoOwner?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = repoName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !owner.isEmpty, !name.isEmpty, prNumber > 0 else {
            error = PullRequestTimelineError(
                kind: .unknown, message: "This forge doesn't expose the timeline for this PR.")
            items = []
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.send(
                PullRequestTimelineRequest(
                    cwd: cwd, prNumber: prNumber, repoOwner: owner, repoName: name))
            items = response.items
            truncated = response.truncated
            error = response.error
        } catch let caught {
            items = []
            error = PullRequestTimelineError(kind: .unknown, message: errorText(caught))
        }
    }

    /// Resets items and error (e.g. after the PR closed or the workspace changed).
    public func reset() {
        items = []
        error = nil
        truncated = false
    }
}

private func errorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}
