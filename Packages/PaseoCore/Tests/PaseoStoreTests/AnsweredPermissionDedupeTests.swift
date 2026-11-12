import Foundation
import Testing

@testable import PaseoStore

// G19 review: the store keeps one confirmed line per request id.
@Suite @MainActor
struct AnsweredPermissionDedupeTests {
    private func makeStore() -> ConversationStore {
        ConversationStore(agentId: "agent-1")
    }

    @Test("records once per request id")
    func recordsOnce() {
        let store = makeStore()
        store.recordAnsweredPermission(AnsweredPermission(id: "r1", line: "Allowed: Bash"))
        store.recordAnsweredPermission(AnsweredPermission(id: "r1", line: "Allowed: Bash"))
        #expect(store.permissionResolvedLines.count == 1)
        #expect(store.permissionResolvedLines[0].line == "Allowed: Bash")
    }

    @Test("keeps one line per request")
    func keepsOneLinePerRequest() {
        let store = makeStore()
        store.recordAnsweredPermission(AnsweredPermission(id: "r1", line: "Allowed: Bash"))
        store.recordAnsweredPermission(AnsweredPermission(id: "r2", line: "Denied"))
        #expect(store.permissionResolvedLines.map(\.id) == ["r1", "r2"])
    }
}
