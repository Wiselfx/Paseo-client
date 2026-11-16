import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct WorkspaceDirectoryTests {
    private func makeDirectory(features: Bool = true) throws -> (WorkspaceDirectory, FakeDaemonClient) {
        let client = FakeDaemonClient()
        let directory = WorkspaceDirectory(client: client)
        if features { directory.update(serverInfo: try Load.workspaceServerInfo()) }
        return (directory, client)
    }

    @Test func loadsProjectsAndWorkspacesAndSubscribes() async throws {
        let (directory, client) = try makeDirectory()
        let projects = try Load.projectList()
        let workspaces = try Load.workspaceDirectory()
        client.on(ProjectListRequest.self) { _ in projects }
        client.on(FetchWorkspacesRequest.self) { _ in workspaces }

        await directory.start()

        #expect(directory.hasLoaded)
        #expect(directory.error == nil)
        #expect(directory.projects.map(\.projectId) == ["prj_9f675e179792b526"])
        let workspace = try #require(directory.workspaces.first)
        #expect(workspace.id == "wks_6adc97aa7e1e49e3")
        #expect(workspace.name == "fixture sandbox")
        #expect(workspace.branch == "main")
        #expect(directory.groups.count == 1)
        #expect(directory.groups.first?.workspaces.map(\.id) == [workspace.id])

        let request = try #require(client.requests(FetchWorkspacesRequest.self).last)
        #expect(request.subscribe != nil)
        #expect(request.includeBackground == true)
    }

    @Test func subscribesToProjectAndStatusEventsOncePerConnection() async throws {
        let (directory, client) = try makeDirectory()
        client.on(ProjectListRequest.self) { _ in try Load.projectList() }
        client.on(FetchWorkspacesRequest.self) { _ in try Load.workspaceDirectory() }
        client.on(SessionEventsSetSubscriptionRequest.self) { request in
            SessionEventsSetSubscriptionRequest.Response(
                requestId: request.requestId, subscriptionId: "events-1")
        }

        await directory.start()

        let requests = client.requests(SessionEventsSetSubscriptionRequest.self)
        #expect(requests.count == 1)
        #expect(Set(requests[0].events) == ["project.update", "checkout_status_update"])

        await directory.reload()
        #expect(client.requests(SessionEventsSetSubscriptionRequest.self).count == 1)

        directory.prepareForReconnect()
        await directory.reload()
        #expect(client.requests(SessionEventsSetSubscriptionRequest.self).count == 2)
    }

    @Test func oldHostsSkipTheEventSubscription() async throws {
        let (directory, client) = try makeDirectory(features: false)
        client.on(FetchWorkspacesRequest.self) { _ in try Load.workspaceDirectory() }

        await directory.start()

        #expect(client.requests(SessionEventsSetSubscriptionRequest.self).isEmpty)
    }

    @Test func missingProjectListStillSynthesizesProjectsFromWorkspaces() async throws {
        let (directory, client) = try makeDirectory()
        directory.update(serverInfo: nil)
        client.on(FetchWorkspacesRequest.self) { _ in try Load.workspaceDirectory() }

        await directory.start()

        #expect(directory.hasLoaded)
        #expect(directory.projects.count == 1)
        #expect(directory.projects.first?.projectDisplayName == "fixture-sandbox")
        #expect(client.requests(ProjectListRequest.self).isEmpty)
    }

    @Test func loadingFailureLandsInError() async throws {
        let (directory, client) = try makeDirectory()
        client.on(ProjectListRequest.self) { _ in throw FakeDaemonClient.FakeError.noHandler("project.list.request") }
        client.on(FetchWorkspacesRequest.self) { _ in throw FakeDaemonClient.FakeError.noHandler("fetch_workspaces_request") }

        await directory.start()

        #expect(directory.hasLoaded == false)
        let error = try #require(directory.error)
        #expect(!error.isEmpty)
    }

    @Test func addProjectGatesOnFeatureAndUpserts() async throws {
        let (directory, client) = try makeDirectory(features: false)
        let added = try Load.projectAdd()
        client.on(ProjectAddRequest.self) { _ in added }

        let gated = await directory.addProject(cwd: "/tmp/fixture-git/new-project")
        #expect(gated == nil)
        #expect(directory.actionError != nil)

        directory.update(serverInfo: try Load.workspaceServerInfo())
        let project = try #require(await directory.addProject(cwd: "/tmp/fixture-git/new-project"))
        #expect(project.projectId == added.project?.projectId)
        #expect(directory.projects.contains { $0.projectId == project.projectId })
        #expect(directory.actionError == nil)
    }

    @Test func createWorkspaceMapsEverySource() async throws {
        let (directory, client) = try makeDirectory()
        let project = try #require(try Load.projectList().projects.first)
        let created = try Load.workspaceCreate()
        client.on(WorkspaceCreateRequest.self) { _ in created }

        _ = await directory.createWorkspace(in: project, source: .local)
        _ = await directory.createWorkspace(in: project, source: .directory(path: "/tmp/fixture-git/new-project"))
        _ = await directory.createWorkspace(
            in: project,
            source: .branchOff(baseRef: "refs/heads/main", branchName: "feature", worktreeSlug: "feature"))
        _ = await directory.createWorkspace(in: project, source: .checkout(refName: "refs/heads/other"))
        _ = await directory.createWorkspace(in: project, source: .changeRequest(forge: "github", number: 7))

        let requests = client.requests(WorkspaceCreateRequest.self)
        #expect(requests.count == 5)
        #expect(requests.allSatisfy { $0.idempotencyKey != nil })

        guard case .directory(let localPath, let localProject) = requests[0].source else {
            Issue.record("expected a directory source")
            return
        }
        #expect(localPath == project.projectRootPath)
        #expect(localProject == project.projectId)

        guard case .directory(let explicitPath, _) = requests[1].source else {
            Issue.record("expected a directory source")
            return
        }
        #expect(explicitPath == "/tmp/fixture-git/new-project")

        guard case .worktree(let branchOff) = requests[2].source else {
            Issue.record("expected a worktree source")
            return
        }
        #expect(branchOff.action == .branchOff)
        #expect(branchOff.refName == "refs/heads/main")
        #expect(branchOff.branchName == "feature")
        #expect(branchOff.worktreeSlug == "feature")

        guard case .worktree(let checkout) = requests[3].source else {
            Issue.record("expected a worktree source")
            return
        }
        #expect(checkout.action == .checkout)
        #expect(checkout.refName == "refs/heads/other")

        guard case .worktree(let changeRequest) = requests[4].source else {
            Issue.record("expected a worktree source")
            return
        }
        #expect(changeRequest.action == .checkout)
        #expect(changeRequest.checkoutSource?.number == 7)
        #expect(changeRequest.checkoutSource?.forge == "github")
        #expect(changeRequest.githubPrNumber == 7)

        let createdId = try Load.workspaceCreate().workspace?.id
        #expect(directory.workspaces.contains { $0.id == createdId })
        #expect(directory.actionError == nil)
    }

    @Test func createWorkspaceIsGatedOnMultiplicity() async throws {
        let (directory, client) = try makeDirectory(features: false)
        let project = try #require(try Load.projectList().projects.first)
        client.on(WorkspaceCreateRequest.self) { _ in try Load.workspaceCreate() }

        let created = await directory.createWorkspace(
            in: project, source: .branchOff(baseRef: "main", branchName: "x"))
        #expect(created == nil)
        #expect(directory.actionError != nil)
        #expect(client.requests(WorkspaceCreateRequest.self).isEmpty)
    }

    @Test func renameAndArchiveMutateTheRows() async throws {
        let (directory, client) = try makeDirectory()
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))

        client.on(WorkspaceTitleSetRequest.self) { request in
            WorkspaceTitleSetRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                accepted: true,
                title: "Renamed",
                error: nil)
        }
        let renamed = await directory.renameWorkspace(workspace.id, title: "Renamed")
        #expect(renamed)
        #expect(directory.workspace(id: workspace.id)?.name == "Renamed")
        #expect(directory.workspace(id: workspace.id)?.title == "Renamed")

        client.on(ArchiveWorkspaceRequest.self) { request in
            ArchiveWorkspaceRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                archivedAt: "2026-11-08T22:00:00.000Z",
                error: nil,
                canceled: nil)
        }
        let archived = await directory.archiveWorkspace(workspace.id)
        #expect(archived)
        #expect(directory.workspace(id: workspace.id) == nil)
        #expect(directory.actionError == nil)
    }

    @Test func canceledArchiveKeepsTheRow() async throws {
        let (directory, client) = try makeDirectory()
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))

        client.on(ArchiveWorkspaceRequest.self) { request in
            ArchiveWorkspaceRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                archivedAt: nil,
                error: "undo won",
                canceled: true)
        }
        let archived = await directory.archiveWorkspace(workspace.id)
        #expect(archived == false)
        #expect(directory.workspace(id: workspace.id) != nil)
        #expect(directory.actionError == "undo won")
    }

    @Test func removeProjectDropsItsWorkspaces() async throws {
        let (directory, client) = try makeDirectory()
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))
        #expect(directory.workspace(id: workspace.id) != nil)

        client.on(ProjectRemoveRequest.self) { request in
            ProjectRemoveRequest.Response(
                requestId: request.requestId,
                projectId: request.projectId,
                accepted: true,
                removedWorkspaceIds: [workspace.id],
                error: nil)
        }
        let removed = await directory.removeProject(workspace.projectId)
        #expect(removed)
        #expect(directory.project(id: workspace.projectId) == nil)
        #expect(directory.workspace(id: workspace.id) == nil)
    }

    @Test func liveUpdatesAddAndRemoveRows() throws {
        let (directory, _) = try makeDirectory()
        let update = try Load.workspaceUpdate()
        directory.apply(update)
        let expectedId = try Load.workspaceCreate().workspace?.id
        let added = try #require(directory.workspace(id: expectedId ?? ""))
        #expect(added.workspaceKind == .worktree)
        #expect(directory.project(id: added.projectId) != nil)

        directory.apply(.remove(id: added.id, emptyProject: nil, removedProjectId: nil, seq: nil))
        #expect(directory.workspace(id: added.id) == nil)

        directory.apply(.upsert(added, seq: nil))
        #expect(directory.workspace(id: added.id) != nil)
        directory.apply(.remove(id: added.id, emptyProject: nil, removedProjectId: added.projectId, seq: nil))
        #expect(directory.project(id: added.projectId) == nil)
    }

    @Test func pushedStatusUpdatesTheDirectoryRow() throws {
        let (directory, _) = try makeDirectory()
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))

        var status = try Load.checkoutStatus()
        status.currentBranch = "feature/thing"
        status.isDirty = false
        status.aheadBehind = CheckoutAheadBehind(ahead: 2, behind: 1)
        directory.apply(status: status)

        let updated = try #require(directory.workspace(id: workspace.id))
        #expect(updated.gitRuntime?.currentBranch == "feature/thing")
        #expect(updated.gitRuntime?.isDirty == false)
        #expect(updated.gitRuntime?.aheadBehind == CheckoutAheadBehind(ahead: 2, behind: 1))
    }

    @Test func searchAndCloneUseTheGithubFeatures() async throws {
        let (directory, client) = try makeDirectory()
        let search = try Load.githubSearch()
        let added = try Load.projectAdd()
        client.on(GithubRepositorySearchRequest.self) { _ in search }
        client.on(ProjectGithubCloneRequest.self) { request in
            ProjectGithubCloneRequest.Response(
                requestId: request.requestId,
                repo: request.repo,
                checkoutPath: "/tmp/fixture-git/paseo",
                project: added.project,
                error: nil)
        }

        let repositories = await directory.searchGithubRepositories("paseo", limit: 5)
        #expect(repositories.count == search.repositories.count)
        #expect(directory.repositorySearchStatus == .success)
        #expect(directory.actionError == nil)

        let project = try #require(
            await directory.cloneGithubProject(
                repo: "getpaseo/paseo", into: "/tmp/fixture-git"))
        #expect(project.projectRootPath == "/tmp/fixture-git/new-project")
        #expect(directory.projects.contains { $0.projectId == project.projectId })

        let cloneRequest = try #require(client.requests(ProjectGithubCloneRequest.self).first)
        #expect(cloneRequest.repo == "getpaseo/paseo")
        #expect(cloneRequest.targetDirectory == "/tmp/fixture-git")
        #expect(cloneRequest.cloneProtocol == .https)
    }

    @Test func githubFeaturesAreGated() async throws {
        let (directory, client) = try makeDirectory(features: false)
        let repositories = await directory.searchGithubRepositories("paseo")
        #expect(repositories.isEmpty)
        let project = await directory.cloneGithubProject(repo: "a/b", into: "/tmp")
        #expect(project == nil)
        #expect(directory.actionError != nil)
        #expect(client.requests(GithubRepositorySearchRequest.self).isEmpty)
        #expect(client.requests(ProjectGithubCloneRequest.self).isEmpty)
    }
}
