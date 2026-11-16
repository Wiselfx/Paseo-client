import Foundation
import PaseoKit
import PaseoProtocol
import PaseoFixtures
import Testing

@testable import PaseoStore

/// M2.8: project rename, workspace pin/unpin, base branch, and archive undo.
@Suite @MainActor
struct WorkspaceMutationsTests {
    private func makeDirectory(features: Bool = true) throws -> (WorkspaceDirectory, FakeDaemonClient) {
        let client = FakeDaemonClient()
        let directory = WorkspaceDirectory(client: client)
        if features { directory.update(serverInfo: try Load.workspaceServerInfo()) }
        return (directory, client)
    }

    /// A server_info with exactly the features named (full session envelope).
    private func serverInfo(features: [String: Bool]) throws -> ServerInfo {
        let object: [String: Any] = [
            "type": "session",
            "message": [
                "type": "status",
                "payload": [
                    "status": "server_info",
                    "protocolVersion": 1,
                    "serverId": "srv_FIXTURE",
                    "hostname": "fixture-host",
                    "version": "0.0.1",
                    "features": features,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try Load.decoder.decode(SessionPayloadEnvelope<ServerInfo>.self, from: data).payload
    }

    // MARK: Project rename

    @Test func renameProjectStoresAndClearsTheOverride() async throws {
        let (directory, client) = try makeDirectory()
        client.on(ProjectListRequest.self) { _ in try Load.projectList() }
        client.on(FetchWorkspacesRequest.self) { _ in try Load.workspaceDirectory() }
        await directory.start()
        let project = try #require(try Load.projectList().projects.first)

        client.on(ProjectRenameRequest.self) { request in
            ProjectRenameRequest.Response(
                requestId: request.requestId,
                projectId: request.projectId,
                accepted: true,
                customName: request.customName,
                error: nil)
        }

        let renamed = await directory.renameProject(project.projectId, to: "  Custom name  ")
        #expect(renamed)
        #expect(directory.project(id: project.projectId)?.projectCustomName == "Custom name")
        let sent = try #require(client.requests(ProjectRenameRequest.self).first)
        #expect(sent.customName == "Custom name")

        // Whitespace-only clears, and the daemon answers null — the row reverts locally.
        let cleared = await directory.renameProject(project.projectId, to: "   ")
        #expect(cleared)
        #expect(directory.project(id: project.projectId)?.projectCustomName == nil)
        let clearRequest = try #require(client.requests(ProjectRenameRequest.self).last)
        #expect(clearRequest.customName == nil)
    }

    @Test func renameProjectFailureKeepsTheRowAndSurfacesTheError() async throws {
        let (directory, client) = try makeDirectory()
        client.on(ProjectListRequest.self) { _ in try Load.projectList() }
        client.on(FetchWorkspacesRequest.self) { _ in try Load.workspaceDirectory() }
        await directory.start()
        let project = try #require(try Load.projectList().projects.first)
        let original = project.projectCustomName

        client.on(ProjectRenameRequest.self) { request in
            ProjectRenameRequest.Response(
                requestId: request.requestId,
                projectId: request.projectId,
                accepted: false,
                customName: nil,
                error: "duplicate name")
        }

        let ok = await directory.renameProject(project.projectId, to: "Custom")
        #expect(!ok)
        #expect(directory.actionError == "duplicate name")
        #expect(directory.project(id: project.projectId)?.projectCustomName == original)
    }

    @Test func renameProjectIgnoresUnknownRoutes() async throws {
        let (directory, client) = try makeDirectory()
        let project = try #require(try Load.projectList().projects.first)

        client.on(ProjectRenameRequest.self) { _ in
            throw FakeDaemonClient.FakeError.noHandler("project.rename.request")
        }
        let ok = await directory.renameProject(project.projectId, to: "Custom")
        #expect(!ok)
        #expect(directory.actionError != nil)
    }

    // MARK: Pin / Unpin

    @Test func setPinnedPinsAndUnpinsOptimistically() async throws {
        let (directory, client) = try makeDirectory()
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))
        #expect(workspace.isPinned == false)

        client.on(WorkspacePinSetRequest.self) { request in
            WorkspacePinSetRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                accepted: true,
                pinnedAt: request.pinned ? "2026-11-09T07:19:05.954Z" : nil,
                error: nil)
        }

        let pinned = await directory.setPinned(workspace.id, true)
        #expect(pinned)
        #expect(directory.workspace(id: workspace.id)?.isPinned == true)
        #expect(directory.workspace(id: workspace.id)?.pinnedAt != nil)

        let unpinned = await directory.setPinned(workspace.id, false)
        #expect(unpinned)
        #expect(directory.workspace(id: workspace.id)?.isPinned == false)
        #expect(directory.workspace(id: workspace.id)?.pinnedAt == nil)

        let requests = client.requests(WorkspacePinSetRequest.self)
        #expect(requests.map(\.pinned) == [true, false])
    }

