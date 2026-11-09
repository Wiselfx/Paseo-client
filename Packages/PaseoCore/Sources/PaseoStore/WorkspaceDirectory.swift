import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// One readable line for an error in a store's error property.
func paseoStoreErrorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}

/// The sidebar's live project/workspace directory, kept current by `workspace_update` and
/// `project.update`.
///
/// Owned by `HostSession`. Views read the `public private(set)` properties and call the `async`
/// methods; failures land in `error` (loading) or `actionError` (mutations).
///
/// IMPLEMENTATION TICKET: docs/tickets/T7-workspaces-git.md
@MainActor @Observable
public final class WorkspaceDirectory {
    public private(set) var projects: [WorkspaceProjectDescriptor] = []
    public private(set) var workspaces: [WorkspaceDescriptor] = []
    /// Last error from loading the directory.
    public private(set) var error: String?
    /// Last failed add/create/rename/archive/clone.
    public private(set) var actionError: String?
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var isAddingProject = false
    public private(set) var isCreatingWorkspace = false
    public private(set) var isCloning = false
    /// Last repository-search outcome, so the clone sheet can explain `gh` problems.
    public private(set) var repositorySearchStatus: GithubRepositorySearchRequest.Response.Status?

    // Capability flags, computed once per `server_info` and exposed as plain Bools.
    public private(set) var supportsProjectList = false
    public private(set) var supportsProjectAdd = false
    public private(set) var supportsProjectRemove = false
    public private(set) var supportsWorkspaceCreate = false
    public private(set) var supportsGithubClone = false
    public private(set) var supportsGithubRepositorySearch = false
    public private(set) var supportsBackgroundWorkspaces = false
    public private(set) var supportsExplicitEventSubscriptions = false
    /// `features.workspacePinning`: pin/unpin RPC exists (added in v0.1.107).
    public private(set) var supportsWorkspacePinning = false
    /// `features.workspaceBaseBranch`: base-branch RPC exists (added after v0.11.2).
    public private(set) var supportsWorkspaceBaseBranch = false
    /// `features.workspaceArchiveUndo`: archive undo RPC exists (added in v0.15.3).
    public private(set) var supportsWorkspaceArchiveUndo = false

    /// Snapshot of the last optimistically-archived workspace, kept for `undoArchive`. One at a
    /// time: a newer archive overwrites it.
    internal var lastArchiveSnapshot: WorkspaceDescriptor?

    // internal so WorkspaceDirectory+Mutations.swift (same module) can send RPCs.
    internal let client: any DaemonClient
    private var subscriptionId: String?
    private var eventSubscriptionId: String?

    internal init(client: any DaemonClient) {
        self.client = client
    }

    /// Projects with their workspaces, pinned/active first. Projects whose last workspace was
    /// archived still appear (the daemon sends them as `emptyProjects`).
    public var groups: [WorkspaceGroup] {
        projects.map { project in
            WorkspaceGroup(
                project: project,
                workspaces: workspaces.filter { $0.projectId == project.projectId })
        }
    }

    public func workspace(id: String) -> WorkspaceDescriptor? {
        workspaces.first { $0.id == id }
    }

    public func project(id: String) -> WorkspaceProjectDescriptor? {
        projects.first { $0.projectId == id }
    }

    // MARK: Loading

    /// Reads projects and the workspace directory, subscribing this socket to live updates.
    public func start() async {
        await reload()
    }

    /// Re-fetches everything. Also used after a reconnect, when the daemon forgot the subscription.
    public func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var failures: [String] = []
        await subscribeEventsIfNeeded()

        if supportsProjectList {
            do {
                let response = try await client.send(ProjectListRequest())
                projects = response.projects
            } catch {
                failures.append(paseoStoreErrorText(error))
            }
        }

        do {
            let response = try await client.send(
                FetchWorkspacesRequest(
                    includeBackground: supportsBackgroundWorkspaces ? true : nil,
                    subscribe: true))
            workspaces = response.entries
            subscriptionId = response.subscriptionId
            merge(projects: response.emptyProjects)
            for workspace in workspaces { ensureProject(for: workspace) }
            hasLoaded = true
        } catch {
            failures.append(paseoStoreErrorText(error))
        }

