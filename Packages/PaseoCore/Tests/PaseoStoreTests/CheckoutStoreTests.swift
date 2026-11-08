import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct CheckoutStoreTests {
    private func scratchWorkspace() throws -> WorkspaceDescriptor {
        var workspace = try Load.sandboxWorkspace()
        workspace.workspaceDirectory = "/tmp/fixture-git/scratch-repo"
        workspace.projectRootPath = "/tmp/fixture-git/scratch-repo"
        workspace.name = "scratch"
        workspace.gitRuntime?.currentBranch = "main"
        return workspace
    }

    private func scratchStatus(_ workspace: WorkspaceDescriptor) throws -> CheckoutStatus {
        var status = try Load.scratchCheckoutStatus()
        status.cwd = workspace.cwd
        return status
    }

    private func prPayload(cwd: String) throws -> CheckoutPrStatusPayload {
        let json = """
            {"cwd":"\(cwd)","status":{
              "forge":"github","number":12,"url":"https://example.test/pr/12","title":"Fixture PR",
              "state":"OPEN","baseRefName":"main","headRefName":"feature","isMerged":false,
              "mergeable":"MERGEABLE","checks":[{"name":"test","status":"success","url":null}],
              "checksStatus":"success","repoOwner":"getpaseo","repoName":"paseo"
            },"githubFeaturesEnabled":true,"authState":"authenticated","forge":"github","error":null,
             "requestId":"pr"}
            """
        return try JSONDecoder().decode(CheckoutPrStatusPayload.self, from: Data(json.utf8))
    }

    @Test func loadsStatusPrBadgeAndWorkingDiff() async throws {
        let client = FakeDaemonClient()
        let workspace = try scratchWorkspace()
        let scratchStatus = try scratchStatus(workspace)
        let diff = try Load.checkoutDiff()
        let pr = try prPayload(cwd: workspace.cwd)

        client.on(CheckoutStatusRequest.self) { _ in scratchStatus }
        client.on(CheckoutPrStatusRequest.self) { _ in pr }
        client.on(SubscribeCheckoutDiffRequest.self) { _ in diff }

        let store = CheckoutStore(workspace: workspace, client: client)
        store.update(serverInfo: try Load.workspaceServerInfo())
        await store.load()

        #expect(store.phase == .ready)
        #expect(store.status?.hasRemote == true)
        #expect(store.branch == "main")
        #expect(store.isGit)
        #expect(store.prStatus?.title == "Fixture PR")
        #expect(store.prStatus?.mergeable == .mergeable)
        #expect(store.prStatusError == nil)
        #expect(store.diffPhase == .ready)
        #expect(store.filesChanged == diff.files.count)
        #expect(store.diffStat?.additions == diff.additions)
        #expect(store.diffError == nil)

        let subscribe = try #require(client.requests(SubscribeCheckoutDiffRequest.self).last)
        #expect(subscribe.cwd == workspace.cwd)
        #expect(subscribe.compare.mode == .uncommitted)
    }

    @Test func closeReleasesOwnedSubscription() async throws {
        let client = FakeDaemonClient()
        let workspace = try scratchWorkspace()
        let scratchStatus = try scratchStatus(workspace)
        let diff = try Load.checkoutDiff()

        client.on(CheckoutStatusRequest.self) { _ in scratchStatus }
        client.on(CheckoutPrStatusRequest.self) { _ in throw FakeDaemonClient.FakeError.noHandler("pr") }
        client.on(SubscribeCheckoutDiffRequest.self) { _ in diff }
        client.on(SubscriptionReleaseRequest.self) { request in
            SubscriptionReleaseRequest.Response(
                requestId: request.requestId, subscriptionId: request.subscriptionId)
        }

        let store = CheckoutStore(workspace: workspace, client: client)
        store.update(serverInfo: try Load.workspaceServerInfo())
        await store.load()
        let subscriptionId = try #require(store.diff?.subscriptionId)

        await store.close()

        let release = try #require(client.requests(SubscriptionReleaseRequest.self).last)
        #expect(release.subscriptionId == subscriptionId)
        #expect(client.requests(UnsubscribeCheckoutDiffRequest.self).isEmpty)
    }

    @Test func legacyHostsGetTheFireAndForgetUnsubscribe() async throws {
        let client = FakeDaemonClient()
        let workspace = try Load.sandboxWorkspace()
        let diff = try Load.checkoutDiff()
        client.on(CheckoutStatusRequest.self) { _ in try Load.checkoutStatus() }
        client.on(SubscribeCheckoutDiffRequest.self) { _ in diff }
        client.on(UnsubscribeCheckoutDiffRequest.self) { request in
            UnsubscribeCheckoutDiffRequest.Response(requestId: request.requestId)
        }

        let store = CheckoutStore(workspace: workspace, client: client)
        store.update(serverInfo: nil)
        await store.load()
        let subscriptionId = try #require(store.diff?.subscriptionId)

        await store.close()

        let unsubscribe = try #require(client.requests(UnsubscribeCheckoutDiffRequest.self).last)
        #expect(unsubscribe.subscriptionId == subscriptionId)
        #expect(client.requests(SubscriptionReleaseRequest.self).isEmpty)
    }

    @Test func commitAndPushRefreshStatus() async throws {
        let client = FakeDaemonClient()
        let workspace = try scratchWorkspace()
        let scratchStatus = try scratchStatus(workspace)
        let diff = try Load.checkoutDiff()

        client.on(CheckoutStatusRequest.self) { _ in scratchStatus }
        client.on(CheckoutPrStatusRequest.self) { _ in throw FakeDaemonClient.FakeError.noHandler("pr") }
        client.on(SubscribeCheckoutDiffRequest.self) { _ in diff }
        client.on(CheckoutCommitRequest.self) { request in
            CheckoutCommitRequest.Response(
                requestId: request.requestId, cwd: request.cwd, success: true, error: nil)
        }
        client.on(CheckoutPushRequest.self) { request in
            CheckoutPushRequest.Response(
                requestId: request.requestId, cwd: request.cwd, success: true, error: nil)
        }
        client.on(CheckoutRefreshRequest.self) { request in
            CheckoutRefreshRequest.Response(
                requestId: request.requestId, cwd: request.cwd, success: true, error: nil)
        }

        let store = CheckoutStore(workspace: workspace, client: client)
        store.update(serverInfo: try Load.workspaceServerInfo())
        await store.load()

        let committed = await store.commit(message: "  Fixture commit  ")
        #expect(committed)
        #expect(store.actionError == nil)
        #expect(store.isCommitting == false)
        let commit = try #require(client.requests(CheckoutCommitRequest.self).last)
        #expect(commit.message == "Fixture commit")
        #expect(commit.addAll == true)

        let pushed = await store.push()
        #expect(pushed)
        #expect(store.isPushing == false)
        #expect(client.requests(CheckoutPushRequest.self).count == 1)
        #expect(client.requests(CheckoutRefreshRequest.self).count >= 2)
        #expect(client.requests(CheckoutStatusRequest.self).count >= 3)
    }

    @Test func commitRejectsEmptyMessagesAndSurfacesDaemonErrors() async throws {
        let client = FakeDaemonClient()
        let workspace = try Load.sandboxWorkspace()
        client.on(CheckoutStatusRequest.self) { _ in try Load.checkoutStatus() }
        client.on(SubscribeCheckoutDiffRequest.self) { _ in try Load.checkoutDiff() }

        let store = CheckoutStore(workspace: workspace, client: client)
        store.update(serverInfo: try Load.workspaceServerInfo())
        await store.load()

        #expect(await store.commit(message: "   ") == false)
        #expect(store.actionError != nil)
        #expect(client.requests(CheckoutCommitRequest.self).isEmpty)

        client.on(CheckoutCommitRequest.self) { request in
            CheckoutCommitRequest.Response(
                requestId: request.requestId, cwd: request.cwd, success: false,
                error: CheckoutError(code: .unknown("UNKNOWN"), message: "nothing to commit"))
        }
        #expect(await store.commit(message: "x") == false)
        #expect(store.actionError == "nothing to commit")
    }

    @Test func diffAllIsGated() async throws {
        let client = FakeDaemonClient()
        let workspace = try Load.sandboxWorkspace()
        let store = CheckoutStore(workspace: workspace, client: client)
        store.update(serverInfo: nil)

        await store.loadDiff(compare: CheckoutDiffCompare(mode: .all, baseRef: "main"))

        #expect(store.diffPhase == .idle)
        #expect(store.actionError != nil)
        #expect(client.requests(SubscribeCheckoutDiffRequest.self).isEmpty)
    }

    @Test func pushedStatusAndDiffUpdatesApply() async throws {
        let client = FakeDaemonClient()
        let workspace = try Load.sandboxWorkspace()
        client.on(CheckoutStatusRequest.self) { _ in try Load.checkoutStatus() }
        client.on(SubscribeCheckoutDiffRequest.self) { _ in try Load.checkoutDiff() }

        let store = CheckoutStore(workspace: workspace, client: client)
        store.update(serverInfo: try Load.workspaceServerInfo())
        await store.load()

        var status = try Load.checkoutStatus()
        status.currentBranch = "pushed/branch"
        status.isDirty = false
        status.aheadBehind = CheckoutAheadBehind(ahead: 3, behind: 0)
        store.handle(CheckoutStatusUpdate(status: status, subscriptionId: nil, prStatus: nil))

        #expect(store.branch == "pushed/branch")
        #expect(store.isDirty == false)
        #expect(store.aheadBehind == CheckoutAheadBehind(ahead: 3, behind: 0))

        var diff = try Load.checkoutDiff()
        diff.files = []
        store.handle(diff)
        #expect(store.filesChanged == 0)
        #expect(store.diffPhase == .ready)

        var foreign = diff
        foreign.cwd = "/tmp/somewhere-else"
        foreign.files = [try Load.checkoutDiff().files[0]]
        store.handle(foreign)
        #expect(store.filesChanged == 0, "a diff for another cwd is ignored")
    }

    @Test func nonGitWorkspaceSkipsTheDiffStream() async throws {
        let client = FakeDaemonClient()
        var workspace = try Load.sandboxWorkspace()
        workspace.projectKind = .directory
        workspace.workspaceKind = .directory
        let notGitJSON = """
            {"cwd":"/tmp/fixture-sandbox","error":null,"requestId":"r","isGit":false,
             "isPaseoOwnedWorktree":false,"repoRoot":null,"currentBranch":null,"isDirty":null,
             "baseRef":null,"aheadBehind":null,"aheadOfOrigin":null,"behindOfOrigin":null,
             "hasRemote":false,"remoteUrl":null}
            """
        let notGit = try JSONDecoder().decode(CheckoutStatus.self, from: Data(notGitJSON.utf8))
        client.on(CheckoutStatusRequest.self) { _ in notGit }

        let store = CheckoutStore(workspace: workspace, client: client)
        store.update(serverInfo: try Load.workspaceServerInfo())
        await store.load()

        #expect(store.phase == .ready)
        #expect(store.isGit == false)
        #expect(store.diffPhase == .idle)
        #expect(client.requests(SubscribeCheckoutDiffRequest.self).isEmpty)
    }

    @Test func resubscribeReloadsStatusAndDiff() async throws {
        let client = FakeDaemonClient()
        let workspace = try Load.sandboxWorkspace()
        client.on(CheckoutStatusRequest.self) { _ in try Load.checkoutStatus() }
        client.on(SubscribeCheckoutDiffRequest.self) { _ in try Load.checkoutDiff() }

        let store = CheckoutStore(workspace: workspace, client: client)
        store.update(serverInfo: try Load.workspaceServerInfo())
        await store.load()
        #expect(client.requests(SubscribeCheckoutDiffRequest.self).count == 1)

        await store.resubscribe()

        #expect(client.requests(CheckoutStatusRequest.self).count == 2)
        #expect(client.requests(SubscribeCheckoutDiffRequest.self).count == 2)
        #expect(store.diffPhase == .ready)
    }
}
