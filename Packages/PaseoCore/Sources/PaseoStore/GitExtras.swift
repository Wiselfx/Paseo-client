import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// The git extras for open workspaces: the modern binary diff pipeline, discard, branch
/// suggestions/switching, the PR badge and live file subscriptions.
///
/// `HostSession` owns one of these per host. It hands out one `WorkspaceGitExtras` per checkout and
/// routes binary frames and `fs.file.update` events here. The modern pipeline is used when the
/// daemon advertises `features.diffSubscription`; otherwise the helper falls back to
/// `CheckoutStore`'s legacy JSON diff stream.
///
/// IMPLEMENTATION TICKET: docs/tickets/PHASE3-BACKEND.md (T11)
@MainActor @Observable
public final class GitExtrasStore {
    public private(set) var supportsModernDiff = false
    public private(set) var supportsDiscardChanges = false
    public private(set) var supportsFileWatching = false
    public private(set) var supportsOwnedSubscriptions = false
    public private(set) var supportsCommitsList = false
    public private(set) var supportsCommitBaseClassification = false
    public private(set) var supportsForgeAutoMerge = false
    public private(set) var supportsLegacyAutoMerge = false

    private let client: any DaemonClient
    private var workspaces: [String: WorkspaceGitExtras] = [:]
    private var gitActions: [String: WorkspaceGitActions] = [:]
    private var timelines: [String: PullRequestTimelineStore] = [:]

    public init(client: any DaemonClient) {
        self.client = client
    }

    /// The git actions for one open workspace. Same instance for the same id while it is open.
    public func gitActions(for checkout: CheckoutStore) -> WorkspaceGitActions {
        if let existing = gitActions[checkout.workspaceId] { return existing }
        let actions = WorkspaceGitActions(
            workspaceId: checkout.workspaceId, cwd: checkout.cwd, checkout: checkout, client: client)
        actions.update(capabilities: gitActionCapabilities)
        gitActions[checkout.workspaceId] = actions
        return actions
    }

    /// The PR timeline for one open workspace. Same instance for the same id while it is open.
    public func timeline(for checkout: CheckoutStore) -> PullRequestTimelineStore {
        if let existing = timelines[checkout.workspaceId] { return existing }
        let timeline = PullRequestTimelineStore(
            workspaceId: checkout.workspaceId, cwd: checkout.cwd, client: client)
        timelines[checkout.workspaceId] = timeline
        return timeline
    }

    /// The extras for one open workspace. Same instance for the same id while it is open.
    public func workspace(for checkout: CheckoutStore) -> WorkspaceGitExtras {
        if let existing = workspaces[checkout.workspaceId] { return existing }
        let extras = WorkspaceGitExtras(
            workspaceId: checkout.workspaceId, cwd: checkout.cwd, checkout: checkout, client: client)
        extras.update(capabilities: capabilities)
        workspaces[checkout.workspaceId] = extras
        return extras
    }

    /// A pushed binary frame. Diff frames live in `0x40...0x4f`; terminal frames are routed by
    /// `TerminalsStore` and fall outside that range.
    internal func handle(binaryFrame: Data) {
        guard let first = binaryFrame.first, (0x40...0x4f).contains(first) else { return }
        guard let frame = DiffFrameCodec.decode(binaryFrame) else { return }
        for extras in workspaces.values {
            extras.handle(frame: frame)
        }
    }

    /// A newer daemon message type this store owns (`fs.file.update`).
    internal func handle(messageType: String, raw: Data) {
        guard messageType == FileUpdate.wireMessageType else { return }
        guard
            let update = try? JSONDecoder().decode(
                SessionPayloadEnvelope<FileUpdate>.self, from: raw
            ).payload
        else { return }
        for extras in workspaces.values {
            extras.handle(update: update)
        }
    }

