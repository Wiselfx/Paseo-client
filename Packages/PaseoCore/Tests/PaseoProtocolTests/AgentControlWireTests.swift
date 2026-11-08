import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

/// Decodes the agent-control fixtures captured from a real daemon (`Tools/capture-agent-control.mjs`)
/// and pins the wire shapes the stores depend on.
@Suite
struct AgentControlWireTests {
    private struct FetchAgentPayload: Decodable {
        var agent: AgentSnapshot
    }

    private func payload<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<T>.self, from: Fixture.agentControl(name)
        ).payload
    }

    private func messageJSON<R: PaseoRequest>(_ request: R) throws -> [String: Any] {
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["message"] as? [String: Any])
    }

    // MARK: Permissions

    @Test func permissionRequestEventDecodes() throws {
        let event = try payload("permission_request_question", as: AgentPermissionRequestEvent.self)
        #expect(!event.agentId.isEmpty)
        let request = event.request
        #expect(!request.id.isEmpty)
        #expect(request.provider == "omp")
        #expect(request.name == "OMP select")
        #expect(request.kind == .question)
        #expect(request.title?.contains("Allow tool: bash") == true)
        #expect(request.actions == nil, "question-style approvals carry no action buttons")
        // The question form is provider input, not a typed field.
        let questions = try #require(request.input?["questions"]?.arrayValue)
        #expect(questions.count == 1)
        #expect(request.metadata?["extensionUiMethod"]?.stringValue == "select")
    }

    @Test func pendingPermissionsInASnapshotAreTyped() throws {
        let snapshot = try payload("fetch_agent_with_pending_permission_response", as: FetchAgentPayload.self)
        #expect(snapshot.agent.pendingPermissions.count == 1)
        let request = try #require(snapshot.agent.permissionRequests.first)
        #expect(request.kind == .question)
        #expect(request.provider == "omp")
        #expect(request.input?["questions"] != nil)
    }

    @Test func permissionResolutionsDecode() throws {
        let allow = try payload("permission_resolved_allow", as: AgentPermissionResolvedEvent.self)
        #expect(allow.resolution == .allowing())
        #expect(!allow.requestId.isEmpty)

        let deny = try payload("permission_resolved_deny", as: AgentPermissionResolvedEvent.self)
        #expect(
            deny.resolution
                == .deny(selectedActionId: nil, message: "Denied by fixture capture", interrupt: nil))
    }

    @Test func respondingEncodesThePermissionIdAsRequestId() throws {
        let request = RespondToAgentPermissionRequest(
            agentId: "agent-1", permissionRequestId: "perm-9", response: .allowing())
        let message = try messageJSON(request)
        #expect(message["type"] as? String == "agent_permission_response")
        // The wire `requestId` is the permission id, never an RPC correlation id.
        #expect(message["requestId"] as? String == "perm-9")
        #expect(message["agentId"] as? String == "agent-1")
        let response = try #require(message["response"] as? [String: Any])
        #expect(response["behavior"] as? String == "allow")
    }

    @Test func denyEncodesMessageAndInterrupt() throws {
        let request = RespondToAgentPermissionRequest(
            agentId: "agent-1", permissionRequestId: "perm-9",
            response: .denying(message: "no thanks", interrupt: true))
        let message = try messageJSON(request)
        let response = try #require(message["response"] as? [String: Any])
        #expect(response["behavior"] as? String == "deny")
        #expect(response["message"] as? String == "no thanks")
        #expect(response["interrupt"] as? Bool == true)
    }

    @Test func unknownPermissionKindsAndBehaviorsDoNotThrow() throws {
        let request = try JSONDecoder().decode(
            AgentPermissionRequest.self,
            from: Data(
                #"{"id":"p","provider":"x","name":"n","kind":"sandbox","actions":[{"id":"a","label":"Go","behavior":"maybe"}]}"#
                    .utf8))
        #expect(request.kind == .unknown("sandbox"))
        let action = try #require(request.actions?.first)
        #expect(action.behavior == .unknown("maybe"))

        let resolution = try JSONDecoder().decode(
            AgentPermissionResponse.self,
            from: Data(#"{"behavior":"defer","reason":"later"}"#.utf8))
        guard case .unknown(let behavior, let raw) = resolution else {
            Issue.record("expected an unknown resolution, got \(resolution)")
            return
        }
        #expect(behavior == "defer")
        #expect(raw["reason"]?.stringValue == "later")
    }

    // MARK: Creation and settings

    @Test func createAgentStatusDecodes() throws {
        let response = try payload("create_agent_response", as: CreateAgentRequest.Response.self)
        #expect(response.status == "agent_created")
        let agent = try #require(response.agent)
        #expect(agent.provider == "omp")
        #expect(agent.cwd == "/tmp/fixture-sandbox")
        #expect(agent.model == "opencode-go/deepseek-v4.1-flash")
        #expect(agent.workspaceId?.hasPrefix("wks_") == true)
        #expect(agent.currentModeId == "ask")
        #expect(agent.id == response.agentId)
    }

    @Test func createAgentFailureDecodes() throws {
        let json = #"""
            {"type":"session","message":{"type":"status","payload":{
              "status":"agent_create_failed","requestId":"r1","error":"unknown branch","errorCode":"unknown_branch"}}}
            """#
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<CreateAgentRequest.Response>.self, from: Data(json.utf8)
        ).payload
        #expect(response.status == "agent_create_failed")
        #expect(response.agent == nil)
        #expect(response.error == "unknown branch")
        #expect(response.errorCode == "unknown_branch")
    }

    @Test func actionResponsesCarryProviderNotices() throws {
        let response = try payload("set_agent_mode_response", as: AgentActionResponse.self)
        #expect(response.accepted)
        #expect(response.error == nil)
        let notice = try #require(response.notice)
        #expect(notice.level == .warning)
        #expect(notice.message.contains("current turn"))
    }

    @Test func clearingTheModelOrThinkingEncodesNullNotOmitted() throws {
        let model = try messageJSON(SetAgentModelRequest(agentId: "a", modelId: nil))
        #expect(model["modelId"] is NSNull, "the schema is nullable, so the key must be present")
        let thinking = try messageJSON(SetAgentThinkingRequest(agentId: "a", thinkingOptionId: nil))
        #expect(thinking["thinkingOptionId"] is NSNull)
        let set = try messageJSON(SetAgentThinkingRequest(agentId: "a", thinkingOptionId: "low"))
        #expect(set["thinkingOptionId"] as? String == "low")
    }

    @Test func archiveAndClearAttentionResponsesDecode() throws {
        let archived = try payload("archive_agent_response", as: ArchiveAgentRequest.Response.self)
        #expect(!archived.agentId.isEmpty)
        #expect(!archived.archivedAt.isEmpty)

        let cleared = try payload(
            "clear_agent_attention_response", as: ClearAgentAttentionRequest.Response.self)
        #expect(cleared.agents.count == 1)
        #expect(cleared.agents.first?.requiresAttention != true)
    }

    @Test func agentUpdatesCarryThinkingLevels() throws {
        let update = try payload("agent_update_created", as: AgentUpdate.self)
        guard case .upsert(let agent, _) = update else {
            Issue.record("expected an upsert, got \(update)")
            return
        }
        #expect(agent.thinkingOptionId == "low")
        #expect(agent.effectiveThinkingOptionId == "low")
        #expect(agent.attention == nil)
    }

    @Test func attentionIsTypedAndRespectsTheUnreadFlag() throws {
        let update = try payload("agent_update_created", as: AgentUpdate.self)
        guard case .upsert(var snapshot, _) = update else {
            Issue.record("expected an upsert")
            return
        }
        snapshot.requiresAttention = true
        snapshot.attentionReason = "permission"
        #expect(snapshot.attention == .permission)
        snapshot.attentionReason = "finished"
        #expect(snapshot.attention == .finished)
        snapshot.attentionReason = "wat"
        #expect(snapshot.attention == .unknown("wat"))
        snapshot.requiresAttention = false
        #expect(snapshot.attention == nil, "the flag, not the reason, decides unread")
        snapshot.requiresAttention = nil
        snapshot.attentionReason = "error"
        #expect(snapshot.attention == .error, "older daemons without the flag still map the reason")
        #expect([snapshot].needingAttention.count == 1)
    }

    // MARK: Provider catalogue

    @Test func providerSnapshotDecodesModelsModesAndThinking() throws {
        let response = try payload(
            "providers_snapshot_response", as: GetProvidersSnapshotRequest.Response.self)
        #expect(response.entries.count == 8)
        let omp = try #require(response.entries.first { $0.provider == "omp" })
        #expect(omp.status == .ready)
        #expect(omp.enabled)
        #expect(omp.isAvailable)
        #expect(omp.modes?.map(\.id) == ["full", "write", "ask"])
        #expect(omp.defaultModeId == "full")
        #expect(omp.models?.count == 7)

        let deepseek = try #require(omp.models?.first { $0.id == "opencode-go/deepseek-v4.1-flash" })
        #expect(deepseek.defaultThinkingOptionId == "minimal")
        #expect(deepseek.thinkingOptions?.map(\.id) == ["auto", "minimal", "low", "high", "max"])
        #expect(deepseek.thinkingOptions?.first { $0.isDefault == true }?.id == "minimal")

        let codex = try #require(response.entries.first { $0.provider == "codex" })
        #expect(codex.status == .unavailable)
        #expect(!codex.isAvailable)
    }

    @Test func legacyCatalogRPCsDecode() throws {
        let models = try payload(
            "list_provider_models_response", as: ListProviderModelsRequest.Response.self)
        #expect(models.provider == "omp")
        #expect(models.models?.contains { $0.id == "opencode-go/deepseek-v4.1-flash" } == true)

        let modes = try payload("list_provider_modes_response", as: ListProviderModesRequest.Response.self)
        #expect(modes.modes?.map(\.id) == ["full", "write", "ask"])
    }
}

extension JSONValue {
    fileprivate var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}
