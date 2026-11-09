import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// M8c: provider `AgentFeature`s — decode tolerance (fixtures first), optimistic set with
/// rollback. The decode fixture is the sandbox agent captured from the fixture daemon.
@MainActor
struct ConversationFeatureTests {
    private func sandboxSnapshot() throws -> AgentSnapshot {
        try JSONDecoder().decode(
            AgentSnapshot.self,
            from: Fixture.data("sandbox_agent_snapshot", in: "agent-features"))
    }

    private func inlineSnapshot(featuresJSON: String) throws -> AgentSnapshot {
        let json = """
        {
          "id": "agent-1", "provider": "opencode", "cwd": "/tmp/fixture-sandbox",
          "model": "opencode/inkling-2-small-free",
          "createdAt": "2026-11-08T21:02:50.312Z", "updatedAt": "2026-11-09T07:18:02.729Z",
          "lastUserMessageAt": null, "status": "idle", "activeTurn": null,
          "currentModeId": "build", "availableModes": [],
          "pendingPermissions": [], "labels": {},
          "features": \(featuresJSON)
        }
        """
        return try JSONDecoder().decode(AgentSnapshot.self, from: Data(json.utf8))
    }

    private func makeStore(snapshot: AgentSnapshot) -> (ConversationStore, FakeDaemonClient) {
        let client = FakeDaemonClient()
        let store = ConversationStore(agentId: snapshot.id, client: client)
        store.applyAgent(snapshot)
        return (store, client)
    }

    private nonisolated static func actionResponse(
        accepted: Bool = true, error: String? = nil, noticeMessage: String? = nil
    ) throws -> AgentActionResponse {
        let notice = noticeMessage.map {
            """
            {"type":"info","message":"\($0)"}
            """
        } ?? "null"
        var errorJSON = "null"
        if let error {
            let escaped = error
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            errorJSON = "\"\(escaped)\""
        }
        let json = """
        {"requestId":"r","agentId":"agent-1","accepted":\(accepted),"error":\(errorJSON),"notice":\(notice)}
        """
        return try JSONDecoder().decode(AgentActionResponse.self, from: Data(json.utf8))
    }

    // MARK: Decoding

    @Test func fixtureDecodesSandboxFeatures() throws {
        let snapshot = try sandboxSnapshot()
        #expect(snapshot.id == "1c51ee58-765c-4f8d-bf27-7009338b361e")
        #expect(snapshot.features?.count == 1)
        if case .toggle(let toggle) = snapshot.features?.first {
            #expect(toggle.id == "auto_accept")
            #expect(toggle.label == "Auto-accept")
            #expect(toggle.value == false)
        } else {
            Issue.record("expected a toggle feature")
        }
    }

