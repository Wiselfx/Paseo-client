import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Git actions and the commits-ahead-of-base log for one open workspace: pull/merge, PR
/// create/merge, forge auto-merge, and the commit log with per-commit file diffs.
///
/// Git actions refresh status, the diff and the PR badge after a success, the same way the
/// existing commit/push do (`checkout.refresh()` + `checkout.loadPrStatus()`). Failures land in
/// the observable `lastFailure` (typed — `.mergeConflict` is distinguishable) and `actionError`.
///
/// Vended by `GitExtrasStore.gitActions(for:)`; capabilities come from the host's
/// `server_info` through `GitExtrasStore.update(serverInfo:)`.
///
/// IMPLEMENTATION TICKET: docs/tickets/T15-git-files-ops.md
@MainActor @Observable
public final class WorkspaceGitActions: Identifiable {
    public nonisolated let workspaceId: String
    public nonisolated var id: String { workspaceId }
    public nonisolated let cwd: String

    public struct Capabilities: Sendable, Hashable {
        /// `features.commitsList`: the commits-ahead-of-base RPCs.
        public var commitsList = false
        /// `features.commitBaseClassification`: the `isOnBase` field.
        public var commitBaseClassification = false
        /// `features.checkoutForgeSetAutoMerge`: the dotted auto-merge RPC.
        public var forgeAutoMerge = false
        /// `features.checkoutGithubSetAutoMerge` (legacy twin).
        public var legacyAutoMerge = false

        public init(
            commitsList: Bool = false, commitBaseClassification: Bool = false,
            forgeAutoMerge: Bool = false, legacyAutoMerge: Bool = false
        ) {
            self.commitsList = commitsList
            self.commitBaseClassification = commitBaseClassification
            self.forgeAutoMerge = forgeAutoMerge
            self.legacyAutoMerge = legacyAutoMerge
        }
    }

    public private(set) var capabilities = Capabilities()
    public private(set) var isPulling = false
    public private(set) var isMergingFromBase = false
    public private(set) var isCreatingPullRequest = false
    public private(set) var isMergingPullRequest = false
    public private(set) var isSettingAutoMerge = false
    public private(set) var isLoadingCommits = false
    public private(set) var isLoadingCommitFileDiff = false

    /// The last failure, typed: `.mergeConflict` is distinguishable from other errors.
    public private(set) var lastFailure: CheckoutError?
    /// One-line human-readable error for banners, as elsewhere in the store layer.
    public private(set) var actionError: String?

    /// Commits between the base ref and HEAD, newest first as the daemon returns them.
    public private(set) var commits: [CheckoutCommit] = []
    /// The base ref the list was computed against, or nil when the daemon didn't say.
    public private(set) var commitsBaseRef: String?
    public private(set) var commitsError: String?
    /// The last commit file diff loaded (nil while loading, nil on error/absent/binary).
    public private(set) var commitFileDiff: ParsedDiffFile?
    public private(set) var commitFileDiffError: String?

    /// Plain capability flags for views; read once per host.
    public var supportsCommitsList: Bool { capabilities.commitsList }
    public var supportsCommitBaseClassification: Bool { capabilities.commitBaseClassification }
    /// Either auto-merge twin is present (dotted preferred at call time).
    public var supportsAutoMerge: Bool { capabilities.forgeAutoMerge || capabilities.legacyAutoMerge }

    private let checkout: CheckoutStore
    private let client: any DaemonClient

    internal init(workspaceId: String, cwd: String, checkout: CheckoutStore, client: any DaemonClient) {
        self.workspaceId = workspaceId
        self.cwd = cwd
        self.checkout = checkout
        self.client = client
    }

    /// Feeds `server_info` in; called by `GitExtrasStore.update(serverInfo:)`.
    internal func update(capabilities: Capabilities) {
        self.capabilities = capabilities
    }

    // MARK: Git mutations

    /// Pulls from the upstream. Typed failure on the way out; status refreshed on success.
    public func pull() async -> Bool {
        guard !isPulling else { return false }
        isPulling = true
        defer { isPulling = false }
        do {
            let response = try await client.send(CheckoutPullRequest(cwd: cwd))
            guard response.success else {
                recordFailure(response.error, fallback: "The pull failed.")
                return false
            }
            clearFailure()
            await refreshAfterMutation()
            return true
        } catch {
            recordFailure(nil, fallback: errorText(error))
            return false
        }
    }

    /// Merges the base branch into the current branch (`checkout_merge_from_base_request`).
    public func mergeFromBase() async -> Bool {
        guard !isMergingFromBase else { return false }
        isMergingFromBase = true
        defer { isMergingFromBase = false }
        do {
            let response = try await client.send(CheckoutMergeFromBaseRequest(cwd: cwd))
            guard response.success else {
                recordFailure(response.error, fallback: "The merge failed.")
                return false
            }
            clearFailure()
            await refreshAfterMutation()
            return true
        } catch {
            recordFailure(nil, fallback: errorText(error))
            return false
        }
    }

