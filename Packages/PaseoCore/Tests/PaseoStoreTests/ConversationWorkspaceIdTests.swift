import Foundation
import PaseoProtocol
import Testing

@testable import PaseoStore

/// `ConversationStore.workspaceId` follows `agent` and is written only when it changes, so the shell
/// (which reads it for the sidebar and the panel) is not invalidated by every agent update (W1).
@Suite @MainActor
struct ConversationWorkspaceIdTests {
    private static func snapshot(workspaceId: String?, updatedAt: String) throws -> AgentSnapshot {
        let workspace = workspaceId.map { ",\"workspaceId\":\"\($0)\"" } ?? ""
        let json = #"""
            {"id":"a1","provider":"pi","cwd":"/tmp/fixture-sandbox","status":"idle",
             "createdAt":"2026-11-08T20:00:00.000Z","updatedAt":"\#(updatedAt)",
             "availableModes":[],"pendingPermissions":[],"requiresAttention":false\#(workspace)}
            """#
        return try JSONDecoder().decode(AgentSnapshot.self, from: Data(json.utf8))
    }

    @Test func followsTheAgentsWorkspace() throws {
        let store = ConversationStore(agentId: "a1", client: FakeDaemonClient())
        #expect(store.workspaceId == nil)
        store.agent = try Self.snapshot(workspaceId: "w1", updatedAt: "2026-11-08T20:00:01.000Z")
        #expect(store.workspaceId == "w1")
        store.agent = try Self.snapshot(workspaceId: "w1", updatedAt: "2026-11-08T20:00:02.000Z")
        #expect(store.workspaceId == "w1")
        store.agent = try Self.snapshot(workspaceId: "w2", updatedAt: "2026-11-08T20:00:03.000Z")
        #expect(store.workspaceId == "w2")
        store.agent = nil
        #expect(store.workspaceId == nil)
    }
}
