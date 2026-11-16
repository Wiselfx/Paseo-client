import Foundation
import PaseoKit
import Testing

@testable import PaseoStore

// Phase D G16: the `new-agent` deep-link route. Synthetic ids only.
@Suite struct DeepLinkNewAgentTests {
    @Test("bare new-agent route has no server or workspace")
    func bareRoute() {
        #expect(DeepLink(string: "paseo://new-agent") == .newAgent(serverID: nil, workspaceID: nil))
    }

    @Test("host new-agent route carries the server")
    func hostRoute() {
        #expect(
            DeepLink(string: "paseo://h/srv_FIXTURE/new-agent")
                == .newAgent(serverID: "srv_FIXTURE", workspaceID: nil))
    }

    @Test("workspace query is optional and strict")
    func workspaceQuery() {
        #expect(
            DeepLink(string: "paseo://h/srv_FIXTURE/new-agent?workspace=workspace-1")
                == .newAgent(serverID: "srv_FIXTURE", workspaceID: "workspace-1"))
        #expect(DeepLink(string: "paseo://h/srv_FIXTURE/new-agent/extra") == nil)
    }

    @Test("new-agent navigates inside the shell")
    func navigates() {
        let link = DeepLink(string: "paseo://new-agent")
        #expect(link?.isNavigation == true)
        #expect(link?.targetServerID == nil)
    }
}
