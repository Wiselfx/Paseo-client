import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

@Suite struct WorkspaceProtocolTests {
    let decoder = JSONDecoder()

    private func payload<P: Decodable & Sendable>(_ type: P.Type, _ name: String) throws -> P {
        try decoder.decode(SessionPayloadEnvelope<P>.self, from: Fixture.data(name, in: "workspaces")).payload
    }

    @Test func workspaceDirectoryDecodes() throws {
        let response = try payload(FetchWorkspacesRequest.Response.self, "fetch_workspaces_response")
        #expect(!response.requestId.isEmpty)
        #expect(response.subscriptionId != nil)
        let workspace = try #require(response.entries.first)
        #expect(workspace.id == "wks_6adc97aa7e1e49e3")
        #expect(workspace.workspaceKind == .localCheckout)
        #expect(workspace.projectKind == .git)
        #expect(workspace.status == .attention)
        #expect(workspace.cwd == "/tmp/fixture-sandbox")
        #expect(workspace.branch == "main")
        #expect(workspace.isDirty)
        #expect(workspace.scripts.isEmpty)
        #expect(workspace.githubRuntime?.featuresEnabled == false)
        #expect(workspace.project?.projectName == "fixture-sandbox")
        #expect(response.pageInfo.hasMore == false)
    }

    @Test func projectListDecodes() throws {
        let response = try payload(ProjectListRequest.Response.self, "project_list_response")
        let project = try #require(response.projects.first)
        #expect(project.projectId == "prj_9f675e179792b526")
        #expect(project.projectRootPath == "/tmp/fixture-sandbox")
        #expect(project.projectKind == .git)
    }

    @Test func workspaceUpdatesDecode() throws {
        let expectedId = try payload(WorkspaceCreateRequest.Response.self, "workspace_create_response")
            .workspace?.id
        for name in ["workspace_update_00", "workspace_update_01", "workspace_update_02"] {
            let update = try payload(WorkspaceUpdate.self, name)
            guard case .upsert(let workspace, _) = update else {
                Issue.record("expected an upsert in \(name)")
                continue
            }
            #expect(workspace.id == expectedId)
            #expect(workspace.workspaceKind == .worktree)
            #expect(workspace.worktreeSlug == "fixture-t7")
            #expect(workspace.cwd.hasSuffix("/fixture-t7"))
        }

        let removeJSON = """
            {"type":"session","message":{"type":"workspace_update","payload":{
              "kind":"remove","id":"wks_remove","removedProjectId":"prj_gone",
              "emptyProject":{"projectId":"prj_gone","projectDisplayName":"gone","projectRootPath":"/tmp/gone","projectKind":"directory"}
            }}}
            """
        let remove = try decoder.decode(SessionPayloadEnvelope<WorkspaceUpdate>.self, from: Data(removeJSON.utf8))
            .payload
        guard case .remove(let id, let emptyProject, let removedProjectId, _) = remove else {
            Issue.record("expected a remove")
            return
        }
        #expect(id == "wks_remove")
        #expect(emptyProject?.projectDisplayName == "gone")
        #expect(removedProjectId == "prj_gone")
    }

    @Test func projectUpdatesDecode() throws {
        let upsertJSON = """
            {"type":"session","message":{"type":"project.update","payload":{
              "kind":"upsert","project":{"projectId":"prj_new","projectDisplayName":"new","projectRootPath":"/tmp/new","projectKind":"git"},"seq":7
            }}}
            """
        let upsert = try decoder.decode(SessionPayloadEnvelope<ProjectUpdate>.self, from: Data(upsertJSON.utf8)).payload
        guard case .upsert(let project, let seq) = upsert else {
            Issue.record("expected a project upsert")
            return
        }
        #expect(project.projectId == "prj_new")
        #expect(seq == 7)

        let removeJSON = """
            {"type":"session","message":{"type":"project.update","payload":{"kind":"remove","projectId":"prj_new"}}}
            """
        let remove = try decoder.decode(SessionPayloadEnvelope<ProjectUpdate>.self, from: Data(removeJSON.utf8)).payload
        guard case .remove(let projectId, _) = remove else {
            Issue.record("expected a project remove")
            return
        }
        #expect(projectId == "prj_new")
    }