        sortProjects()
        sortWorkspaces()
        error = failures.isEmpty ? nil : failures.joined(separator: " ")
    }

    /// Pull to refresh.
    public func refresh() async {
        await reload()
    }

    // MARK: Mutations

    /// Registers an existing folder on the host as a project. Returns nil on failure.
    public func addProject(cwd: String) async -> WorkspaceProjectDescriptor? {
        guard supportsProjectAdd else {
            actionError = "This daemon cannot add projects."
            return nil
        }
        isAddingProject = true
        defer { isAddingProject = false }
        do {
            let response = try await client.send(ProjectAddRequest(cwd: cwd))
            guard let project = response.project else {
                actionError = response.error ?? "The daemon did not add the project."
                return nil
            }
            upsert(project)
            actionError = nil
            return project
        } catch {
            actionError = paseoStoreErrorText(error)
            return nil
        }
    }

    /// Creates a workspace in `project`. Worktree sources need `features.workspaceMultiplicity`.
    public func createWorkspace(
        in project: WorkspaceProjectDescriptor,
        source: NewWorkspaceSource,
        title: String? = nil,
        idempotencyKey: String? = nil
    ) async -> WorkspaceDescriptor? {
        let wireSource = source.wireSource(project: project)
        if case .worktree = wireSource, !supportsWorkspaceCreate {
            actionError = "This daemon cannot create worktree workspaces."
            return nil
        }
        isCreatingWorkspace = true
        defer { isCreatingWorkspace = false }
        do {
            let response = try await client.send(
                WorkspaceCreateRequest(
                    source: wireSource,
                    title: title,
                    idempotencyKey: idempotencyKey ?? UUID().uuidString))
            guard let workspace = response.workspace else {
                actionError = response.error ?? "The daemon did not create a workspace."
                return nil
            }
            apply(.upsert(workspace, seq: nil))
            actionError = nil
            return workspace
        } catch {
            actionError = paseoStoreErrorText(error)
            return nil
        }
    }

    /// Renames a workspace. `title` nil or empty clears the override.
    public func renameWorkspace(_ workspaceId: String, title: String?) async -> Bool {
        do {
            let response = try await client.send(
                WorkspaceTitleSetRequest(workspaceId: workspaceId, title: title))
            guard response.accepted else {
                actionError = response.error ?? "The daemon rejected the rename."
                return false
            }
            if let index = workspaces.firstIndex(where: { $0.id == workspaceId }) {
                workspaces[index].title = response.title
                if let name = response.title, !name.isEmpty {
                    workspaces[index].name = name
                }
            }
            actionError = nil
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    /// Archives a workspace. A canceled archive (undo raced it) leaves the row in place.
    public func archiveWorkspace(_ workspaceId: String) async -> Bool {
        do {
            let response = try await client.send(ArchiveWorkspaceRequest(workspaceId: workspaceId))
            if response.canceled == true {
                actionError = response.error ?? "The archive was canceled."
                return false
            }
            if let error = response.error {
                actionError = error
                return false
            }
            workspaces.removeAll { $0.id == workspaceId }
            actionError = nil
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    /// Unregisters a project and its workspaces.
    public func removeProject(_ projectId: String) async -> Bool {
        guard supportsProjectRemove else {
            actionError = "This daemon cannot remove projects."
            return false
        }
        do {
            let response = try await client.send(ProjectRemoveRequest(projectId: projectId))
            guard response.accepted else {
                actionError = response.error ?? "The daemon rejected the removal."
                return false
            }
            projects.removeAll { $0.projectId == projectId }
            let removed = Set(response.removedWorkspaceIds)
            workspaces.removeAll { removed.contains($0.id) || $0.projectId == projectId }
            actionError = nil
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    /// Searches the user's GitHub repositories through the host's `gh` CLI.
    public func searchGithubRepositories(_ query: String, limit: Int = 30) async -> [GithubRepository] {
        guard supportsGithubRepositorySearch else {
            actionError = "This daemon cannot search GitHub repositories."
            return []
        }
        do {
            let response = try await client.send(
                GithubRepositorySearchRequest(query: query, limit: limit))
            repositorySearchStatus = response.status
            if response.status == .success {
                actionError = nil
            } else {
                actionError = response.error ?? "GitHub repository search failed."
            }
            return response.repositories
        } catch {
            repositorySearchStatus = .error
            actionError = paseoStoreErrorText(error)
            return []
        }
    }

    /// Clones `repo` into `targetDirectory` on the host and registers it as a project.
    public func cloneGithubProject(
        repo: String,
        into targetDirectory: String,
        protocol cloneProtocol: GithubCloneProtocol = .https
    ) async -> WorkspaceProjectDescriptor? {
        guard supportsGithubClone else {
            actionError = "This daemon cannot clone GitHub repositories."
            return nil
        }
        isCloning = true
        defer { isCloning = false }
        do {
            let response = try await client.send(
                ProjectGithubCloneRequest(
                    repo: repo,
                    targetDirectory: targetDirectory,
                    cloneProtocol: cloneProtocol))
            guard let project = response.project else {
                actionError = response.error ?? "The clone did not produce a project."
                return nil
            }
            upsert(project)
            actionError = nil
            return project
        } catch {
            actionError = paseoStoreErrorText(error)
            return nil
        }
    }

    // MARK: HostSession handoff

    /// Recomputes the capability flags. Called once per `server_info`, never in a view.
    internal func update(serverInfo: ServerInfo?) {
        supportsProjectList = serverInfo?.hasFeature("projectList") ?? false
        supportsProjectAdd = serverInfo?.hasFeature("projectAdd") ?? false
        supportsProjectRemove = serverInfo?.hasFeature("projectRemove") ?? false
        supportsWorkspaceCreate = serverInfo?.hasFeature("workspaceMultiplicity") ?? false
        supportsGithubClone = serverInfo?.hasFeature("projectGithubClone") ?? false
        supportsGithubRepositorySearch = serverInfo?.hasFeature("workspaceGithubRepositorySearch") ?? false
        supportsBackgroundWorkspaces = serverInfo?.hasFeature("backgroundWorkspaces") ?? false
        supportsExplicitEventSubscriptions = serverInfo?.hasFeature("explicitEventSubscriptions") ?? false
        supportsWorkspacePinning = serverInfo?.hasFeature("workspacePinning") ?? false
        supportsWorkspaceBaseBranch = serverInfo?.hasFeature("workspaceBaseBranch") ?? false
        supportsWorkspaceArchiveUndo = serverInfo?.hasFeature("workspaceArchiveUndo") ?? false
    }

    /// A reconnect means the daemon forgot the event subscription too.
    internal func prepareForReconnect() {
        eventSubscriptionId = nil
    }

    internal func apply(_ update: WorkspaceUpdate) {
        switch update {
        case .upsert(let workspace, _):
            if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
                workspaces[index] = workspace
            } else {
                workspaces.append(workspace)
            }
            ensureProject(for: workspace)
            sortWorkspaces()

        case .remove(let id, let emptyProject, let removedProjectId, _):
            workspaces.removeAll { $0.id == id }
            if let emptyProject { merge(projects: [emptyProject]) }
            if let removedProjectId {
                projects.removeAll { $0.projectId == removedProjectId }
                workspaces.removeAll { $0.projectId == removedProjectId }
            }
            sortProjects()

        case .unknown:
            break
        }
    }

    internal func apply(_ update: ProjectUpdate) {
        switch update {
        case .upsert(let project, _):
            upsert(project)

        case .remove(let projectId, _):
            projects.removeAll { $0.projectId == projectId }
            workspaces.removeAll { $0.projectId == projectId }

        case .unknown:
            break
        }
    }

    /// Applies a pushed git status to the matching row, so branch/dirty/ahead-behind stay fresh
    /// in the sidebar without a reload.
    internal func apply(status: CheckoutStatus) {
        guard let index = workspaces.firstIndex(where: { $0.cwd == status.cwd }) else { return }
        var runtime = workspaces[index].gitRuntime ?? WorkspaceGitRuntime()
        runtime.currentBranch = status.currentBranch
        runtime.isDirty = status.isDirty
        runtime.aheadBehind = status.aheadBehind
        runtime.aheadOfOrigin = status.aheadOfOrigin
        runtime.behindOfOrigin = status.behindOfOrigin
        if let remoteUrl = status.remoteUrl { runtime.remoteUrl = remoteUrl }
        workspaces[index].gitRuntime = runtime
    }

    // MARK: Internals

    /// Subscribes this socket to project and checkout-status events. Modern daemons only deliver
    /// them to explicit subscribers; old daemons broadcast status updates anyway.
    private func subscribeEventsIfNeeded() async {
        guard supportsExplicitEventSubscriptions, eventSubscriptionId == nil else { return }
        do {
            let response = try await client.send(
                SessionEventsSetSubscriptionRequest(events: ["project.update", "checkout_status_update"]))
            eventSubscriptionId = response.subscriptionId
        } catch {
            // Non-fatal: the workspace directory itself still works, only project rows go stale.
            eventSubscriptionId = nil
        }
    }

    private func upsert(_ project: WorkspaceProjectDescriptor) {
        if let index = projects.firstIndex(where: { $0.projectId == project.projectId }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
        sortProjects()
    }

    private func merge(projects newProjects: [WorkspaceProjectDescriptor]) {
        for project in newProjects where !projects.contains(where: { $0.projectId == project.projectId }) {
            projects.append(project)
        }
        sortProjects()
    }

    /// A workspace can arrive before its project descriptor (old daemons omit `project.list`).
    private func ensureProject(for workspace: WorkspaceDescriptor) {
        guard !projects.contains(where: { $0.projectId == workspace.projectId }) else { return }
        projects.append(
            WorkspaceProjectDescriptor(
                projectId: workspace.projectId,
                projectDisplayName: workspace.projectDisplayName,
                projectCustomName: workspace.projectCustomName,
                projectCustomIconRevision: workspace.projectCustomIconRevision,
                projectRootPath: workspace.projectRootPath,
                projectKind: workspace.projectKind))
        sortProjects()
    }

    private func sortProjects() {
        projects.sort {
            $0.projectDisplayName.localizedCaseInsensitiveCompare($1.projectDisplayName) == .orderedAscending
        }
    }

    private func sortWorkspaces() {
        workspaces.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            let left = activityDate(lhs)
            let right = activityDate(rhs)
            if left != right {
                switch (left, right) {
                case let (left?, right?): return left > right
                case (_?, nil): return true
                default: return false
                }
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func activityDate(_ workspace: WorkspaceDescriptor) -> Date? {
        for timestamp in [workspace.activityAt, workspace.lastUserMessageAt, workspace.createdAt] {
            if let timestamp, let date = PaseoDate.parse(timestamp) { return date }
        }
        return nil
    }

    // MARK: Internal seam for `WorkspaceDirectory+Mutations.swift`

    /// Sets `actionError` (errors land there, not thrown).
    internal func setActionError(_ message: String?) {
        actionError = message
    }

    /// Removes `id` from the directory and returns the removed descriptor (optimistic archive).
    internal func snapshotAndRemoveWorkspace(id: String) -> WorkspaceDescriptor? {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return nil }
        return workspaces.remove(at: index)
    }

    /// Puts a snapshot back (archive failed, another undo won, or the archive was canceled).
    internal func restoreWorkspace(_ workspace: WorkspaceDescriptor) {
        guard !workspaces.contains(where: { $0.id == workspace.id }) else { return }
        workspaces.append(workspace)
        sortWorkspaces()
    }

    /// Applies a renamed project row locally (the daemon reverts to the derived name on nil).
    internal func renameProjectLocally(_ projectId: String, customName: String?) {
        guard let index = projects.firstIndex(where: { $0.projectId == projectId }) else { return }
        projects[index].projectCustomName = customName
        sortProjects()
    }

    /// Sets or clears `pinnedAt` locally (nil clears), keeping the list sorted.
    internal func setPinLocally(_ workspaceId: String, pinnedAt: String?) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        workspaces[index].pinnedAt = pinnedAt
        sortWorkspaces()
    }
}

/// A project row plus its workspaces, for a grouped sidebar.
public struct WorkspaceGroup: Identifiable, Sendable, Equatable {
    public var project: WorkspaceProjectDescriptor
    public var workspaces: [WorkspaceDescriptor]
    public var id: String { project.projectId }
    public init(project: WorkspaceProjectDescriptor, workspaces: [WorkspaceDescriptor]) {
        self.project = project
        self.workspaces = workspaces
    }
}

/// What the New-workspace sheet asks for, mapped to the daemon's `workspace.create` source union.
public enum NewWorkspaceSource: Sendable, Equatable {
    /// Open the project root as a workspace.
    case local
    /// Open another existing directory as a workspace.
    case directory(path: String)
    /// Cut a Paseo worktree on a new branch off `baseRef`.
    case branchOff(baseRef: String, branchName: String, worktreeSlug: String? = nil)
    /// Check an existing branch/ref out into a new worktree.
    case checkout(refName: String)
    /// Check a PR/MR head out into a new worktree.
    case changeRequest(forge: String? = nil, number: Int, projectPath: String? = nil)

    func wireSource(project: WorkspaceProjectDescriptor) -> WorkspaceSource {
        switch self {
        case .local:
            return .directory(path: project.projectRootPath, projectId: project.projectId)
        case .directory(let path):
            return .directory(path: path, projectId: project.projectId)
        case .branchOff(let baseRef, let branchName, let worktreeSlug):
            return .worktree(
                WorkspaceSource.Worktree(
                    projectId: project.projectId,
                    action: .branchOff,
                    refName: baseRef,
                    branchName: branchName,
                    worktreeSlug: worktreeSlug))
        case .checkout(let refName):
            return .worktree(
                WorkspaceSource.Worktree(
                    projectId: project.projectId,
                    action: .checkout,
                    refName: refName))
        case .changeRequest(let forge, let number, let projectPath):
            return .worktree(
                WorkspaceSource.Worktree(
                    projectId: project.projectId,
                    action: .checkout,
                    checkoutSource: ChangeRequestCheckoutSource(
                        forge: forge, number: number, projectPath: projectPath),
                    githubPrNumber: number))
        }
    }
}
