import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// The git state of one open workspace: branch, dirty/ahead-behind, the PR badge, the working
/// diff, and commit/push.
///
/// Owned by `HostSession` (one store per open workspace). The diff uses the legacy JSON
/// `subscribe_checkout_diff_request` pipeline because it works on every daemon; `close()`
/// releases the subscription.
///
/// IMPLEMENTATION TICKET: docs/tickets/T7-workspaces-git.md
@MainActor @Observable
public final class CheckoutStore: Identifiable {
    public nonisolated let workspaceId: String
    public nonisolated var id: String { workspaceId }
    /// The directory all git and file RPCs use.
    public nonisolated let cwd: String
    /// Files in this workspace (list/read).
    public let files: WorkspaceFiles
    public private(set) var workspace: WorkspaceDescriptor

    public enum LoadPhase: Sendable, Equatable {
        case loading
        case ready
        case failed(String)
    }

    public enum DiffPhase: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public private(set) var phase: LoadPhase = .loading
    public private(set) var status: CheckoutStatus?
    public private(set) var statusError: String?
    public private(set) var diff: CheckoutDiff?
    public private(set) var diffPhase: DiffPhase = .idle
    public private(set) var diffError: String?
    public private(set) var prStatus: CheckoutPrStatus?
    /// The forge CLI auth state from the same payload (`cli_missing`, `unauthenticated`, …).
    public private(set) var prAuthState: ForgeAuthState?
    public private(set) var prStatusError: String?
    /// Last failed commit/push/refresh/diff action.
    public private(set) var actionError: String?
    public private(set) var isCommitting = false
    public private(set) var isPushing = false
    public private(set) var isRefreshing = false

    // Capability flags, computed once per `server_info`.
    public private(set) var supportsDiffAll = false
    public private(set) var supportsOwnedSubscriptions = false
    public private(set) var supportsRefresh = false

    private let client: any DaemonClient
    private var subscriptionId: String?
    private var lastCompare: CheckoutDiffCompare?

    internal init(workspace: WorkspaceDescriptor, client: any DaemonClient) {
        self.workspace = workspace
        self.workspaceId = workspace.id
        self.cwd = workspace.cwd
        self.client = client
        self.files = WorkspaceFiles(cwd: workspace.cwd, client: client)
    }

    // MARK: Read state

    public var branch: String? { status?.currentBranch ?? workspace.gitRuntime?.currentBranch }
    public var isDirty: Bool { status?.isDirty ?? workspace.gitRuntime?.isDirty ?? false }
    public var aheadBehind: CheckoutAheadBehind? { status?.aheadBehind ?? workspace.gitRuntime?.aheadBehind }
    public var isGit: Bool { status?.isGit ?? (workspace.projectKind == .git) }
    public var isPaseoOwnedWorktree: Bool { status?.isPaseoOwnedWorktree ?? (workspace.workspaceKind == .worktree) }

    /// Diff stat from the live diff when loaded, else the directory row's summary.
    public var diffStat: WorkspaceDiffStat? {
        guard let diff else { return workspace.diffStat }
        return WorkspaceDiffStat(additions: diff.additions, deletions: diff.deletions)
    }

    public var filesChanged: Int { diff?.files.count ?? 0 }

    /// The comparison for the "changes vs base" view: `all` when the daemon supports it, else
    /// `base` against the workspace base ref. Nil when the status carries no base.
    public var baseCompare: CheckoutDiffCompare? {
        guard let base = status?.baseRefExact ?? status?.baseRef, !base.isEmpty else { return nil }
        return CheckoutDiffCompare(mode: supportsDiffAll ? .all : .base, baseRef: base)
    }

    /// The working-tree comparison, which is what the changes view opens with.
    public var workingCompare: CheckoutDiffCompare { CheckoutDiffCompare(mode: .uncommitted) }

    // MARK: Loading

    /// Loads status, the PR badge and the working diff.
    public func load() async {
        phase = .loading
        await loadStatus()
        guard phase == .ready, isGit else { return }
        if status?.hasRemote == true { await loadPrStatus() }
        await loadDiff(compare: workingCompare)
    }

    /// Re-reads the git status snapshot.
    public func loadStatus() async {
        do {
            let status = try await client.send(CheckoutStatusRequest(cwd: cwd))
            self.status = status
            statusError = status.error?.message
            phase = .ready
        } catch {
            statusError = paseoStoreErrorText(error)
            phase = .failed(paseoStoreErrorText(error))
        }
    }

    /// Re-reads the PR badge for the current branch.
    public func loadPrStatus() async {
        do {
            let payload = try await client.send(CheckoutPrStatusRequest(cwd: cwd))
            prStatus = payload.status
            prAuthState = payload.forgeAuthState
            prStatusError = payload.error?.message
        } catch {
            prStatusError = paseoStoreErrorText(error)
        }
    }

