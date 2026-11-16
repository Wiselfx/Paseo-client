import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct GitActionsTests {
    private func workspace(cwd: String = "/tmp/fixture-sandbox") throws -> WorkspaceDescriptor {
        var workspace = try Load.sandboxWorkspace()
        workspace.workspaceDirectory = cwd
        workspace.projectRootPath = cwd
        workspace.name = "fixture-sandbox"
        workspace.gitRuntime?.currentBranch = "main"
        return workspace
    }

    private func serverInfo(
        commitsList: Bool = true, commitBaseClassification: Bool = true,
        forgeAutoMerge: Bool = true, legacyAutoMerge: Bool = false, refresh: Bool = false
    ) throws -> ServerInfo {
        let json = """
            {"serverId":"srv_FIXTURE","version":"0.15.2","features":{
              "commitsList":\(commitsList),
              "commitBaseClassification":\(commitBaseClassification),
              "checkoutForgeSetAutoMerge":\(forgeAutoMerge),
              "checkoutGithubSetAutoMerge":\(legacyAutoMerge),
              "checkoutRefresh":\(refresh)
            }}
            """
        return try JSONDecoder().decode(ServerInfo.self, from: Data(json.utf8))
    }

    nonisolated private func fixture(_ name: String) throws -> Data {
        try Fixture.data(name, in: "git-ops")
    }

    private func decode<P: Decodable & Sendable>(_ type: P.Type, from data: Data) throws -> P {
        try JSONDecoder().decode(SessionPayloadEnvelope<P>.self, from: data).payload
    }

    private func makeActions(
        client: FakeDaemonClient, serverInfo: ServerInfo? = nil,
        workspace cwd: String = "/tmp/fixture-sandbox"
    ) throws -> WorkspaceGitActions {
        let store = GitExtrasStore(client: client)
        if let serverInfo { store.update(serverInfo: serverInfo) }
        let checkout = CheckoutStore(workspace: try workspace(cwd: cwd), client: client)
        return store.gitActions(for: checkout)
    }

    nonisolated private func statusResponse(_ cwd: String = "/tmp/fixture-sandbox") -> Data {
        Data(
            """
            {"type":"session","message":{"type":"checkout_status_response","payload":{
              "cwd":"\(cwd)","isGit":true,"isPaseoOwnedWorktree":false,
              "repoRoot":"\(cwd)","currentBranch":"main","isDirty":false,
              "baseRef":"main","hasRemote":false,"aheadBehind":null,"error":null,
              "requestId":"fixture"
            }}}
            """.utf8)
    }

    nonisolated private func prStatusResponse() -> Data {
        Data(
            """
            {"type":"session","message":{"type":"checkout_pr_status_response","payload":{
              "cwd":"/tmp/fixture-sandbox","status":null,"githubFeaturesEnabled":true,
              "authState":"authenticated","forge":"github","error":null,
              "requestId":"fixture"
            }}}
            """.utf8)
    }

    nonisolated private func registerRefreshHandlers(_ client: FakeDaemonClient) {
        client.on(CheckoutStatusRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutStatus>.self, from: statusResponse()).payload
        }
        client.on(CheckoutPrStatusRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutPrStatusPayload>.self, from: prStatusResponse()).payload
        }
    }

    nonisolated private func mutationResponse(
        type: String, success: Bool, code: String? = nil, message: String? = nil
    ) -> Data {
        let error: String
        if let code {
            let message = message ?? "boom"
            error = "{\"code\":\"\(code)\",\"message\":\"\(message)\"}"
        } else {
            error = "null"
        }
        return Data(
            """
            {"type":"session","message":{"type":"\(type)","payload":{
              "cwd":"/tmp/fixture-sandbox","success":\(success),"error":\(error),"requestId":"fixture"
            }}}
            """.utf8)
    }

    nonisolated private func prCreateResponse(
        url: String? = nil, number: Int? = nil, code: String? = nil, message: String? = nil
    ) -> Data {
        let error: String
        if let code {
            let message = message ?? "boom"
            error = "{\"code\":\"\(code)\",\"message\":\"\(message)\"}"
        } else {
            error = "null"
        }
        let url = url.map { "\"\($0)\"" } ?? "null"
        let number = number.map(String.init) ?? "null"
        return Data(
            """
            {"type":"session","message":{"type":"checkout_pr_create_response","payload":{
              "cwd":"/tmp/fixture-sandbox","url":\(url),"number":\(number),
              "error":\(error),"requestId":"fixture"
            }}}
            """.utf8)
    }

    // MARK: Fixture decoding

    @Test func commitsListDecodesLiveFixture() throws {
        let response = try decode(
            CheckoutCommitsListRequest.Response.self, from: fixture("commits_list_response"))
        #expect(response.baseRef == nil)
        let commit = try #require(response.commits.first)
        #expect(commit.sha == "ab3b806a42f4fb13c9884e65ab499b8e95eecad8")
        #expect(commit.shortSha == "ab3b806")
        #expect(commit.subject == "Fixture baseline")
        #expect(commit.authorName == "Fixture")
        #expect(commit.isOnRemote == false)
        #expect(commit.isOnBase == true)
        #expect(commit.files.count == 2)
        #expect(commit.files.first?.path == "README.md")
        #expect(commit.files.first?.status == .added)
        #expect(commit.files.first?.additions == 3)
    }

    @Test func commitsFileDiffDecodesLiveFixture() throws {
        let response = try decode(
            CheckoutCommitFileDiffRequest.Response.self, from: fixture("commits_file_diff_response"))
        let file = try #require(response.file)
        #expect(file.path == "README.md")
        #expect(file.isNew == true)
        #expect(file.additions == 3)
        #expect(file.hunks.first?.lines.contains { $0.type == .add } == true)
    }

    @Test func writeResultDecodesLiveFixture() throws {
        let response = try decode(
            FileWriteRequest.Response.self, from: fixture("fs_file_write_response"))
        guard case .written(let modifiedAt, let size, let revision) = response.result else {
            Issue.record("expected .written, got \(response.result)")
            return
        }
        #expect(size == 12)
        #expect(!modifiedAt.isEmpty)
        #expect(revision?.isEmpty == false)
    }

    // MARK: Commits list gate and load

    @Test func commitsListWithoutTheFeatureMakesNoRequests() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(client: client, serverInfo: try serverInfo(commitsList: false))
        await actions.loadCommits()
        #expect(actions.commitsError == "This daemon cannot list commits.")
        #expect(client.requests(CheckoutCommitsListRequest.self).isEmpty)
    }

    @Test func commitsListLoadsFromTheDaemon() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(client: client, serverInfo: try serverInfo())
        let data = try fixture("commits_list_response")
        client.on(CheckoutCommitsListRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutCommitsListRequest.Response>.self, from: data).payload
        }
        await actions.loadCommits()
        #expect(actions.supportsCommitsList)
        #expect(actions.supportsCommitBaseClassification)
        #expect(actions.commits.count == 1)
        #expect(actions.commitsBaseRef == nil)
        #expect(actions.commitsError == nil)
        #expect(actions.isLoadingCommits == false)
    }

    @Test func commitFileDiffIsStoredAndReturned() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(client: client, serverInfo: try serverInfo())
        let data = try fixture("commits_file_diff_response")
        client.on(CheckoutCommitFileDiffRequest.self) { request in
            #expect(request.sha == "ab3b806a42f4fb13c9884e65ab499b8e95eecad8")
            #expect(request.path == "README.md")
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutCommitFileDiffRequest.Response>.self, from: data).payload
        }
        let file = await actions.loadCommitFileDiff(
            sha: "ab3b806a42f4fb13c9884e65ab499b8e95eecad8", path: "README.md")
        #expect(file?.path == "README.md")
        #expect(actions.commitFileDiff?.additions == 3)
        #expect(actions.commitFileDiffError == nil)
    }

    @Test func commitsFileDiffWithoutTheFeatureMakesNoRequests() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(client: client, serverInfo: try serverInfo(commitsList: false))
        let file = await actions.loadCommitFileDiff(sha: "abc", path: "README.md")
        #expect(file == nil)
        #expect(actions.commitFileDiffError == "This daemon cannot read commit file diffs.")
        #expect(client.requests(CheckoutCommitFileDiffRequest.self).isEmpty)
    }

    // MARK: Mutations and typed errors

    @Test func pullSuccessRefreshesAndClearsFailure() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(client: client, serverInfo: try serverInfo())
        client.on(CheckoutPullRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutMutationResponse>.self,
                from: mutationResponse(type: "checkout_pull_response", success: true)).payload
        }
        registerRefreshHandlers(client)
        let ok = await actions.pull()
        #expect(ok == true)
        #expect(actions.lastFailure == nil)
        #expect(actions.actionError == nil)
        #expect(client.requests(CheckoutPullRequest.self).count == 1)
        #expect(client.requests(CheckoutStatusRequest.self).count == 1)
        #expect(actions.isPulling == false)
    }

    @Test func pullFailureSurfacesMergeConflictDistinctly() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(client: client, serverInfo: try serverInfo())
        client.on(CheckoutPullRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutMutationResponse>.self,
                from: mutationResponse(
                    type: "checkout_pull_response", success: false,
                    code: "MERGE_CONFLICT", message: "conflict in convert.py")).payload
        }
        let ok = await actions.pull()
        #expect(ok == false)
        #expect(actions.lastFailure?.code == .mergeConflict)
        #expect(actions.actionError == "conflict in convert.py")
    }

    @Test func mergeFromBaseConflictIsDistinguishable() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(client: client, serverInfo: try serverInfo())
        client.on(CheckoutMergeFromBaseRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutMutationResponse>.self,
                from: mutationResponse(
                    type: "checkout_merge_from_base_response", success: false,
                    code: "MERGE_CONFLICT", message: "merge conflict")).payload
        }
        let ok = await actions.mergeFromBase()
        #expect(ok == false)
        #expect(actions.lastFailure?.code == .mergeConflict)
        #expect(actions.isMergingFromBase == false)
    }

    @Test func createPullRequestSuccessReturnsURLAndNumber() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(client: client, serverInfo: try serverInfo())
        client.on(CheckoutPrCreateRequest.self) { request in
            #expect(request.title == "T15 work")
            #expect(request.baseRef == "main")
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutPrCreateRequest.Response>.self,
                from: prCreateResponse(url: "https://example.test/pr/7", number: 7)).payload
        }
        registerRefreshHandlers(client)
        let result = await actions.createPullRequest(title: "T15 work", body: "body", baseRef: "main")
        #expect(result?.url == "https://example.test/pr/7")
        #expect(result?.number == 7)
        #expect(actions.lastFailure == nil)
        #expect(actions.isCreatingPullRequest == false)
        #expect(client.requests(CheckoutPrCreateRequest.self).count == 1)
    }

    @Test func createPullRequestFailureCarriesTypedCode() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(client: client, serverInfo: try serverInfo())
        client.on(CheckoutPrCreateRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutPrCreateRequest.Response>.self,
                from: prCreateResponse(code: "NOT_ALLOWED", message: "no permission")).payload
        }
        let result = await actions.createPullRequest(title: "T15", body: nil, baseRef: nil)
        #expect(result == nil)
        #expect(actions.lastFailure?.code == .notAllowed)
        #expect(actions.actionError == "no permission")
    }

    @Test func mergePullRequestForwardsMethodAndRefreshes() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(client: client, serverInfo: try serverInfo())
        client.on(CheckoutPrMergeRequest.self) { request in
            #expect(request.mergeMethod == .squash)
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutMutationResponse>.self,
                from: mutationResponse(type: "checkout_pr_merge_response", success: true)).payload
        }
        registerRefreshHandlers(client)
        let ok = await actions.mergePullRequest(method: .squash)
        #expect(ok == true)
        #expect(actions.isMergingPullRequest == false)
    }

    // MARK: Auto-merge

    @Test func setAutoMergeSendsMethodWhenEnabling() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(client: client, serverInfo: try serverInfo())
        client.on(CheckoutForgeSetAutoMergeRequest.self) { request in
            #expect(request.enabled == true)
            #expect(request.mergeMethod == .squash)
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutSetAutoMergeResponse>.self,
                from: Data("""
                    {"type":"session","message":{"type":"checkout.forge.set_auto_merge.response","payload":{
                      "cwd":"/tmp/fixture-sandbox","enabled":true,"success":true,
                      "error":null,"requestId":"fixture"
                    }}}
                    """.utf8)).payload
        }
        client.on(CheckoutPrStatusRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutPrStatusPayload>.self, from: prStatusResponse()).payload
        }
        let ok = await actions.setAutoMerge(enabled: true, method: .squash)
        #expect(ok == true)
        #expect(client.requests(CheckoutForgeSetAutoMergeRequest.self).count == 1)
        #expect(client.requests(CheckoutGithubSetAutoMergeRequest.self).isEmpty)
    }

    @Test func setAutoMergeOmitsMethodWhenDisabling() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(client: client, serverInfo: try serverInfo())
        client.on(CheckoutForgeSetAutoMergeRequest.self) { request in
            #expect(request.enabled == false)
            #expect(request.mergeMethod == nil)
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutSetAutoMergeResponse>.self,
                from: Data("""
                    {"type":"session","message":{"type":"checkout.forge.set_auto_merge.response","payload":{
                      "cwd":"/tmp/fixture-sandbox","enabled":false,"success":true,
                      "error":null,"requestId":"fixture"
                    }}}
                    """.utf8)).payload
        }
        client.on(CheckoutPrStatusRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutPrStatusPayload>.self, from: prStatusResponse()).payload
        }
        let ok = await actions.setAutoMerge(enabled: false, method: .squash)
        #expect(ok == true)
        let sent = try #require(client.requests(CheckoutForgeSetAutoMergeRequest.self).first)
        #expect(sent.mergeMethod == nil)
    }

    @Test func setAutoMergeFallsBackToTheLegacyTwin() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(
            client: client,
            serverInfo: try serverInfo(forgeAutoMerge: false, legacyAutoMerge: true))
        client.on(CheckoutGithubSetAutoMergeRequest.self) { request in
            #expect(request.enabled == true)
            #expect(request.mergeMethod == .merge)
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutSetAutoMergeResponse>.self,
                from: Data("""
                    {"type":"session","message":{"type":"checkout.github.set_auto_merge.response","payload":{
                      "cwd":"/tmp/fixture-sandbox","enabled":true,"success":true,
                      "error":null,"requestId":"fixture"
                    }}}
                    """.utf8)).payload
        }
        client.on(CheckoutPrStatusRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<CheckoutPrStatusPayload>.self, from: prStatusResponse()).payload
        }
        let ok = await actions.setAutoMerge(enabled: true, method: .merge)
        #expect(ok == true)
        #expect(client.requests(CheckoutForgeSetAutoMergeRequest.self).isEmpty)
        #expect(client.requests(CheckoutGithubSetAutoMergeRequest.self).count == 1)
    }

    @Test func setAutoMergeWithoutAnyGateSendsNothing() async throws {
        let client = FakeDaemonClient()
        let actions = try makeActions(
            client: client, serverInfo: try serverInfo(forgeAutoMerge: false, legacyAutoMerge: false))
        let ok = await actions.setAutoMerge(enabled: true, method: .merge)
        #expect(ok == false)
        #expect(actions.actionError == "This daemon cannot set PR auto-merge.")
        #expect(client.requests(CheckoutForgeSetAutoMergeRequest.self).isEmpty)
        #expect(client.requests(CheckoutGithubSetAutoMergeRequest.self).isEmpty)
    }

    @Test func gitActionsAreTheSameInstancePerCheckout() async throws {
        let client = FakeDaemonClient()
        let store = GitExtrasStore(client: client)
        store.update(serverInfo: try serverInfo())
        let checkout = CheckoutStore(workspace: try workspace(), client: client)
        let first = store.gitActions(for: checkout)
        let second = store.gitActions(for: checkout)
        #expect(first === second)
    }
}