    internal func update(serverInfo: ServerInfo?) {
        supportsModernDiff = serverInfo?.hasFeature("diffSubscription") ?? false
        supportsDiscardChanges = serverInfo?.hasFeature("checkoutDiscardChanges") ?? false
        supportsFileWatching = serverInfo?.hasFeature("workspaceFileEditing") ?? false
        supportsOwnedSubscriptions = serverInfo?.hasFeature("ownedSubscriptions") ?? false
        supportsCommitsList = serverInfo?.hasFeature("commitsList") ?? false
        supportsCommitBaseClassification = serverInfo?.hasFeature("commitBaseClassification") ?? false
        supportsForgeAutoMerge = serverInfo?.hasFeature("checkoutForgeSetAutoMerge") ?? false
        supportsLegacyAutoMerge = serverInfo?.hasFeature("checkoutGithubSetAutoMerge") ?? false
        let capabilities = capabilities
        for extras in workspaces.values {
            extras.update(capabilities: capabilities)
        }
        let actionCapabilities = gitActionCapabilities
        for actions in gitActions.values {
            actions.update(capabilities: actionCapabilities)
        }
    }

    /// After a reconnect the daemon forgot every subscription: re-subscribe what is open.
    internal func resubscribe() async {
        let open = Array(workspaces.values)
        for extras in open {
            await extras.resubscribe()
        }
    }

    /// Releases the extras for one workspace. Called by `HostSession.closeCheckout`.
    internal func close(_ workspaceId: String) async {
        gitActions.removeValue(forKey: workspaceId)
        timelines.removeValue(forKey: workspaceId)
        guard let extras = workspaces.removeValue(forKey: workspaceId) else { return }
        await extras.close()
    }

    private var capabilities: WorkspaceGitExtras.Capabilities {
        WorkspaceGitExtras.Capabilities(
            supportsModernDiff: supportsModernDiff,
            supportsDiscardChanges: supportsDiscardChanges,
            supportsFileWatching: supportsFileWatching,
            supportsOwnedSubscriptions: supportsOwnedSubscriptions)
    }

    private var gitActionCapabilities: WorkspaceGitActions.Capabilities {
        WorkspaceGitActions.Capabilities(
            commitsList: supportsCommitsList,
            commitBaseClassification: supportsCommitBaseClassification,
            forgeAutoMerge: supportsForgeAutoMerge,
            legacyAutoMerge: supportsLegacyAutoMerge)
    }
}

/// One workspace's git extras. Created and retained by `GitExtrasStore`; views read its observable
/// state and call its async methods.
///
/// IMPLEMENTATION TICKET: docs/tickets/PHASE3-BACKEND.md (T11)
@MainActor @Observable
public final class WorkspaceGitExtras: Identifiable {
    public nonisolated let workspaceId: String
    public nonisolated var id: String { workspaceId }
    public nonisolated let cwd: String

    public struct Capabilities: Sendable, Hashable {
        public var supportsModernDiff = false
        public var supportsDiscardChanges = false
        public var supportsFileWatching = false
        public var supportsOwnedSubscriptions = false

        public init(
            supportsModernDiff: Bool = false, supportsDiscardChanges: Bool = false,
            supportsFileWatching: Bool = false, supportsOwnedSubscriptions: Bool = false
        ) {
            self.supportsModernDiff = supportsModernDiff
            self.supportsDiscardChanges = supportsDiscardChanges
            self.supportsFileWatching = supportsFileWatching
            self.supportsOwnedSubscriptions = supportsOwnedSubscriptions
        }
    }

    public enum DiffPhase: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public enum FilePhase: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public private(set) var capabilities = Capabilities()
    public private(set) var diffPhase: DiffPhase = .idle
    public private(set) var snapshot: DiffSnapshot?
    public private(set) var pendingEntries: [DiffEntry] = []
    public private(set) var diffError: String?
    public private(set) var branchSuggestions: [BranchSuggestion] = []
    public private(set) var branchError: String?
    public private(set) var prStatus: CheckoutPrStatus?
    public private(set) var prAuthState: ForgeAuthState?
    public private(set) var prError: String?
    public private(set) var watchedFile: FileVersion?
    public private(set) var filePhase: FilePhase = .idle
    public private(set) var fileError: String?
    public private(set) var actionError: String?
    public private(set) var isDiscarding = false
    public private(set) var isSwitchingBranch = false
    public private(set) var isLoadingBranchSuggestions = false

    /// The pipeline the last `loadDiff` used. False until a diff has been loaded.
    public private(set) var isUsingLegacyPipeline = false

