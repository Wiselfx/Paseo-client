import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// Stash & switch: the store side of upstream's `hooks/use-branch-switcher.ts`
/// (`Upstream: packages/app/src/hooks/use-branch-switcher.ts:96-153`,
/// `packages/app/src/git/branch-switcher-operations.ts:9-11`).
@Suite @MainActor
struct StashStoreTests {
    private func extras(client: FakeDaemonClient) throws -> WorkspaceGitExtras {
        var workspace = try Load.sandboxWorkspace()
        workspace.workspaceDirectory = "/tmp/fixture-sandbox"
        workspace.projectRootPath = "/tmp/fixture-sandbox"
        let checkout = CheckoutStore(workspace: workspace, client: client)
        return WorkspaceGitExtras(
            workspaceId: workspace.id, cwd: workspace.cwd, checkout: checkout, client: client)
    }

    nonisolated private func stashList(_ entries: [StashEntry]) -> StashListRequest.Response {
        StashListRequest.Response(
            requestId: "r", cwd: "/tmp/fixture-sandbox", entries: entries, error: nil)
    }

    nonisolated private func saveResponse(success: Bool, message: String? = nil) -> StashSaveRequest.Response {
        StashSaveRequest.Response(
            requestId: "r", cwd: "/tmp/fixture-sandbox", success: success,
            error: message.map { CheckoutError(code: .unknownCode, message: $0) })
    }

    nonisolated private func switchResponse(success: Bool, branch: String, message: String? = nil)
        -> CheckoutSwitchBranchRequest.Response
    {
        CheckoutSwitchBranchRequest.Response(
            requestId: "r", cwd: "/tmp/fixture-sandbox", success: success, branch: branch,
            source: .local,
            error: message.map { CheckoutError(code: .unknownCode, message: $0) })
    }

    @Test func loadPaseoStashesAsksForPaseoStashesOnly() async throws {
        let client = FakeDaemonClient()
        client.onSend(StashListRequest.self) { request in
            #expect(request.paseoOnly == true)
            return self.stashList([
                StashEntry(index: 0, message: "paseo-auto-stash: old", branch: "old", isPaseo: true)
            ])
        }
        let extras = try extras(client: client)

        await extras.loadPaseoStashes()

        #expect(extras.paseoStashes.count == 1)
        #expect(extras.stashError == nil)
        #expect(extras.paseoStash(forBranch: "old")?.index == 0)
        #expect(extras.paseoStash(forBranch: "other") == nil)
    }

    @Test func stashAndSwitchSavesUnderTheCurrentBranchThenSwitches() async throws {
        let client = FakeDaemonClient()
        client.onSend(StashSaveRequest.self) { _ in self.saveResponse(success: true) }
        client.onSend(StashListRequest.self) { _ in self.stashList([]) }
        client.onSend(CheckoutSwitchBranchRequest.self) { request in
            self.switchResponse(success: true, branch: request.branch)
        }
        let extras = try extras(client: client)
        let current = extras.currentBranch

        let switched = await extras.stashAndSwitch(to: "feature/t11")

        #expect(switched)
        #expect(extras.actionError == nil)
        let save = try #require(client.requests(StashSaveRequest.self).first)
        #expect(save.branch == current, "the stash is tagged with the branch being left")
        let order = client.requests.compactMap { request -> String? in
            switch request {
            case is StashSaveRequest: return "save"
            case is CheckoutSwitchBranchRequest: return "switch"
            default: return nil
            }
        }
        #expect(order == ["save", "switch"])
    }

    @Test func aDirtyTreeIsReportedAsBlockedAndKeepsTheDaemonsWords() async throws {
        let client = FakeDaemonClient()
        let dirty = "error: Your local changes would be overwritten. Uncommitted changes."
        client.onSend(CheckoutSwitchBranchRequest.self) { _ in
            self.switchResponse(success: false, branch: "feature/t11", message: dirty)
        }
        let extras = try extras(client: client)

        let switched = await extras.switchBranch("feature/t11")

        #expect(!switched)
        #expect(extras.lastSwitchBlockedByChanges)
        #expect(extras.actionError == dirty)
    }

    @Test func otherSwitchFailuresDoNotOfferTheStashDialog() async throws {
        let client = FakeDaemonClient()
        client.onSend(CheckoutSwitchBranchRequest.self) { _ in
            self.switchResponse(success: false, branch: "nope", message: "No such branch")
        }
        let extras = try extras(client: client)

        _ = await extras.switchBranch("nope")

        #expect(!extras.lastSwitchBlockedByChanges)
        #expect(extras.actionError == "No such branch")
    }

    @Test func stashAndSwitchStopsWhenTheStashFails() async throws {
        let client = FakeDaemonClient()
        client.onSend(StashSaveRequest.self) { _ in
            self.saveResponse(success: false, message: "Failed to stash changes")
        }
        let extras = try extras(client: client)

        let switched = await extras.stashAndSwitch(to: "feature/t11")

        #expect(!switched)
        #expect(extras.actionError == "Failed to stash changes")
        #expect(client.requests(CheckoutSwitchBranchRequest.self).isEmpty)
    }

    @Test func popRestoresByIndexAndRefreshesTheList() async throws {
        let client = FakeDaemonClient()
        client.onSend(StashPopRequest.self) { request in
            #expect(request.stashIndex == 3)
            return StashPopRequest.Response(
                requestId: "r", cwd: "/tmp/fixture-sandbox", success: true, error: nil)
        }
        client.onSend(StashListRequest.self) { _ in self.stashList([]) }
        let extras = try extras(client: client)

        let restored = await extras.popStash(index: 3)

        #expect(restored)
        #expect(extras.paseoStashes.isEmpty)
        #expect(client.requests(StashListRequest.self).count == 1)
    }

    @Test func popFailureKeepsTheDaemonsError() async throws {
        let client = FakeDaemonClient()
        client.onSend(StashPopRequest.self) { _ in
            StashPopRequest.Response(
                requestId: "r", cwd: "/tmp/fixture-sandbox", success: false,
                error: CheckoutError(code: .unknownCode, message: "conflict in Stash.swift"))
        }
        let extras = try extras(client: client)

        let restored = await extras.popStash(index: 0)

        #expect(!restored)
        #expect(extras.actionError == "conflict in Stash.swift")
    }
}
