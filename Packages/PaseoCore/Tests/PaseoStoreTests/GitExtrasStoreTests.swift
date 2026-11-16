import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct GitExtrasStoreTests {
    private func workspace(cwd: String = "/tmp/fixture-git/scratch-repo") throws -> WorkspaceDescriptor {
        var workspace = try Load.sandboxWorkspace()
        workspace.workspaceDirectory = cwd
        workspace.projectRootPath = cwd
        workspace.name = "scratch"
        workspace.gitRuntime?.currentBranch = "main"
        return workspace
    }

    private func serverInfo(
        modernDiff: Bool = true, discard: Bool = true, files: Bool = true, owned: Bool = true
    ) throws -> ServerInfo {
        let json = """
            {"serverId":"srv_FIXTURE","version":"0.15.2","features":{
              "diffSubscription":\(modernDiff),"checkoutDiscardChanges":\(discard),
              "workspaceFileEditing":\(files),"ownedSubscriptions":\(owned)
            }}
            """
        return try JSONDecoder().decode(ServerInfo.self, from: Data(json.utf8))
    }

    private func diffBegin(revision: Int = 1, baseRevision: Int = 0) -> DiffFrame {
        .begin(
            DiffBegin(
                slot: 3, revision: revision, baseRevision: baseRevision, baseSha: "base",
                headSha: "head", mergeBaseSha: "merge",
                entries: [
                    DiffEntry(
                        path: "README.md", oldPath: nil, change: .modified, content: .text,
                        additions: 1, deletions: 0, body: true)
                ]))
    }

    private func diffBodies(revision: Int = 1) -> DiffFrame {
        .bodies(
            DiffBodies(
                slot: 3, revision: revision,
                files: [
                    DiffBody(
                        path: "README.md",
                        hunks: [
                            DiffStreamHunk(
                                oldStart: 1, oldCount: 1, newStart: 1, newCount: 2,
                                lines: [DiffStreamLine(kind: .add, content: "modern line")])
                        ])
                ]))
    }

    private func diffEnd(revision: Int = 1) -> DiffFrame {
        .end(DiffEnd(slot: 3, revision: revision, diffTooLarge: false, omitted: [], error: nil))
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

    // MARK: Modern diff

    @Test func modernDiffSubscribesAssemblesAndReleases() async throws {
        let client = FakeDaemonClient()
        let checkout = CheckoutStore(workspace: try workspace(), client: client)
        let store = GitExtrasStore(client: client)
        store.update(serverInfo: try serverInfo())
        let extras = store.workspace(for: checkout)

        client.on(DiffSubscribeRequest.self) { request in
            DiffSubscribePayload(
                requestId: request.requestId, subscriptionId: "diff-1", slot: 3, error: nil)
        }

        await extras.loadDiff(compare: .working(cwd: checkout.cwd))

        let request = try #require(client.requests(DiffSubscribeRequest.self).last)
        #expect(request.cwd == checkout.cwd)
        #expect(request.base == .rev("HEAD"))
        #expect(request.head == .worktree)
        #expect(request.mergeBase == nil)
        #expect(extras.diffPhase == .loading)
        #expect(extras.isUsingLegacyPipeline == false)
        #expect(client.requests(SubscribeCheckoutDiffRequest.self).isEmpty, "modern hosts never use the legacy stream")

        let begin = try #require(DiffFrameCodec.encode(diffBegin()))
        store.handle(binaryFrame: begin)
        #expect(extras.pendingEntries.count == 1)
        #expect(extras.diffPhase == .loading)

        let bodies = try #require(DiffFrameCodec.encode(diffBodies()))
        store.handle(binaryFrame: bodies)
        #expect(extras.snapshot == nil, "bodies alone do not commit a revision")

        let end = try #require(DiffFrameCodec.encode(diffEnd()))
        store.handle(binaryFrame: end)
        #expect(extras.diffPhase == .ready)
        #expect(extras.filesChanged == 1)
        #expect(extras.additions == 1)
        #expect(extras.files.first?.hunks.first?.lines.first?.content == "modern line")
        #expect(extras.diffError == nil)

        await store.close(checkout.workspaceId)

        let release = try #require(client.requests(SubscriptionReleaseRequest.self).last)
        #expect(release.subscriptionId == "diff-1")
    }

    @Test func framesForAnotherSlotAreIgnored() async throws {
        let client = FakeDaemonClient()
        let checkout = CheckoutStore(workspace: try workspace(), client: client)
        let store = GitExtrasStore(client: client)
        store.update(serverInfo: try serverInfo())
        let extras = store.workspace(for: checkout)
        client.on(DiffSubscribeRequest.self) { request in
            DiffSubscribePayload(
                requestId: request.requestId, subscriptionId: "diff-1", slot: 3, error: nil)
        }
        await extras.loadDiff(compare: .working(cwd: checkout.cwd))

        let foreign = DiffFrame.begin(
            DiffBegin(
                slot: 8, revision: 1, baseRevision: 0, baseSha: "", headSha: "",
                mergeBaseSha: "", entries: []))
        store.handle(binaryFrame: try #require(DiffFrameCodec.encode(foreign)))
        #expect(extras.pendingEntries.isEmpty)
        #expect(extras.diffPhase == .loading)
    }

    @Test func modernDiffErrorsLandInTheObservableFailure() async throws {
        let client = FakeDaemonClient()
        let checkout = CheckoutStore(workspace: try workspace(), client: client)
        let store = GitExtrasStore(client: client)
        store.update(serverInfo: try serverInfo())
        let extras = store.workspace(for: checkout)
        client.on(DiffSubscribeRequest.self) { request in
            DiffSubscribePayload(
                requestId: request.requestId, subscriptionId: "diff-1", slot: 3,
                error: DiffError(code: .notGitRepo, message: "not a repo"))
        }

        await extras.loadDiff(compare: .working(cwd: checkout.cwd))

        #expect(extras.diffPhase == .failed("not a repo"))
        #expect(extras.diffError == "not a repo")
        #expect(extras.snapshot == nil)
    }

    // MARK: Legacy fallback

    @Test func withoutTheFlagTheLegacyDiffStreamIsUsed() async throws {
        let client = FakeDaemonClient()
        let checkout = CheckoutStore(workspace: try workspace(), client: client)
        let store = GitExtrasStore(client: client)
        store.update(serverInfo: try serverInfo(modernDiff: false))
        let extras = store.workspace(for: checkout)
        let diff = try Load.checkoutDiff()
        client.on(CheckoutStatusRequest.self) { _ in try Load.checkoutStatus() }
        client.on(SubscribeCheckoutDiffRequest.self) { _ in diff }

        await extras.loadDiff(compare: .working(cwd: checkout.cwd))

        #expect(client.requests(DiffSubscribeRequest.self).isEmpty)
        let legacy = try #require(client.requests(SubscribeCheckoutDiffRequest.self).last)
        #expect(legacy.compare.mode == .uncommitted)
        #expect(extras.isUsingLegacyPipeline)
        #expect(extras.diffPhase == .ready)
        #expect(extras.filesChanged == diff.files.count)
        #expect(extras.additions == diff.additions)
    }

    @Test func unsupportedLegacyComparisonsFailWithoutASubscription() async throws {
        let client = FakeDaemonClient()
        let checkout = CheckoutStore(workspace: try workspace(), client: client)
        let store = GitExtrasStore(client: client)
        store.update(serverInfo: try serverInfo(modernDiff: false))
        let extras = store.workspace(for: checkout)

        await extras.loadDiff(
            compare: DiffCompare(cwd: checkout.cwd, base: .index, head: .worktree))

        #expect(extras.diffPhase == .failed("This daemon cannot run this comparison."))
        #expect(client.requests(SubscribeCheckoutDiffRequest.self).isEmpty)
    }

    // MARK: Mutations

    @Test func discardGatesOnTheFeatureAndSurfacesDaemonErrors() async throws {
        let client = FakeDaemonClient()
        let checkout = CheckoutStore(workspace: try workspace(), client: client)
        let store = GitExtrasStore(client: client)
        let extras = store.workspace(for: checkout)

        store.update(serverInfo: try serverInfo(discard: false))
        #expect(await extras.discard(paths: ["README.md"]) == false)
        #expect(extras.actionError == "This daemon cannot discard changes.")
        #expect(client.requests(CheckoutDiscardChangesRequest.self).isEmpty)

        store.update(serverInfo: try serverInfo())
        client.on(CheckoutDiscardChangesRequest.self) { request in
            CheckoutDiscardChangesRequest.Response(
                requestId: request.requestId, cwd: request.cwd, success: false,
                error: CheckoutError(code: .unknown("UNKNOWN"), message: "path is protected"))
        }
        #expect(await extras.discard(paths: ["  README.md  "]) == false)
        #expect(extras.actionError == "path is protected")
        let request = try #require(client.requests(CheckoutDiscardChangesRequest.self).last)
        #expect(request.paths == ["README.md"])

        client.on(CheckoutDiscardChangesRequest.self) { request in
            CheckoutDiscardChangesRequest.Response(
                requestId: request.requestId, cwd: request.cwd, success: true, error: nil)
        }
        client.on(CheckoutStatusRequest.self) { _ in try Load.checkoutStatus() }
        #expect(await extras.discard(paths: ["README.md"]))
        #expect(extras.actionError == nil)
        #expect(extras.isDiscarding == false)
    }

    @Test func branchSuggestionsAndSwitchingDriveTheDaemon() async throws {
        let client = FakeDaemonClient()
        let checkout = CheckoutStore(workspace: try workspace(), client: client)
        let store = GitExtrasStore(client: client)
        store.update(serverInfo: try serverInfo())
        let extras = store.workspace(for: checkout)

        client.on(BranchSuggestionsRequest.self) { request in
            BranchSuggestionsRequest.Response(
                requestId: request.requestId, branches: ["feature/t11"],
                branchDetails: nil, error: nil)
        }
        await extras.loadBranchSuggestions(query: "  feature  ", limit: 20)
        let suggestions = try #require(client.requests(BranchSuggestionsRequest.self).last)
        #expect(suggestions.query == "feature")
        #expect(suggestions.limit == 20)
        #expect(extras.branchSuggestions.map(\.name) == ["feature/t11"])
        #expect(extras.branchError == nil)

        client.on(CheckoutSwitchBranchRequest.self) { request in
            CheckoutSwitchBranchRequest.Response(
                requestId: request.requestId, cwd: request.cwd, success: true,
                branch: request.branch, source: .local, error: nil)
        }
        var switchedStatus = try Load.checkoutStatus()
        switchedStatus.currentBranch = "feature/t11"
        let statusAfterSwitch = switchedStatus
        client.on(CheckoutStatusRequest.self) { _ in statusAfterSwitch }

        #expect(await extras.switchBranch(" feature/t11 "))
        let switchRequest = try #require(client.requests(CheckoutSwitchBranchRequest.self).last)
        #expect(switchRequest.branch == "feature/t11")
        #expect(extras.currentBranch == "feature/t11")
        #expect(extras.isSwitchingBranch == false)
    }

    @Test func switchingReportsARejectedBranch() async throws {
        let client = FakeDaemonClient()
        let checkout = CheckoutStore(workspace: try workspace(), client: client)
        let store = GitExtrasStore(client: client)
        store.update(serverInfo: try serverInfo())
        let extras = store.workspace(for: checkout)
        client.on(CheckoutSwitchBranchRequest.self) { request in
            CheckoutSwitchBranchRequest.Response(
                requestId: request.requestId, cwd: request.cwd, success: false,
                branch: request.branch, source: nil,
                error: CheckoutError(code: .unknown("UNKNOWN"), message: "dirty working tree"))
        }

        #expect(await extras.switchBranch("main") == false)
        #expect(extras.actionError == "dirty working tree")
    }

    // MARK: PR badge

    @Test func prStatusKeepsTheAuthStateAndBuildsABadge() async throws {
        let client = FakeDaemonClient()
        let checkout = CheckoutStore(workspace: try workspace(), client: client)
        let store = GitExtrasStore(client: client)
        store.update(serverInfo: try serverInfo())
        let extras = store.workspace(for: checkout)
        let payload = try prPayload(cwd: checkout.cwd)
        client.on(CheckoutPrStatusRequest.self) { _ in payload }

        await extras.loadPrStatus()

        #expect(extras.prError == nil)
        #expect(extras.prAuthState == .authenticated)
        let badge = try #require(extras.prBadge)
        #expect(badge.number == 12)
        #expect(badge.title == "Fixture PR")
        #expect(badge.checks == .passing)
        #expect(badge.isOpen)
        #expect(badge.isActionable)
    }

    // MARK: Live files

    @Test func liveFileWatchAppliesPushedVersionsAndReleases() async throws {
        let client = FakeDaemonClient()
        let checkout = CheckoutStore(workspace: try workspace(), client: client)
        let store = GitExtrasStore(client: client)
        store.update(serverInfo: try serverInfo())
        let extras = store.workspace(for: checkout)
        let subscribed = try JSONDecoder().decode(
            SessionPayloadEnvelope<FileSubscribeRequest.Response>.self,
            from: Fixture.data("fs_file_subscribe_response", in: "git-extras")
        ).payload
        client.on(FileSubscribeRequest.self) { _ in subscribed }

        await extras.watchFile("README.md")

        let request = try #require(client.requests(FileSubscribeRequest.self).last)
        #expect(request.cwd == checkout.cwd)
        #expect(request.path == "README.md")
        #expect(extras.filePhase == .ready)
        #expect(extras.watchedFile?.size == 29)

        let updateData = try Fixture.data("fs_file_update_00", in: "git-extras")
        store.handle(messageType: "fs.file.update", raw: updateData)
        #expect(extras.watchedFile?.size == 42)

        let updateText = try #require(String(data: updateData, encoding: .utf8))
        let foreignRaw = Data(
            updateText.replacingOccurrences(
                of: subscribed.subscriptionId, with: "someone-else"
            ).utf8)
        store.handle(messageType: "fs.file.update", raw: foreignRaw)
        #expect(extras.watchedFile?.size == 42, "another subscription's update is ignored")

        await store.close(checkout.workspaceId)
        let release = try #require(client.requests(SubscriptionReleaseRequest.self).last)
        #expect(release.subscriptionId == subscribed.subscriptionId)
    }

    @Test func withoutTheFileFeatureWatchingFallsBackToAOneShotRead() async throws {
        let client = FakeDaemonClient()
        let checkout = CheckoutStore(workspace: try workspace(), client: client)
        let store = GitExtrasStore(client: client)
        store.update(serverInfo: try serverInfo(files: false))
        let extras = store.workspace(for: checkout)
        client.on(FileExplorerRequest.self) { _ in try Load.fileRead() }

        await extras.watchFile("convert.py")

        #expect(client.requests(FileSubscribeRequest.self).isEmpty)
        #expect(extras.filePhase == .ready)
        #expect(extras.watchedFile?.path == "convert.py")
        #expect(extras.fileError == nil)
    }
}