    private let checkout: CheckoutStore
    private let client: any DaemonClient

    private var lastCompare: DiffCompare?
    private var assembler = DiffStreamAssembler()
    private var diffSubscriptionId: String?
    private var diffSlot: UInt8?
    private var fileSubscriptionId: String?
    private var watchedPath: String?

    internal init(
        workspaceId: String, cwd: String, checkout: CheckoutStore, client: any DaemonClient
    ) {
        self.workspaceId = workspaceId
        self.cwd = cwd
        self.checkout = checkout
        self.client = client
    }

    // MARK: Read state

    public var files: [ParsedDiffFile] { snapshot?.files ?? [] }
    public var filesChanged: Int { snapshot?.files.count ?? 0 }
    public var additions: Int { snapshot?.additions ?? 0 }
    public var deletions: Int { snapshot?.deletions ?? 0 }
    public var diffTooLarge: Bool { snapshot?.diffTooLarge ?? false }
    /// The branch the helper switched to, before the daemon's status cache catches up.
    public private(set) var switchedBranch: String?
    public var currentBranch: String? { switchedBranch ?? checkout.branch }

    /// The PR badge derived from the last `checkout_pr_status_request`.
    public var prBadge: PullRequestBadge? {
        guard let prStatus else { return nil }
        return PullRequestBadge(status: prStatus)
    }

    // MARK: Diff

    /// Loads a comparison through the modern binary pipeline when the daemon supports it, and
    /// through `CheckoutStore.loadDiff` otherwise.
    public func loadDiff(compare: DiffCompare) async {
        lastCompare = compare
        guard capabilities.supportsModernDiff else {
            await loadLegacyDiff(compare)
            return
        }
        await releaseDiff()
        isUsingLegacyPipeline = false
        snapshot = nil
        pendingEntries = []
        diffError = nil
        diffPhase = .loading
        do {
            let payload = try await client.send(DiffSubscribeRequest(compare: compare))
            if let error = payload.error {
                diffError = error.message
                diffPhase = .failed(error.message)
                return
            }
            guard let slot = payload.slotByte else {
                let message = "The daemon sent an invalid diff slot."
                diffError = message
                diffPhase = .failed(message)
                return
            }
            diffSubscriptionId = payload.subscriptionId
            diffSlot = slot
            assembler = DiffStreamAssembler()
        } catch {
            let message = gitExtrasErrorText(error)
            diffError = message
            diffPhase = .failed(message)
        }
    }

    /// The uncommitted working tree.
    public func loadWorkingDiff() async {
        await loadDiff(compare: .working(cwd: cwd))
    }

    /// The branch's changes against `baseRef`, through the merge base.
    public func loadBaseDiff(baseRef: String) async {
        await loadDiff(compare: .againstBase(cwd: cwd, baseRef: baseRef))
    }

    // MARK: Mutations