    /// Opens a PR for the current branch. Returns `(url, number)` on success.
    /// The daemon pushes the branch and opens the PR in one shot.
    public func createPullRequest(
        title: String? = nil, body: String? = nil, baseRef: String? = nil
    ) async -> (url: String, number: Int?)? {
        guard !isCreatingPullRequest else { return nil }
        isCreatingPullRequest = true
        defer { isCreatingPullRequest = false }
        func trimmed(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        do {
            let response = try await client.send(
                CheckoutPrCreateRequest(
                    cwd: cwd, title: trimmed(title), body: trimmed(body), baseRef: trimmed(baseRef)))
            if let error = response.error {
                recordFailure(error, fallback: "The pull request could not be opened.")
                return nil
            }
            guard let url = response.url else {
                recordFailure(nil, fallback: "The daemon did not return a pull request URL.")
                return nil
            }
            clearFailure()
            await refreshAfterMutation()
            return (url: url, number: response.number)
        } catch {
            recordFailure(nil, fallback: errorText(error))
            return nil
        }
    }

    /// Merges the open PR for the current branch.
    public func mergePullRequest(method: PullRequestMergeMethod) async -> Bool {
        guard !isMergingPullRequest else { return false }
        isMergingPullRequest = true
        defer { isMergingPullRequest = false }
        do {
            let response = try await client.send(
                CheckoutPrMergeRequest(cwd: cwd, mergeMethod: method))
            guard response.success else {
                recordFailure(response.error, fallback: "The pull request could not be merged.")
                return false
            }
            clearFailure()
            await refreshAfterMutation()
            return true
        } catch {
            recordFailure(nil, fallback: errorText(error))
            return false
        }
    }

    // MARK: Auto-merge

    /// Enables or disables forge-side auto-merge on the open PR.
    ///
    /// When disabling, `mergeMethod` is never sent — older daemons expect the field absent.
    /// The dotted `checkout.forge.set_auto_merge.request` is used when the daemon advertises
    /// `features.checkoutForgeSetAutoMerge`, falling back to the legacy `checkout.github.set_auto_merge.request`
    /// twin (COMPAT(githubAutoMergeRpc), remove after 2027-01-17).
    public func setAutoMerge(enabled: Bool, method: PullRequestMergeMethod? = nil) async -> Bool {
        guard !isSettingAutoMerge else { return false }
        guard capabilities.forgeAutoMerge || capabilities.legacyAutoMerge else {
            actionError = "This daemon cannot set PR auto-merge."
            return false
        }
        isSettingAutoMerge = true
        defer { isSettingAutoMerge = false }
        let wireMethod: PullRequestMergeMethod? = enabled ? method : nil
        do {
            let response: CheckoutSetAutoMergeResponse
            if capabilities.forgeAutoMerge {
                response = try await client.send(
                    CheckoutForgeSetAutoMergeRequest(cwd: cwd, enabled: enabled, mergeMethod: wireMethod))
            } else {
                response = try await client.send(
                    CheckoutGithubSetAutoMergeRequest(cwd: cwd, enabled: enabled, mergeMethod: wireMethod))
            }
            guard response.success else {
                recordFailure(response.error, fallback: "Setting auto-merge failed.")
                return false
            }
            clearFailure()
            await checkout.loadPrStatus()
            return true
        } catch {
            recordFailure(nil, fallback: errorText(error))
            return false
        }
    }

    // MARK: Commits ahead of base

    /// Loads the commits between the base ref and HEAD. Requires `features.commitsList`.
    public func loadCommits() async {
        guard capabilities.commitsList else {
            commitsError = "This daemon cannot list commits."
            return
        }
        guard !isLoadingCommits else { return }
        isLoadingCommits = true
        defer { isLoadingCommits = false }
        do {
            let response = try await client.send(CheckoutCommitsListRequest(cwd: cwd))
            if let error = response.error {
                commits = []
                commitsBaseRef = nil
                commitsError = error.message
                return
            }
            commits = response.commits
            commitsBaseRef = response.baseRef
            commitsError = nil
        } catch {
            commits = []
            commitsBaseRef = nil
            commitsError = errorText(error)
        }
    }

    /// Loads one file's diff inside a commit. Requires `features.commitsList`.
    /// The null diff (absent or binary file) comes back as `nil` with no error set.
    public func loadCommitFileDiff(sha: String, path: String) async -> ParsedDiffFile? {
        guard capabilities.commitsList else {
            commitFileDiffError = "This daemon cannot read commit file diffs."
            return nil
        }
        guard !isLoadingCommitFileDiff else { return commitFileDiff }
        isLoadingCommitFileDiff = true
        defer { isLoadingCommitFileDiff = false }
        do {
            let response = try await client.send(
                CheckoutCommitFileDiffRequest(cwd: cwd, sha: sha, path: path))
            if let error = response.error {
                commitFileDiff = nil
                commitFileDiffError = error.message
                return nil
            }
            commitFileDiff = response.file
            commitFileDiffError = nil
            return response.file
        } catch {
            commitFileDiff = nil
            commitFileDiffError = errorText(error)
            return nil
        }
    }

    // MARK: Internals

    private func refreshAfterMutation() async {
        await checkout.refresh()
        await checkout.loadPrStatus()
    }

    private func recordFailure(_ error: CheckoutError?, fallback: String) {
        lastFailure = error
        actionError = error?.message ?? fallback
    }

    private func clearFailure() {
        lastFailure = nil
        actionError = nil
    }
}

private func errorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}