    @Test func unknownDirectoryValuesDoNotThrow() throws {
        let json = """
            {"id":"wks_x","projectId":"prj_x","projectDisplayName":"x","projectRootPath":"/tmp/x",
             "projectKind":"hologram","workspaceKind":"teleporter","name":"x","status":"vibing",
             "activityAt":null,"scripts":[]}
            """
        let workspace = try decoder.decode(WorkspaceDescriptor.self, from: Data(json.utf8))
        #expect(workspace.projectKind == .unknown("hologram"))
        #expect(workspace.workspaceKind == .unknown("teleporter"))
        #expect(workspace.status == .unknown("vibing"))
    }

    @Test func checkoutStatusDecodes() throws {
        let status = try payload(CheckoutStatus.self, "checkout_status_response")
        #expect(status.cwd == "/tmp/fixture-sandbox")
        #expect(status.isGit)
        #expect(status.currentBranch == "main")
        #expect(status.isDirty == true)
        #expect(status.baseRef == "main")
        #expect(status.hasRemote == false)
        #expect(status.isPaseoOwnedWorktree == false)
        #expect(status.error == nil)

        let scratch = try payload(CheckoutStatus.self, "scratch_checkout_status_response")
        #expect(scratch.upstreamRef == "refs/remotes/origin/main")
        #expect(scratch.aheadOfOrigin == 0)
        #expect(scratch.behindOfOrigin == 0)
        #expect(scratch.remoteUrl == "/tmp/fixture-git/scratch-remote.git")
    }

    @Test func checkoutStatusUpdateCarriesPrStatus() throws {
        let update = try payload(CheckoutStatusUpdate.self, "checkout_status_update_00")
        #expect(update.status.cwd.hasSuffix("/fixture-t7"))
        #expect(update.status.isPaseoOwnedWorktree)
        #expect(update.status.mainRepoRoot == "/tmp/fixture-sandbox")
        #expect(update.prStatus?.status == nil)
        #expect(update.prStatus?.authStateText == "no_remote")
    }

    @Test func notGitStatusDecodes() throws {
        let json = """
            {"cwd":"/tmp/plain","error":null,"requestId":"r","isGit":false,"isPaseoOwnedWorktree":false,
             "repoRoot":null,"currentBranch":null,"isDirty":null,"baseRef":null,"aheadBehind":null,
             "aheadOfOrigin":null,"behindOfOrigin":null,"hasRemote":false,"remoteUrl":null}
            """
        let status = try decoder.decode(CheckoutStatus.self, from: Data(json.utf8))
        #expect(status.isGit == false)
        #expect(status.currentBranch == nil)
        #expect(status.isDirty == nil)
    }

    @Test func diffSnapshotDecodes() throws {
        let diff = try payload(CheckoutDiff.self, "subscribe_checkout_diff_response")
        #expect(diff.subscriptionId != nil)
        #expect(diff.cwd == "/tmp/fixture-sandbox")
        #expect(diff.error == nil)
        let file = try #require(diff.files.first { $0.path == "convert.py" })
        #expect(file.additions == 3)
        #expect(file.deletions == 0)
        #expect(file.isNew == false)
        #expect(!file.hunks.isEmpty)
        #expect(file.hunks.contains { $0.lines.contains { $0.type == .add } })
        #expect(diff.additions >= file.additions)

        let oneShot = try payload(CheckoutDiff.self, "checkout_diff_get_response")
        #expect(oneShot.subscriptionId == nil)
        #expect(oneShot.files.contains { $0.path == "convert.py" })
    }

