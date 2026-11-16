import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// The forge setup banner reads the payload's auth state, which arrives even when there is
/// no PR (GitHub CLI missing), so `CheckoutStore` must keep it next to `prStatus`.
@MainActor
struct CheckoutPrAuthStateTests {
    private func workspace() throws -> WorkspaceDescriptor {
        var workspace = try Load.sandboxWorkspace()
        workspace.workspaceDirectory = "/tmp/fixture-git/scratch-repo"
        workspace.projectRootPath = "/tmp/fixture-git/scratch-repo"
        return workspace
    }

    private func payload(cwd: String, authState: String, withPR: Bool) throws -> CheckoutPrStatusPayload {
        let status = withPR
            ? #"{"forge":"github","number":3,"url":"https://example.test/pr/3","title":"Fixture","state":"OPEN","baseRefName":"main","headRefName":"feature","isMerged":false}"#
            : "null"
        let json = """
            {"cwd":"\(cwd)","status":\(status),"githubFeaturesEnabled":true,
             "authState":"\(authState)","forge":"github","error":null,"requestId":"pr"}
            """
        return try JSONDecoder().decode(CheckoutPrStatusPayload.self, from: Data(json.utf8))
    }

    @Test func cliMissingIsKeptWithoutAPR() async throws {
        let client = FakeDaemonClient()
        let store = CheckoutStore(workspace: try workspace(), client: client)
        let reply = try payload(cwd: store.cwd, authState: "cli_missing", withPR: false)
        client.on(CheckoutPrStatusRequest.self) { _ in reply }

        await store.loadPrStatus()

        #expect(store.prStatus == nil)
        #expect(store.prAuthState == .cliMissing)
    }

    @Test func authenticatedRidesAlongTheBadge() async throws {
        let client = FakeDaemonClient()
        let store = CheckoutStore(workspace: try workspace(), client: client)
        let reply = try payload(cwd: store.cwd, authState: "authenticated", withPR: true)
        client.on(CheckoutPrStatusRequest.self) { _ in reply }

        await store.loadPrStatus()

        #expect(store.prStatus?.number == 3)
        #expect(store.prAuthState == .authenticated)
    }
}