    /// Subscribes to the legacy JSON diff stream for `compare` (default: the working tree).
    /// Replaces any previous subscription.
    public func loadDiff(compare: CheckoutDiffCompare? = nil) async {
        guard isGit else {
            diff = nil
            diffPhase = .ready
            return
        }
        let compare = compare ?? workingCompare
        if compare.mode == .all, !supportsDiffAll {
            actionError = "This daemon cannot diff against the merge base."
            return
        }
        await releaseDiff()
        lastCompare = compare
        diffPhase = .loading
        do {
            let response = try await client.send(
                SubscribeCheckoutDiffRequest(cwd: cwd, compare: compare))
            subscriptionId = response.subscriptionId
            apply(response)
        } catch {
            diffError = paseoStoreErrorText(error)
            diffPhase = .failed(paseoStoreErrorText(error))
        }
    }

    /// Releases the diff subscription. Called by `HostSession.closeCheckout`.
    public func close() async {
        await releaseDiff()
        lastCompare = nil
        files.clearFile()
    }

    // MARK: Mutations

    /// Commits. `addAll` stages every change first (the default the changes view uses).
    public func commit(message: String, addAll: Bool = true) async -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            actionError = "A commit message is required."
            return false
        }
        isCommitting = true
        defer { isCommitting = false }
        do {
            let response = try await client.send(
                CheckoutCommitRequest(cwd: cwd, message: trimmed, addAll: addAll))
            guard response.success else {
                actionError = response.error?.message ?? "The commit failed."
                return false
            }
            actionError = nil
            await refresh()
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    /// Pushes the current branch to its upstream.
    public func push() async -> Bool {
        isPushing = true
        defer { isPushing = false }
        do {
            let response = try await client.send(CheckoutPushRequest(cwd: cwd))
            guard response.success else {
                actionError = response.error?.message ?? "The push failed."
                return false
            }
            actionError = nil
            await refresh()
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    /// Pokes the daemon's git/forge snapshot (when supported) and re-reads status and the diff.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if supportsRefresh {
            _ = try? await client.send(CheckoutRefreshRequest(cwd: cwd))
        }
        await loadStatus()
        if diffPhase != .idle {
            await loadDiff(compare: lastCompare)
        }
    }

    // MARK: HostSession handoff

    internal func update(serverInfo: ServerInfo?) {
        supportsDiffAll = serverInfo?.hasFeature("checkoutDiffAll") ?? false
        supportsOwnedSubscriptions = serverInfo?.hasFeature("ownedSubscriptions") ?? false
        supportsRefresh = serverInfo?.hasFeature("checkoutRefresh") ?? false
        files.update(
            supportsEntryOps: serverInfo?.hasFeature("fsEntryOps") ?? false,
            supportsEntryDuplicate: serverInfo?.hasFeature("fsEntryDuplicate") ?? false,
            supportsFileEditing: serverInfo?.hasFeature("workspaceFileEditing") ?? false)
    }

    internal func update(workspace: WorkspaceDescriptor) {
        self.workspace = workspace
    }

    /// A pushed `checkout_status_update`.
    internal func handle(_ update: CheckoutStatusUpdate) {
        guard update.status.cwd == cwd else { return }
        status = update.status
        statusError = update.status.error?.message
        if let payload = update.prStatus {
            prStatus = payload.status
            prAuthState = payload.forgeAuthState
            prStatusError = payload.error?.message
        }
        phase = .ready
    }

    /// A pushed `checkout_diff_update`.
    internal func handle(_ update: CheckoutDiff) {
        guard update.cwd == cwd else { return }
        if let expected = subscriptionId, let actual = update.subscriptionId, expected != actual {
            return
        }
        if subscriptionId == nil { subscriptionId = update.subscriptionId }
        apply(update)
    }

    /// After a reconnect the daemon forgot the subscription: reload and re-subscribe.
    internal func resubscribe() async {
        subscriptionId = nil
        await loadStatus()
        guard phase == .ready, isGit else { return }
        if let lastCompare { await loadDiff(compare: lastCompare) }
    }

    // MARK: Internals

    private func apply(_ diff: CheckoutDiff) {
        self.diff = diff
        if let error = diff.error {
            diffError = error.message
            diffPhase = .failed(error.message)
        } else {
            diffError = nil
            diffPhase = .ready
        }
    }

    private func releaseDiff() async {
        guard let subscriptionId else { return }
        self.subscriptionId = nil
        if supportsOwnedSubscriptions {
            _ = try? await client.send(SubscriptionReleaseRequest(subscriptionId: subscriptionId))
        } else {
            await client.sendFireAndForget(UnsubscribeCheckoutDiffRequest(subscriptionId: subscriptionId))
        }
    }
}

private extension DaemonClient {
    /// Sends an RPC whose protocol has no correlated response. The frame goes out; the pending
    /// waiter is dropped when the short timeout expires. Failures are ignored — a dead socket
    /// reconnects on its own.
    func sendFireAndForget<R: PaseoRequest>(_ request: R) async {
        _ = try? await send(request, timeout: .milliseconds(250))
    }
}