    @Test func setPinnedRollsBackWhenTheDaemonRejects() async throws {
        let (directory, client) = try makeDirectory()
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))

        client.on(WorkspacePinSetRequest.self) { request in
            WorkspacePinSetRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                accepted: false,
                pinnedAt: nil,
                error: "not a worktree")
        }

        let ok = await directory.setPinned(workspace.id, true)
        #expect(!ok)
        // Rolled back: the row shows its previous state and the error is set.
        #expect(directory.workspace(id: workspace.id)?.isPinned == false)
        #expect(directory.workspace(id: workspace.id)?.pinnedAt == nil)
        #expect(directory.actionError == "not a worktree")
    }

    @Test func setPinnedRollsBackOnSocketFailure() async throws {
        let (directory, client) = try makeDirectory()
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))

        client.on(WorkspacePinSetRequest.self) { _ in
            throw FakeDaemonClient.FakeError.noHandler("workspace.pin.set.request")
        }

        let ok = await directory.setPinned(workspace.id, true)
        #expect(!ok)
        #expect(directory.workspace(id: workspace.id)?.isPinned == false)
        #expect(directory.actionError != nil)
    }

    @Test func setPinnedIsGatedOnTheFeature() async throws {
        let (directory, client) = try makeDirectory(features: false)
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))

        let ok = await directory.setPinned(workspace.id, true)
        #expect(!ok)
        #expect(directory.actionError != nil)
        #expect(client.requests(WorkspacePinSetRequest.self).isEmpty)
    }

    @Test func setPinnedIsGatedPerFeatureNotGlobally() async throws {
        // Base branch present, pinning absent: base branch gates open while pin gates shut.
        let client = FakeDaemonClient()
        let directory = WorkspaceDirectory(client: client)
        directory.update(serverInfo: try serverInfo(features: [
            "workspaceBaseBranch": true,
        ]))
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))

        client.on(WorkspaceBaseBranchSetRequest.self) { request in
            WorkspaceBaseBranchSetRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                accepted: true,
                baseRef: request.baseRef,
                error: nil)
        }

        let ok = await directory.setBaseBranch(workspace.id, baseRef: "refs/heads/main")
        #expect(ok)
        #expect(client.requests(WorkspaceBaseBranchSetRequest.self).count == 1)

        let pinned = await directory.setPinned(workspace.id, true)
        #expect(!pinned)
        #expect(client.requests(WorkspacePinSetRequest.self).isEmpty)
    }

    // MARK: Base branch

    @Test func setBaseBranchSendsAndSurfacesErrors() async throws {
        let (directory, client) = try makeDirectory()
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))

        client.on(WorkspaceBaseBranchSetRequest.self) { request in
            WorkspaceBaseBranchSetRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                accepted: true,
                baseRef: request.baseRef,
                error: nil)
        }

        let ok = await directory.setBaseBranch(workspace.id, baseRef: "refs/heads/main")
        #expect(ok)
        #expect(client.requests(WorkspaceBaseBranchSetRequest.self).first?.baseRef == "refs/heads/main")

        client.on(WorkspaceBaseBranchSetRequest.self) { request in
            WorkspaceBaseBranchSetRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                accepted: false,
                baseRef: nil,
                error: "Workspace is not a Paseo worktree")
        }
        let rejected = await directory.setBaseBranch(workspace.id, baseRef: "refs/heads/main")
        #expect(!rejected)
        #expect(directory.actionError == "Workspace is not a Paseo worktree")

        let blank = await directory.setBaseBranch(workspace.id, baseRef: "  ")
        #expect(!blank)
        #expect(client.requests(WorkspaceBaseBranchSetRequest.self).count == 2)
    }

    @Test func setBaseBranchIsGatedOnTheFeature() async throws {
        let client = FakeDaemonClient()
        let directory = WorkspaceDirectory(client: client)
        directory.update(serverInfo: try serverInfo(features: [:]))

        let ok = await directory.setBaseBranch("wks_fixture", baseRef: "refs/heads/main")
        #expect(!ok)
        #expect(directory.actionError != nil)
        #expect(client.requests(WorkspaceBaseBranchSetRequest.self).isEmpty)
    }

    // MARK: Archive with undo

    @Test func archiveWithUndoHidesTheRowAndUndoRestoresIt() async throws {
        let (directory, client) = try makeDirectory()
        // The captured sandbox server_info predates archive undo; add it explicitly.
        directory.update(serverInfo: try serverInfo(features: [
            "workspaceList": true,
            "workspaceArchiveUndo": true,
        ]))
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))

        client.on(ArchiveWorkspaceRequest.self) { request in
            ArchiveWorkspaceRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                archivedAt: "2026-11-09T07:00:00.000Z",
                error: nil,
                canceled: nil)
        }
        let archived = await directory.archiveWorkspaceWithUndo(workspace.id)
        #expect(archived)
        #expect(directory.workspace(id: workspace.id) == nil)
        #expect(directory.actionError == nil)

        // No push is simulated here; the local snapshot re-inserts the row.
        client.on(WorkspaceArchiveUndoRequest.self) { request in
            WorkspaceArchiveUndoRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                accepted: true,
                error: nil)
        }
        let undone = await directory.undoArchive(workspace.id)
        #expect(undone)
        #expect(directory.workspace(id: workspace.id) != nil)
        #expect(directory.actionError == nil)
    }

    @Test func canceledArchiveKeepsTheRow() async throws {
        let (directory, client) = try makeDirectory()
        directory.update(serverInfo: try serverInfo(features: [
            "workspaceArchiveUndo": true,
        ]))
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))

        client.on(ArchiveWorkspaceRequest.self) { request in
            ArchiveWorkspaceRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                archivedAt: nil,
                error: "an undo won",
                canceled: true)
        }
        let archived = await directory.archiveWorkspaceWithUndo(workspace.id)
        #expect(!archived)
        #expect(directory.workspace(id: workspace.id) != nil)
        #expect(directory.actionError == "an undo won")
    }

    @Test func failedArchiveRestoresTheRow() async throws {
        let (directory, client) = try makeDirectory()
        directory.update(serverInfo: try serverInfo(features: [
            "workspaceArchiveUndo": true,
        ]))
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))

        client.on(ArchiveWorkspaceRequest.self) { _ in
            throw FakeDaemonClient.FakeError.noHandler("archive_workspace_request")
        }
        let archived = await directory.archiveWorkspaceWithUndo(workspace.id)
        #expect(!archived)
        #expect(directory.workspace(id: workspace.id) != nil)
        #expect(directory.actionError != nil)
    }

    @Test func archiveUndoFallsBackToPlainArchiveWhenUngated() async throws {
        let (directory, client) = try makeDirectory(features: false)
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))

        client.on(ArchiveWorkspaceRequest.self) { request in
            ArchiveWorkspaceRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                archivedAt: "2026-11-09T07:00:00.000Z",
                error: nil,
                canceled: nil)
        }
        let archived = await directory.archiveWorkspaceWithUndo(workspace.id)
        #expect(archived)
        #expect(directory.workspace(id: workspace.id) == nil)

        let undo = await directory.undoArchive(workspace.id)
        #expect(!undo)
        #expect(directory.actionError != nil)
        #expect(client.requests(WorkspaceArchiveUndoRequest.self).isEmpty)
    }

    @Test func undoArchiveFailureSurfacesTheErrorAndKeepsTheSnapshot() async throws {
        let (directory, client) = try makeDirectory()
        directory.update(serverInfo: try serverInfo(features: [
            "workspaceArchiveUndo": true,
        ]))
        let workspace = try Load.sandboxWorkspace()
        directory.apply(.upsert(workspace, seq: nil))

        client.on(ArchiveWorkspaceRequest.self) { request in
            ArchiveWorkspaceRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                archivedAt: "2026-11-09T07:00:00.000Z",
                error: nil,
                canceled: nil)
        }
        _ = await directory.archiveWorkspaceWithUndo(workspace.id)

        client.on(WorkspaceArchiveUndoRequest.self) { request in
            WorkspaceArchiveUndoRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                accepted: false,
                error: "already restored")
        }
        let undone = await directory.undoArchive(workspace.id)
        #expect(!undone)
        #expect(directory.actionError == "already restored")

        // A later undo attempt can still succeed (the snapshot is kept while the row is gone).
        client.on(WorkspaceArchiveUndoRequest.self) { request in
            WorkspaceArchiveUndoRequest.Response(
                requestId: request.requestId,
                workspaceId: request.workspaceId,
                accepted: true,
                error: nil)
        }
        let retried = await directory.undoArchive(workspace.id)
        #expect(retried)
        #expect(directory.workspace(id: workspace.id) != nil)
    }

    // MARK: Fixtures

    @Test func mutationFixturesDecode() throws {
        let pin = try Load.decoder.decode(
            SessionPayloadEnvelope<WorkspacePinSetRequest.Response>.self,
            from: Fixture.data("workspace_pin_set_response", in: "workspaces")
        ).payload
        #expect(pin.accepted)
        #expect(pin.pinnedAt != nil)

        let unpin = try Load.decoder.decode(
            SessionPayloadEnvelope<WorkspacePinSetRequest.Response>.self,
            from: Fixture.data("workspace_pin_set_unpin_response", in: "workspaces")
        ).payload
        #expect(unpin.accepted)
        #expect(unpin.pinnedAt == nil)

        let renamed = try Load.decoder.decode(
            SessionPayloadEnvelope<ProjectRenameRequest.Response>.self,
            from: Fixture.data("project_rename_response", in: "workspaces")
        ).payload
        #expect(renamed.accepted)
        #expect(renamed.customName == "Mutation fixture")

        let cleared = try Load.decoder.decode(
            SessionPayloadEnvelope<ProjectRenameRequest.Response>.self,
            from: Fixture.data("project_rename_clear_response", in: "workspaces")
        ).payload
        #expect(cleared.accepted)
        #expect(cleared.customName == nil)

        let baseBranch = try Load.decoder.decode(
            SessionPayloadEnvelope<WorkspaceBaseBranchSetRequest.Response>.self,
            from: Fixture.data("workspace_base_branch_set_response", in: "workspaces")
        ).payload
        // The sandbox workspace is not a Paseo worktree; the captured response says so.
        #expect(baseBranch.accepted == false)
        #expect(baseBranch.error != nil)
    }
}