    /// Discards working-tree changes for repo-relative `paths`. Irreversible; the caller confirms.
    public func discard(paths: [String]) async -> Bool {
        let cleaned = paths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            actionError = "Choose at least one file to discard."
            return false
        }
        guard capabilities.supportsDiscardChanges else {
            actionError = "This daemon cannot discard changes."
            return false
        }
        isDiscarding = true
        defer { isDiscarding = false }
        do {
            let response = try await client.send(
                CheckoutDiscardChangesRequest(cwd: cwd, paths: cleaned))
            guard response.success else {
                actionError = response.error?.message ?? "The discard failed."
                return false
            }
            actionError = nil
            await checkout.loadStatus()
            await reloadDiff()
            return true
        } catch {
            actionError = gitExtrasErrorText(error)
            return false
        }
    }

    /// Loads branch names matching `query`.
    public func loadBranchSuggestions(query: String? = nil, limit: Int? = nil) async {
        isLoadingBranchSuggestions = true
        defer { isLoadingBranchSuggestions = false }
        let normalized = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response = try await client.send(
                BranchSuggestionsRequest(
                    cwd: cwd, query: normalized?.isEmpty == false ? normalized : nil,
                    limit: limit))
            branchSuggestions = response.suggestions
            branchError = response.error
        } catch {
            branchSuggestions = []
            branchError = gitExtrasErrorText(error)
        }
    }

    /// Switches the working tree to `branch`. Refreshes status and the current diff on success.
    public func switchBranch(_ branch: String) async -> Bool {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            actionError = "A branch name is required."
            return false
        }
        isSwitchingBranch = true
        defer { isSwitchingBranch = false }
        do {
            let response = try await client.send(
                CheckoutSwitchBranchRequest(cwd: cwd, branch: trimmed))
            guard response.success else {
                actionError = response.error?.message ?? "The branch switch failed."
                return false
            }
            actionError = nil
            await checkout.loadStatus()
            switchedBranch = response.branch
            await reloadDiff()
            return true
        } catch {
            actionError = gitExtrasErrorText(error)
            return false
        }
    }

    /// Re-reads the PR badge, keeping the auth state the plain checkout store discards.
    public func loadPrStatus() async {
        do {
            let payload = try await client.send(CheckoutPrStatusRequest(cwd: cwd))
            prStatus = payload.status
            prAuthState = payload.forgeAuthState
            prError = payload.error?.message
        } catch {
            prStatus = nil
            prAuthState = nil
            prError = gitExtrasErrorText(error)
        }
    }

    // MARK: Live files

    /// Watches one file. Without `features.workspaceFileEditing` this falls back to a one-shot
    /// `file_explorer_request` read through `checkout.files`.
    public func watchFile(_ path: String) async {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fileError = "A file path is required."
            return
        }
        await releaseFileWatch()
        watchedPath = trimmed
        guard capabilities.supportsFileWatching else {
            await checkout.files.read(trimmed)
            if let file = checkout.files.file {
                watchedFile = FileVersion(
                    status: .ready, cwd: cwd, path: file.path, size: file.size,
                    modifiedAt: file.modifiedAt, revision: file.revision, kind: file.kind,
                    mimeType: file.mimeType)
                fileError = nil
                filePhase = .ready
            } else {
                let message = checkout.files.error ?? "This daemon cannot watch files."
                fileError = message
                filePhase = .failed(message)
            }
            return
        }

        filePhase = .loading
        do {
            let payload = try await client.send(
                FileSubscribeRequest(cwd: cwd, path: trimmed))
            fileSubscriptionId = payload.subscriptionId
            apply(version: payload.initial)
        } catch {
            let message = gitExtrasErrorText(error)
            fileError = message
            filePhase = .failed(message)
        }
    }

    /// Stops watching the current file. Safe when nothing is watched.
    public func stopWatchingFile() async {
        await releaseFileWatch()
        watchedPath = nil
        watchedFile = nil
        fileError = nil
        filePhase = .idle
    }

    // MARK: HostSession handoff

    internal func update(capabilities: Capabilities) {
        self.capabilities = capabilities
    }

    internal func handle(frame: DiffFrame) {
        guard let diffSlot, frame.slot == diffSlot else { return }
        guard let event = assembler.receive(frame) else { return }
        switch event {
        case .loading(let entries):
            pendingEntries = entries
            diffPhase = .loading
        case .ready(let snapshot):
            self.snapshot = snapshot
            pendingEntries = []
            diffError = nil
            diffPhase = .ready
        case .failed(let error):
            diffError = error.message
            diffPhase = .failed(error.message)
        }
    }

    internal func handle(update: FileUpdate) {
        guard let fileSubscriptionId, update.subscriptionId == fileSubscriptionId else { return }
        apply(version: update.version)
    }

    internal func resubscribe() async {
        // The legacy stream is owned by CheckoutStore, which HostSession already resubscribed.
        if capabilities.supportsModernDiff, let lastCompare {
            await loadDiff(compare: lastCompare)
        }
        if let watchedPath {
            await watchFile(watchedPath)
        }
    }

    internal func close() async {
        await releaseDiff()
        await releaseFileWatch()
        lastCompare = nil
        watchedPath = nil
        watchedFile = nil
        snapshot = nil
        pendingEntries = []
        diffPhase = .idle
        filePhase = .idle
        fileError = nil
        isUsingLegacyPipeline = false
        switchedBranch = nil
        diffSlot = nil
    }

    // MARK: Internals

    private func reloadDiff() async {
        guard let lastCompare else { return }
        await loadDiff(compare: lastCompare)
    }

    private func loadLegacyDiff(_ compare: DiffCompare) async {
        guard let legacy = compare.legacyCompare else {
            let message = "This daemon cannot run this comparison."
            diffError = message
            diffPhase = .failed(message)
            return
        }
        isUsingLegacyPipeline = true
        diffError = nil
        diffPhase = .loading
        await checkout.loadDiff(compare: legacy)
        pendingEntries = []
        if let diff = checkout.diff {
            applyLegacy(diff)
        } else {
            snapshot = nil
            let message = checkout.diffError ?? "The daemon returned no diff."
            diffError = message
            diffPhase = .failed(message)
        }
    }

    private func applyLegacy(_ diff: CheckoutDiff) {
        snapshot = DiffSnapshot(
            revision: 0, baseRevision: 0, baseSha: "", headSha: "", mergeBaseSha: "",
            files: diff.files, diffTooLarge: diff.isTooLarge, omitted: [])
        switch checkout.diffPhase {
        case .ready:
            diffError = nil
            diffPhase = .ready
        case .failed(let message):
            diffError = message
            diffPhase = .failed(message)
        case .idle, .loading:
            diffError = checkout.diffError
            diffPhase = .ready
        }
    }

    private func releaseDiff() async {
        guard let diffSubscriptionId else {
            self.diffSubscriptionId = nil
            diffSlot = nil
            assembler.reset()
            return
        }
        self.diffSubscriptionId = nil
        diffSlot = nil
        assembler.reset()
        if capabilities.supportsOwnedSubscriptions {
            _ = try? await client.send(SubscriptionReleaseRequest(subscriptionId: diffSubscriptionId))
        } else {
            try? await client.send(DiffUnsubscribeRequest(subscriptionId: diffSubscriptionId))
        }
    }

    private func releaseFileWatch() async {
        guard let fileSubscriptionId else { return }
        self.fileSubscriptionId = nil
        if capabilities.supportsOwnedSubscriptions {
            _ = try? await client.send(SubscriptionReleaseRequest(subscriptionId: fileSubscriptionId))
        } else {
            _ = try? await client.send(FileUnsubscribeRequest(subscriptionId: fileSubscriptionId))
        }
    }

    private func apply(version: FileVersion) {
        watchedFile = version
        if let error = version.error {
            fileError = error
            filePhase = .failed(error)
        } else {
            fileError = nil
            filePhase = .ready
        }
    }
}

