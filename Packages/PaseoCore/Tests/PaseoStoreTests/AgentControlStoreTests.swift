import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// Drives the agent-control store and the conversation's agent actions with the traffic captured
/// by `Tools/capture-agent-control.mjs` (sandbox agents in /tmp/fixture-sandbox).
@Suite @MainActor
struct AgentControlStoreTests {
    private enum Fixtures {
        enum Missing: Error { case agent }

        static func payload<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
            try JSONDecoder().decode(
                SessionPayloadEnvelope<T>.self, from: Fixture.agentControl(name)
            ).payload
        }

        static func agents() throws -> FetchAgentsRequest.Response {
            try payload("fetch_agents_response", as: FetchAgentsRequest.Response.self)
        }

        static func agent() throws -> AgentSnapshot {
            guard let agent = try agents().entries.first?.agent else { throw Missing.agent }
            return agent
        }

        /// The captured agent while it was parked on a permission request.
        static func pendingSnapshot() throws -> AgentSnapshot {
            struct FetchAgentPayload: Decodable { var agent: AgentSnapshot }
            return try payload(
                "fetch_agent_with_pending_permission_response", as: FetchAgentPayload.self
            ).agent
        }

        /// The shared timeline page, stripped of its agent so it cannot overwrite the sandbox one.
        static func page() throws -> FetchAgentTimelineRequest.Response {
            var page = try Load.page()
            page.agent = nil
            page.entries = []
            page.hasOlder = false
            page.hasNewer = false
            return page
        }
    }

    /// A started session whose agent list is the captured sandbox agent.
    private func makeSession(_ client: FakeDaemonClient) async throws -> (HostSession, String) {
        let agents = try Fixtures.agents()
        let agentId = try #require(agents.entries.first?.agent.id)
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { _ in try Fixtures.page() }
        client.onSetSubscription { _ in try Load.subscription() }

        let info = try Load.serverInfo()
        client.push(.connected(info))
        let session = HostSession(client: client)
        await session.start()
        _ = await eventually { session.connection == .connected(info) }
        return (session, agentId)
    }

    /// Holds the session alive: dropping it stops the event loop that feeds the store.
    private struct OpenConversation {
        let session: HostSession
        let store: ConversationStore
    }

    private func openConversation(_ client: FakeDaemonClient) async throws -> OpenConversation {
        let (session, agentId) = try await makeSession(client)
        let store = session.conversation(for: agentId)
        _ = await eventually { store.phase == .ready }
        return OpenConversation(session: session, store: store)
    }

    // MARK: Catalogue

    @Test func catalogueLoadsProvidersModelsModesAndThinking() async throws {
        let client = FakeDaemonClient()
        let (session, _) = try await makeSession(client)
        client.onSend(GetProvidersSnapshotRequest.self) { _ in
            try Fixtures.payload("providers_snapshot_response", as: GetProvidersSnapshotRequest.Response.self)
        }

        await session.agentControl.loadCatalog(cwd: "/tmp/fixture-sandbox")

        #expect(session.agentControl.phase == .ready)
        #expect(session.agentControl.isSupported)
        #expect(session.agentControl.providers.count == 8)
        #expect(session.agentControl.readyProviders.contains { $0.provider == "omp" })
        #expect(session.agentControl.models(forProvider: "omp").count == 7)
        #expect(session.agentControl.modes(forProvider: "omp").map(\.id) == ["full", "write", "ask"])
        #expect(
            session.agentControl.thinkingOptions(
                forProvider: "omp", modelId: "opencode-go/deepseek-v4.1-flash"
            ).map(\.id) == ["auto", "minimal", "low", "high", "max"])
        #expect(session.agentControl.defaultModel(forProvider: "omp")?.id == "opencode-go/beam-free")
        #expect(client.requests(GetProvidersSnapshotRequest.self).first?.cwd == "/tmp/fixture-sandbox")
    }

    @Test func catalogueFallsBackToPerProviderRPCsWithoutTheSnapshotFeature() async throws {
        let client = FakeDaemonClient()
        var info = try Load.serverInfo()
        info.features = nil
        client.onFetchAgents { _ in try Fixtures.agents() }
        client.onFetchTimeline { _ in try Fixtures.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        client.push(.connected(info))

        let session = HostSession(client: client)
        await session.start()
        _ = await eventually { session.connection == .connected(info) }
        #expect(!session.agentControl.isSupported)

        client.onSend(ListAvailableProvidersRequest.self) { _ in
            let json = #"""
                {"requestId":"r","providers":[{"provider":"omp","available":true},
                {"provider":"codex","available":false,"error":"not installed"}],"fetchedAt":"now"}
                """#
            return try JSONDecoder().decode(
                ListAvailableProvidersRequest.Response.self, from: Data(json.utf8))
        }
        client.onSend(ListProviderModelsRequest.self) { _ in
            try Fixtures.payload("list_provider_models_response", as: ListProviderModelsRequest.Response.self)
        }
        client.onSend(ListProviderModesRequest.self) { _ in
            try Fixtures.payload("list_provider_modes_response", as: ListProviderModesRequest.Response.self)
        }

        await session.agentControl.loadCatalog(cwd: "/tmp/fixture-sandbox")

        #expect(session.agentControl.phase == .ready)
        #expect(client.requests(GetProvidersSnapshotRequest.self).isEmpty, "no snapshot RPC on old daemons")
        #expect(session.agentControl.provider("omp")?.isAvailable == true)
        #expect(session.agentControl.models(forProvider: "omp").count > 0)
        #expect(session.agentControl.modes(forProvider: "omp").count == 3)
        #expect(session.agentControl.provider("codex")?.status == .unavailable)
    }

    // MARK: Creation

    @Test func createAgentReturnsTheNewAgentId() async throws {
        let client = FakeDaemonClient()
        let (session, _) = try await makeSession(client)
        client.onSend(CreateAgentRequest.self) { _ in
            try Fixtures.payload("create_agent_response", as: CreateAgentRequest.Response.self)
        }

        let id = await session.agentControl.createAgent(
            cwd: "/tmp/fixture-sandbox", provider: "omp", model: "opencode-go/deepseek-v4.1-flash",
            modeId: "ask", thinkingOptionId: "low", prompt: "  say ready  ", title: "Probe")

        let created = try #require(client.requests(CreateAgentRequest.self).first)
        #expect(created.config.provider == "omp")
        #expect(created.config.cwd == "/tmp/fixture-sandbox")
        #expect(created.config.model == "opencode-go/deepseek-v4.1-flash")
        #expect(created.config.modeId == "ask")
        #expect(created.config.thinkingOptionId == "low")
        #expect(created.config.title == "Probe")
        #expect(created.initialPrompt == "say ready", "prompt is trimmed")
        #expect(id == (try Fixtures.agent().id))
        #expect(session.agentControl.lastCreatedAgent?.id == id)
        #expect(session.agentControl.actionError == nil)
    }

    @Test func createAgentFailureSetsActionError() async throws {
        let client = FakeDaemonClient()
        let (session, _) = try await makeSession(client)
        client.onSend(CreateAgentRequest.self) { _ in
            let json = #"""
                {"status":"agent_create_failed","requestId":"r","error":"no such workspace","errorCode":"not_found"}
                """#
            return try JSONDecoder().decode(CreateAgentRequest.Response.self, from: Data(json.utf8))
        }

        let id = await session.agentControl.createAgent(
            cwd: "/tmp/fixture-sandbox", provider: "omp", model: "m", prompt: "   ")

        #expect(id == nil)
        #expect(session.agentControl.actionError == "no such workspace")
        #expect(session.agentControl.lastCreatedAgent == nil)
        #expect(client.requests(CreateAgentRequest.self).first?.initialPrompt == nil, "blank prompt is dropped")
    }

    // MARK: Permissions

    @Test func permissionEventsReachTheOpenConversation() async throws {
        let client = FakeDaemonClient()
        let open = try await openConversation(client)
        let store = open.store

        client.push(
            .unhandled(
                messageType: "agent_permission_request",
                raw: try Fixture.agentControl("permission_request_question")))
        let arrived = await eventually { store.pendingPermissions.count == 1 }
        #expect(arrived)
        let request = try #require(store.pendingPermissions.first)
        #expect(request.kind == .question)
        #expect(request.provider == "omp")
        #expect(request.title?.contains("bash") == true)

        // A duplicate event must not stack two cards for the same request.
        client.push(
            .unhandled(
                messageType: "agent_permission_request",
                raw: try Fixture.agentControl("permission_request_question")))
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.pendingPermissions.count == 1)

        // Resolution can come from any client; it removes the card here too.
        client.push(
            .unhandled(
                messageType: "agent_permission_resolved",
                raw: try Fixture.agentControl("permission_resolved_allow")))
        let cleared = await eventually { store.pendingPermissions.isEmpty }
        #expect(cleared)
    }

    @Test func aSnapshotCarriesTypedPendingPermissions() async throws {
        let client = FakeDaemonClient()
        let open = try await openConversation(client)
        let store = open.store
        #expect(store.pendingPermissions.isEmpty)

        let snapshot = try Fixtures.pendingSnapshot()
        client.push(.agentUpdate(.upsert(snapshot, project: nil)))

        let arrived = await eventually { store.pendingPermissions.count == 1 }
        #expect(arrived)
        #expect(store.pendingPermissions.first?.kind == .question)
        #expect(store.pendingPermissions.first?.id == snapshot.pendingPermissions.first?["id"]?.stringValue)
    }

    @Test func respondingKeepsTheCardUntilTheResolutionEvent() async throws {
        let client = FakeDaemonClient()
        let open = try await openConversation(client)
        let store = open.store
        client.push(
            .unhandled(
                messageType: "agent_permission_request",
                raw: try Fixture.agentControl("permission_request_question")))
        let arrived = await eventually { store.pendingPermissions.count == 1 }
        #expect(arrived)
        let request = try #require(store.pendingPermissions.first)

        await store.respond(to: request.id, with: .denying(message: "not now", interrupt: true))

        let recorded = await eventually { !client.requests(RespondToAgentPermissionRequest.self).isEmpty }
        #expect(recorded)
        let sent = try #require(client.requests(RespondToAgentPermissionRequest.self).first)
        #expect(sent.agentId == store.agentId)
        #expect(sent.permissionRequestId == request.id)
        #expect(sent.response == .deny(selectedActionId: nil, message: "not now", interrupt: true))
        #expect(store.pendingPermissions.count == 1, "not removed until the daemon confirms")

        client.push(
            .unhandled(
                messageType: "agent_permission_resolved",
                raw: try Fixture.agentControl("permission_resolved_allow")))
        let cleared = await eventually { store.pendingPermissions.isEmpty }
        #expect(cleared)
    }

    // MARK: Settings, rename, archive

    @Test func setModeAppliesTheChangeAndSurfacesTheNotice() async throws {
        let client = FakeDaemonClient()
        let open = try await openConversation(client)
        let store = open.store
        client.onSend(SetAgentModeRequest.self) { _ in
            try Fixtures.payload("set_agent_mode_response", as: AgentActionResponse.self)
        }

        await store.setMode("write")

        #expect(client.requests(SetAgentModeRequest.self).first?.modeId == "write")
        #expect(store.agent?.currentModeId == "write")
        #expect(store.actionError == nil)
        #expect(store.lastNotice?.level == .warning)

        store.clearNotice()
        #expect(store.lastNotice == nil)
    }

    @Test func setModelAndThinkingUpdateTheSnapshot() async throws {
        let client = FakeDaemonClient()
        let open = try await openConversation(client)
        let store = open.store
        client.onSend(SetAgentModelRequest.self) { _ in
            try Fixtures.payload("set_agent_model_response", as: AgentActionResponse.self)
        }
        client.onSend(SetAgentThinkingRequest.self) { _ in
            try Fixtures.payload("set_agent_thinking_response", as: AgentActionResponse.self)
        }

        await store.setModel("opencode-go/glm-5.3")
        #expect(client.requests(SetAgentModelRequest.self).first?.modelId == "opencode-go/glm-5.3")
        #expect(store.agent?.model == "opencode-go/glm-5.3")

        await store.setThinking("low")
        #expect(client.requests(SetAgentThinkingRequest.self).first?.thinkingOptionId == "low")
        #expect(store.agent?.thinkingOptionId == "low")
        #expect(store.agent?.effectiveThinkingOptionId == "low")
    }

    @Test func aRejectedChangeKeepsTheOldValueAndReportsTheError() async throws {
        let client = FakeDaemonClient()
        let open = try await openConversation(client)
        let store = open.store
        let previousModel = store.agent?.model
        client.onSend(SetAgentModelRequest.self) { _ in
            let json = #"""
                {"requestId":"r","agentId":"a","accepted":false,"error":"model not available"}
                """#
            return try JSONDecoder().decode(AgentActionResponse.self, from: Data(json.utf8))
        }

        await store.setModel("nope")

        #expect(store.agent?.model == previousModel)
        #expect(store.actionError == "model not available")
    }

    @Test func renameAndArchiveApplyTheDaemonsAnswer() async throws {
        let client = FakeDaemonClient()
        let open = try await openConversation(client)
        let store = open.store
        client.onSend(UpdateAgentRequest.self) { _ in
            try Fixtures.payload("update_agent_response", as: AgentActionResponse.self)
        }
        client.onSend(ArchiveAgentRequest.self) { _ in
            try Fixtures.payload("archive_agent_response", as: ArchiveAgentRequest.Response.self)
        }

        await store.rename(to: "  T6 probe agent  ")
        #expect(client.requests(UpdateAgentRequest.self).first?.name == "T6 probe agent")
        #expect(store.agent?.title == "T6 probe agent")

        await store.rename(to: "   ")
        #expect(client.requests(UpdateAgentRequest.self).count == 1, "blank rename is a no-op")

        await store.archive()
        #expect(store.agent?.archivedAt != nil)
        #expect(store.actionError == nil)
    }

    // MARK: Attention

    @Test func openingAConversationClearsAttentionOnTheDaemon() async throws {
        let client = FakeDaemonClient()
        let agents = try Fixtures.agents()
        let agentId = try #require(agents.entries.first?.agent.id)
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { _ in try Fixtures.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        client.onSend(ClearAgentAttentionRequest.self) { _ in
            try Fixtures.payload(
                "clear_agent_attention_response", as: ClearAgentAttentionRequest.Response.self)
        }

        let info = try Load.serverInfo()
        client.push(.connected(info))
        let session = HostSession(client: client)
        await session.start()
        _ = await eventually { session.connection == .connected(info) }

        var flagged = try Fixtures.agent()
        flagged.requiresAttention = true
        flagged.attentionReason = "permission"
        client.push(.agentUpdate(.upsert(flagged, project: nil)))
        let flaggedInList = await eventually { session.agents.first?.requiresAttention == true }
        #expect(flaggedInList)
        #expect(session.agents.needingAttention.count == 1)
        #expect(session.agents.needingAttention.first?.attention == .permission)

        let store = session.conversation(for: agentId)
        let ready = await eventually { store.phase == .ready }
        #expect(ready)

        let clearedOnDaemon = await eventually { !client.requests(ClearAgentAttentionRequest.self).isEmpty }
        #expect(clearedOnDaemon)
        #expect(client.requests(ClearAgentAttentionRequest.self).first?.agentId == agentId)
        let badgeGone = await eventually { store.agent?.requiresAttention != true }
        #expect(badgeGone)
    }
}