    @Test func selectFeatureDecodes() throws {
        let snapshot = try inlineSnapshot(
            featuresJSON: #"""
            [{"type":"select","id":"service_tier","label":"Speed","description":"Request speed",
              "value":"Normal","options":[
                {"id":"Normal","label":"Normal"},
                {"id":"Fast","label":"Fast","description":"Lower latency","isDefault":true},
                {"id":"Ultrafast","label":"Ultrafast"}]}]
            """#)
        #expect(snapshot.features?.count == 1)
        if case .select(let select) = snapshot.features?.first {
            #expect(select.id == "service_tier")
            #expect(select.value == "Normal")
            #expect(select.options.map(\.id) == ["Normal", "Fast", "Ultrafast"])
            #expect(select.options[1].isDefault == true)
            #expect(select.options[1].description == "Lower latency")
        } else {
            Issue.record("expected a select feature")
        }
    }

    @Test func malformedFeaturesDecodeAsUnknown() throws {
        let snapshot = try inlineSnapshot(
            featuresJSON: #"""
            [{"type":"toggle","id":"auto_accept","label":"Auto-accept","value":"yes"},
             {"type":"slider","id":"wisdom","label":"Wisdom"},
             {"type":"toggle","id":"fast_mode","label":"Fast","value":true}]
            """#)
        #expect(snapshot.features?.count == 3)
        guard let features = snapshot.features else {
            Issue.record("expected features")
            return
        }
        #expect(features[0].id == "") // .unknown: value was not a bool
        #expect(features[1].id == "") // .unknown: newer kind
        #expect(features[2].id == "fast_mode") // the one good feature survives
    }

    @Test func missingTypePropertyDecodesAsUnknown() throws {
        let snapshot = try inlineSnapshot(
            featuresJSON: #"[{"id":"x","label":"No type key"}]"#)
        #expect(snapshot.features?.count == 1)
        #expect(snapshot.features?.first?.id == "") // unknown, not a crash
    }

    // MARK: setFeature — optimistic with rollback

    @Test func toggleFlipAppliesOptimisticallyAndSettles() async throws {
        let snapshot = try sandboxSnapshot()
        let (store, client) = makeStore(snapshot: snapshot)
        let gate = Gate()
        client.on(SetAgentFeatureRequest.self) { _ in
            await gate.wait()
            return try Self.actionResponse(accepted: true, noticeMessage: "applies next turn")
        }

        let sending = Task { await store.setFeatureToggle(featureId: "auto_accept", value: true) }

        // Before the daemon answers, the toggle is already flipped: the optimistic update is
        // applied synchronously, before the RPC suspends at the gate.
        try? await Task.sleep(for: .milliseconds(50))
        let flipped = store.agent?.features.flatMap { features in
            features.compactMap { feature -> Bool? in
                if case .toggle(let toggle) = feature, toggle.id == "auto_accept" { return toggle.value }
                return nil
            }.first
        }
        #expect(flipped == true)

        await gate.open()
        await sending.value
        #expect(store.actionError == nil)
        #expect(store.lastNotice?.message == "applies next turn")
        #expect(client.requests(SetAgentFeatureRequest.self).count == 1)
        let sent = try #require(client.requests(SetAgentFeatureRequest.self).first)
        #expect(sent.featureId == "auto_accept")
        #expect(sent.value == .bool(true))
    }

    @Test func setFeatureRollsBackOnRejectedResponse() async throws {
        let snapshot = try sandboxSnapshot()
        let (store, client) = makeStore(snapshot: snapshot)
        client.on(SetAgentFeatureRequest.self) { _ in
            try Self.actionResponse(accepted: false, error: "not allowed here")
        }

        await store.setFeatureToggle(featureId: "auto_accept", value: true)

        let value = store.agent?.features?.compactMap { feature -> Bool? in
            if case .toggle(let toggle) = feature { return toggle.value }
            return nil
        }.first
        #expect(value == false)
        #expect(store.actionError == "not allowed here")
    }

    @Test func setFeatureRollsBackOnThrow() async throws {
        struct Boom: Error {}
        let snapshot = try sandboxSnapshot()
        let (store, client) = makeStore(snapshot: snapshot)
        client.on(SetAgentFeatureRequest.self) { _ in throw Boom() }

        await store.setFeatureToggle(featureId: "auto_accept", value: true)

        let value = store.agent?.features?.compactMap { feature -> Bool? in
            if case .toggle(let toggle) = feature { return toggle.value }
            return nil
        }.first
        #expect(value == false)
        #expect(store.actionError != nil)
    }

    @Test func selectRejectsUnknownOptionWithoutSending() async throws {
        let snapshot = try inlineSnapshot(
            featuresJSON: #"""
            [{"type":"select","id":"service_tier","label":"Speed","value":"Normal",
              "options":[{"id":"Normal","label":"Normal"},{"id":"Fast","label":"Fast"}]}]
            """#)
        let (store, client) = makeStore(snapshot: snapshot)

        await store.setFeatureSelection(featureId: "service_tier", value: "Ultrafast")

        #expect(store.actionError == "That value doesn't fit this feature.")
        #expect(client.requests(SetAgentFeatureRequest.self).isEmpty)
        if case .select(let select) = store.agent?.features?.first {
            #expect(select.value == "Normal")
        } else {
            Issue.record("expected select feature")
        }
    }

    @Test func selectOptionIsAppliedAndSent() async throws {
        let snapshot = try inlineSnapshot(
            featuresJSON: #"""
            [{"type":"select","id":"service_tier","label":"Speed","value":"Normal",
              "options":[{"id":"Normal","label":"Normal"},{"id":"Fast","label":"Fast"}]}]
            """#)
        let (store, client) = makeStore(snapshot: snapshot)
        client.on(SetAgentFeatureRequest.self) { _ in try Self.actionResponse() }

        await store.setFeatureSelection(featureId: "service_tier", value: "Fast")

        #expect(store.actionError == nil)
        if case .select(let select) = store.agent?.features?.first {
            #expect(select.value == "Fast")
        } else {
            Issue.record("expected select feature")
        }
        let sent = try #require(client.requests(SetAgentFeatureRequest.self).first)
        #expect(sent.value == .string("Fast"))
    }

    @Test func clearingSelectionSendsNull() async throws {
        let snapshot = try inlineSnapshot(
            featuresJSON: #"""
            [{"type":"select","id":"service_tier","label":"Speed","value":"Fast",
              "options":[{"id":"Normal","label":"Normal"},{"id":"Fast","label":"Fast"}]}]
            """#)
        let (store, client) = makeStore(snapshot: snapshot)
        client.on(SetAgentFeatureRequest.self) { _ in try Self.actionResponse() }

        await store.setFeatureSelection(featureId: "service_tier", value: nil)

        let sent = try #require(client.requests(SetAgentFeatureRequest.self).first)
        #expect(sent.value == .null)
        if case .select(let select) = store.agent?.features?.first {
            #expect(select.value == nil)
        }
    }

    @Test func missingFeatureIsRejectedWithoutRPC() async throws {
        let snapshot = try sandboxSnapshot()
        let (store, client) = makeStore(snapshot: snapshot)

        await store.setFeatureToggle(featureId: "no_such_feature", value: true)

        #expect(store.actionError == "This agent doesn't offer that feature.")
        #expect(client.requests(SetAgentFeatureRequest.self).isEmpty)
    }
}