    @Test func diffUpdateDecodes() throws {
        let update = try payload(CheckoutDiff.self, "checkout_diff_update_00")
        #expect(update.subscriptionId != nil)
        #expect(update.cwd == "/tmp/fixture-sandbox")
        #expect(update.files.contains { $0.path == "README.md" })
    }

    @Test func fileExplorerDecodes() throws {
        let listing = try payload(FileExplorerRequest.Response.self, "file_explorer_list_response")
        #expect(listing.mode == .list)
        #expect(listing.directory?.path == ".")
        #expect(listing.directory?.entries.contains { $0.name == "convert.py" && $0.kind == .file } == true)

        let read = try payload(FileExplorerRequest.Response.self, "file_explorer_file_response")
        #expect(read.mode == .file)
        let file = try #require(read.file)
        #expect(file.kind == .text)
        #expect(file.encoding == .utf8)
        #expect(file.textContent?.contains("def c_to_f") == true)
        #expect(file.size > 0)
    }

    @Test func githubSearchDecodes() throws {
        let response = try payload(
            GithubRepositorySearchRequest.Response.self, "github_search_repositories_response")
        #expect(response.status == .success)
        #expect(response.available)
        #expect(response.error == nil)
        let repository = try #require(response.repositories.first)
        #expect(repository.nameWithOwner.contains("/"))
        #expect(repository.visibility == .public)

        let unavailableJSON = """
            {"status":"unavailable","requestId":"r","repositories":[],"reason":"gh_missing",
             "available":false,"error":"gh is not installed"}
            """
        let unavailable = try decoder.decode(
            GithubRepositorySearchRequest.Response.self, from: Data(unavailableJSON.utf8))
        #expect(unavailable.status == .unavailable)
        #expect(unavailable.reason == "gh_missing")
    }

    @Test func createAndMutateResponsesDecode() throws {
        let created = try payload(WorkspaceCreateRequest.Response.self, "workspace_create_response")
        let workspace = try #require(created.workspace)
        #expect(workspace.workspaceKind == .worktree)
        #expect(workspace.gitRuntime?.currentBranch != nil)
        #expect(created.error == nil)

        let renamed = try payload(WorkspaceTitleSetRequest.Response.self, "workspace_title_set_response")
        #expect(renamed.accepted)
        #expect(renamed.title == "Fixture T7 worktree")

        let archived = try payload(ArchiveWorkspaceRequest.Response.self, "archive_workspace_response")
        #expect(archived.archivedAt != nil)
        #expect(archived.error == nil)

        let added = try payload(ProjectAddRequest.Response.self, "project_add_response")
        #expect(added.project?.projectRootPath == "/tmp/fixture-git/new-project")
        #expect(added.error == nil)

        let removed = try payload(ProjectRemoveRequest.Response.self, "project_remove_response")
        #expect(removed.accepted)

        let commit = try payload(CheckoutCommitRequest.Response.self, "checkout_commit_response")
        #expect(commit.success)
        let push = try payload(CheckoutPushRequest.Response.self, "checkout_push_response")
        #expect(push.success)

        let release = try payload(SubscriptionReleaseRequest.Response.self, "subscription_release_response")
        #expect(release.subscriptionId.isEmpty == false)
    }

    @Test func unknownCheckoutAndDiffValuesDoNotThrow() throws {
        let errorJSON = #"{"code":"COSMIC_RAY","message":"nope"}"#
        let error = try decoder.decode(CheckoutError.self, from: Data(errorJSON.utf8))
        #expect(error.code == .unknown("COSMIC_RAY"))

        let lineJSON = #"{"type":"sideways","content":"x"}"#
        let line = try decoder.decode(DiffLine.self, from: Data(lineJSON.utf8))
        #expect(line.type == .unknown("sideways"))

        let prJSON = """
            {"url":"https://example.test/1","title":"t","state":"OPEN","baseRefName":"main",
             "headRefName":"x","isMerged":false,"mergeable":"WOBBLY"}
            """
        let pr = try decoder.decode(CheckoutPrStatus.self, from: Data(prJSON.utf8))
        #expect(pr.mergeable == .unknown("WOBBLY"))
        #expect(pr.checks.isEmpty)
    }