/// A compact PR badge for the changes panel. Derived from `CheckoutPrStatus`; no network.
public struct PullRequestBadge: Sendable, Hashable {
    public enum Checks: Sendable, Hashable {
        case passing
        case failing
        case pending
        case none
        case unknown(String)
    }

    public var number: Int?
    public var title: String
    public var state: String
    public var url: String
    public var checks: Checks
    public var isDraft: Bool
    public var mergeable: CheckoutMergeable

    public init(status: CheckoutPrStatus) {
        number = status.number
        title = status.title
        state = status.state
        url = status.url
        checks = PullRequestBadge.checks(from: status.checksStatus)
        isDraft = status.isDraft == true
        mergeable = status.mergeable
    }

    public var isOpen: Bool { state.caseInsensitiveCompare("OPEN") == .orderedSame }
    public var isMerged: Bool { state.caseInsensitiveCompare("MERGED") == .orderedSame }
    public var isActionable: Bool {
        isOpen && !isMerged && !isDraft && mergeable != .conflicting && checks != .failing
    }

    private static func checks(from status: String?) -> Checks {
        guard let status = status?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty
        else { return .none }
        switch status.lowercased() {
        case "success", "passing", "passed": return .passing
        case "failure", "failing", "failed", "error": return .failing
        case "pending", "expected", "queued", "in_progress": return .pending
        case "neutral", "skipped": return .none
        default: return .unknown(status)
        }
    }
}

private func gitExtrasErrorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}

extension FileUpdate {
    static let wireMessageType = "fs.file.update"
}
