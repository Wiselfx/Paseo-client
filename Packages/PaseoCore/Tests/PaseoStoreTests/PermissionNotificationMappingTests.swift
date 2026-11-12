import Foundation
import Testing

@testable import PaseoProtocol
@testable import PaseoStore

// Phase D G19: notification actions appear only on simple permission requests.
struct PermissionNotificationMappingTests {
    private func action(
        id: String, label: String, behavior: AgentPermissionAction.Behavior
    ) -> AgentPermissionAction {
        AgentPermissionAction(
            id: id, label: label, behavior: behavior, variant: nil, intent: nil)
    }

    private func request(
        kind: AgentPermissionRequest.Kind = .tool,
        actions: [AgentPermissionAction]? = nil,
        input: JSONValue? = nil
    ) -> AgentPermissionRequest {
        AgentPermissionRequest(
            id: "req-1", provider: "test", name: "Bash", kind: kind, title: nil,
            description: nil, input: input, detail: nil, suggestions: nil,
            actions: actions, metadata: nil)
    }

    private var allowDeny: [AgentPermissionAction] {
        [action(id: "a-allow", label: "Allow", behavior: .allow),
         action(id: "a-deny", label: "Deny", behavior: .deny)]
    }

    @Test("a simple tool request maps to its buttons")
    func simpleMaps() {
        let mapped = PermissionNotificationMapping.actions(
            for: request(actions: allowDeny, input: .object(["command": .string("ls")])))
        #expect(mapped?.allowActionId == "a-allow")
        #expect(mapped?.denyActionId == "a-deny")
        #expect(mapped?.allowResponse == .allowing(selectedActionId: "a-allow"))
        #expect(mapped?.denyResponse == .denying(selectedActionId: "a-deny"))
    }

    @Test("plans, questions and modes never map")
    func onlyToolKindMaps() {
        for kind in [AgentPermissionRequest.Kind.plan, .question, .mode] as [AgentPermissionRequest.Kind] {
            #expect(PermissionNotificationMapping.actions(
                for: request(kind: kind, actions: allowDeny)) == nil)
        }
    }

    @Test("unknown behaviors do not count as allow or deny")
    func unknownBehaviorsDoNotMap() {
        #expect(PermissionNotificationMapping.actions(for: request(actions: [
            action(id: "a-x", label: "Maybe", behavior: .unknown("maybe")),
            action(id: "a-deny", label: "Deny", behavior: .deny),
        ])) == nil)
        #expect(PermissionNotificationMapping.actions(for: request(actions: [])) == nil)
        #expect(PermissionNotificationMapping.actions(for: request(actions: nil)) == nil)
    }

    @Test("question options never map")
    func questionOptionsDoNotMap() {
        #expect(PermissionNotificationMapping.actions(for: request(
            actions: allowDeny,
            input: .object(["questions": .array([.object(["question": .string("Pick")])])]))) == nil)
    }

    @Test("free-text input never maps")
    func freeTextInputDoesNotMap() {
        let typed = request(
            actions: allowDeny, input: .object(["message": .string("tell me why")]))
        #expect(PermissionNotificationMapping.actions(for: typed) == nil)
        let blank = request(
            actions: allowDeny, input: .object(["message": .string("   ")]))
        #expect(PermissionNotificationMapping.actions(for: blank) != nil)
    }
}