    @Test func requestsEncodeTheDocumentedShapes() throws {
        let workspaces = FetchWorkspacesRequest(
            includeBackground: true,
            sort: [.init(key: .activityAt, direction: .desc)],
            page: .init(limit: 50),
            subscribe: true)
        var workspacesWithId = workspaces
        workspacesWithId.requestId = "r1"
        let workspacesJSON = try JSONDecoder().decode(
            JSONValue.self, from: JSONEncoder().encode(SessionRequestEnvelope(workspacesWithId)))
        let workspacesMessage = try #require(workspacesJSON["message"])
        #expect(workspacesMessage["type"] == .string("fetch_workspaces_request"))
        #expect(workspacesMessage["includeBackground"] == .bool(true))
        #expect(workspacesMessage["subscribe"]?["subscriptionId"] == nil)
        #expect(workspacesMessage["sort"] == .array([.object(["key": .string("activity_at"), "direction": .string("desc")])]))

        let worktree = WorkspaceCreateRequest(
            source: .worktree(
                WorkspaceSource.Worktree(
                    projectId: "prj_1", action: .branchOff, refName: "refs/heads/main",
                    branchName: "feature", worktreeSlug: "feature")),
            title: "Feature",
            idempotencyKey: "idem")
        var worktreeWithId = worktree
        worktreeWithId.requestId = "r2"
        let createJSON = try JSONDecoder().decode(
            JSONValue.self, from: JSONEncoder().encode(SessionRequestEnvelope(worktreeWithId)))
        let source = try #require(createJSON["message"]?["source"])
        #expect(source["kind"] == .string("worktree"))
        #expect(source["projectId"] == .string("prj_1"))
        #expect(source["action"] == .string("branch-off"))
        #expect(source["refName"] == .string("refs/heads/main"))
        #expect(source["branchName"] == .string("feature"))
        #expect(source["worktreeSlug"] == .string("feature"))

        let checkout = WorkspaceCreateRequest(
            source: .worktree(
                WorkspaceSource.Worktree(
                    projectId: "prj_1", action: .checkout,
                    checkoutSource: ChangeRequestCheckoutSource(forge: "github", number: 42),
                    githubPrNumber: 42)))
        var checkoutWithId = checkout
        checkoutWithId.requestId = "r3"
        let checkoutJSON = try JSONDecoder().decode(
            JSONValue.self, from: JSONEncoder().encode(SessionRequestEnvelope(checkoutWithId)))
        let checkoutSource = try #require(checkoutJSON["message"]?["source"]?["checkoutSource"])
        #expect(checkoutSource["kind"] == .string("change_request"))
        #expect(checkoutSource["number"] == .number(42))
        #expect(checkoutJSON["message"]?["source"]?["githubPrNumber"] == .number(42))

        var commit = CheckoutCommitRequest(cwd: "/tmp/x", message: "hi", addAll: true)
        commit.requestId = "r4"
        let commitJSON = try JSONDecoder().decode(
            JSONValue.self, from: JSONEncoder().encode(SessionRequestEnvelope(commit)))
        #expect(commitJSON["message"]?["type"] == .string("checkout_commit_request"))
        #expect(commitJSON["message"]?["cwd"] == .string("/tmp/x"))
        #expect(commitJSON["message"]?["addAll"] == .bool(true))

        var unsubscribe = UnsubscribeCheckoutDiffRequest(subscriptionId: "sub-1")
        unsubscribe.requestId = "r5"
        let unsubscribeJSON = try JSONDecoder().decode(
            JSONValue.self, from: JSONEncoder().encode(SessionRequestEnvelope(unsubscribe)))
        #expect(unsubscribeJSON["message"]?["type"] == .string("unsubscribe_checkout_diff_request"))
        #expect(unsubscribeJSON["message"]?["subscriptionId"] == .string("sub-1"))
    }
}
