import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// The draft that becomes a session on its first send (UX-SPEC §3, ticket U2).
@Suite @MainActor
struct DraftSessionTests {
    /// Two providers: `claude` is unavailable (asleep), `codex` is ready with two models, one of
    /// which carries thinking levels, plus two modes and a default mode.
    nonisolated private static let snapshot = #"""
        {"requestId":"r","entries":[
          {"provider":"claude","status":"unavailable","enabled":true,"error":"not signed in"},
          {"provider":"codex","status":"ready","enabled":true,"defaultModeId":"plan",
           "models":[
             {"provider":"codex","id":"fast","label":"Fast","isDefault":true},
             {"provider":"codex","id":"deep","label":"Deep","defaultThinkingOptionId":"medium",
              "thinkingOptions":[
                {"id":"low","label":"Low"},
                {"id":"medium","label":"Medium"},
                {"id":"high","label":"High"}]}],
           "modes":[{"id":"plan","label":"Plan"},{"id":"write","label":"Write"}]}
        ]}
        """#



    private func catalogue(
        _ client: FakeDaemonClient, snapshot: String = DraftSessionTests.snapshot
    ) async -> AgentControlStore {
        client.onSend(GetProvidersSnapshotRequest.self) { _ in
            try JSONDecoder().decode(
                GetProvidersSnapshotRequest.Response.self, from: Data(snapshot.utf8))
        }
        let catalog = AgentControlStore(client: client)
        await catalog.loadCatalog(cwd: "/tmp/draft-scratch")
        return catalog
    }

    // MARK: Seeding

    @Test func seedPicksTheFirstAvailableProviderAndItsDefaults() async {
        let client = FakeDaemonClient()
        let catalog = await catalogue(client)
        let draft = DraftSession(workspaceId: "ws-1", cwd: "/tmp/draft-scratch")

        draft.seed(catalog: catalog)

        #expect(draft.providerId == "codex", "the unavailable provider is skipped")
        #expect(draft.modelId == "fast", "the provider's default model")
        #expect(draft.thinkingOptionId == nil, "a model with levels picks none, like the old form")
        #expect(draft.modeId == "plan", "the provider's default mode")
    }

    @Test func seedUsesTheLastUsedPicksWhenTheCatalogueOffersThem() async {
        let client = FakeDaemonClient()
        let catalog = await catalogue(client)
        let draft = DraftSession(
            workspaceId: "ws-1", cwd: "/tmp/draft-scratch",
            preferences: DraftPreferences(
                providerId: "codex", modelId: "deep", thinkingOptionId: "high", modeId: "write"))

        draft.seed(catalog: catalog)

        #expect(draft.providerId == "codex")
        #expect(draft.modelId == "deep")
        #expect(draft.thinkingOptionId == "high")
        #expect(draft.modeId == "write")
    }

    @Test func seedFallsBackWhenTheRememberedProviderIsGone() async {
        let client = FakeDaemonClient()
        let catalog = await catalogue(client)
        let draft = DraftSession(
            workspaceId: "ws-1", cwd: "/tmp/draft-scratch",
            preferences: DraftPreferences(
                providerId: "claude", modelId: "deep", thinkingOptionId: "high", modeId: "write"))

        draft.seed(catalog: catalog)

        #expect(draft.providerId == "codex")
        #expect(draft.modelId == "fast", "another provider's model is never carried over")
        #expect(draft.modeId == "plan")
    }

    @Test func seedDoesNothingWithoutAReadyProvider() async {
        let client = FakeDaemonClient()
        let catalog = await catalogue(client, snapshot: #"""
            {"requestId":"r","entries":[{"provider":"claude","status":"unavailable"}]}
            """#)
        let draft = DraftSession(workspaceId: nil, cwd: "/tmp/draft-scratch")

        draft.seed(catalog: catalog)

        #expect(draft.providerId == nil)
        #expect(draft.creationArguments == nil)
    }

    // MARK: Picks

    @Test func switchingProviderResetsModelThinkingAndModeToThatProvidersDefaults() async {
        let client = FakeDaemonClient()
        let catalog = await catalogue(client)
        let draft = DraftSession(workspaceId: "ws-1", cwd: "/tmp/draft-scratch")
        draft.seed(catalog: catalog)
        draft.selectModel("deep", catalog: catalog)
        draft.selectThinking("high")
        draft.selectMode("write")

        draft.selectProvider("codex", catalog: catalog)

        #expect(draft.modelId == "fast")
        #expect(draft.thinkingOptionId == nil)
        #expect(draft.modeId == "plan")
        #expect(draft.preferences.providerId == "codex")
        #expect(draft.preferences.modelId == "fast", "the switch is remembered for the next draft")
    }

    @Test func choosingAModelResetsThinkingToThatModelsDefault() async {
        let client = FakeDaemonClient()
        let catalog = await catalogue(client)
        let draft = DraftSession(workspaceId: "ws-1", cwd: "/tmp/draft-scratch")
        draft.seed(catalog: catalog)
        draft.selectThinking("high")

        draft.selectModel("fast", catalog: catalog)
        #expect(draft.thinkingOptionId == nil, "Fast reports no levels")

        draft.selectModel("deep", catalog: catalog)
        #expect(draft.thinkingOptionId == "medium", "Deep's own default level")
    }

    @Test func movingToAnotherWorkspaceKeepsThePicks() async {
        let client = FakeDaemonClient()
        let catalog = await catalogue(client)
        let draft = DraftSession(workspaceId: "ws-1", cwd: "/tmp/draft-scratch")
        draft.seed(catalog: catalog)
        draft.text = "hello"

        draft.move(toWorkspace: "ws-2", cwd: "/tmp/other")

        #expect(draft.workspaceId == "ws-2")
        #expect(draft.cwd == "/tmp/other")
        #expect(draft.providerId == "codex")
        #expect(draft.text == "hello")
    }

    // MARK: Creation

    @Test func creationArgumentsCarryTheWorkspaceAndPicks() async {
        let client = FakeDaemonClient()
        let catalog = await catalogue(client)
        let draft = DraftSession(workspaceId: "ws-1", cwd: "/tmp/draft-scratch")
        draft.seed(catalog: catalog)
        draft.selectModel("deep", catalog: catalog)
        draft.selectThinking("high")
        draft.text = "  refactor the parser  "

        let arguments = draft.creationArguments

        #expect(arguments?.workspaceId == "ws-1")
        #expect(arguments?.cwd == "/tmp/draft-scratch")
        #expect(arguments?.providerId == "codex")
        #expect(arguments?.modelId == "deep")
        #expect(arguments?.thinkingOptionId == "high")
        #expect(arguments?.modeId == "plan")
        #expect(arguments?.featureValues == nil)
        #expect(draft.canSend(hasAttachments: false))
    }

    @Test func createSendsThePromptAndAttachmentsAndClearsTheDraft() async throws {
        let client = FakeDaemonClient()
        let catalog = await catalogue(client)
        client.onSend(CreateAgentRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<CreateAgentRequest.Response>.self,
                from: Fixture.agentControl("create_agent_response")
            ).payload
        }
        let draft = DraftSession(workspaceId: "ws-1", cwd: "/tmp/draft-scratch")
        draft.seed(catalog: catalog)
        draft.text = "say ready"

        let agentId = await draft.create(
            using: catalog,
            attachments: [
                .text(AgentAttachment.TextAttachment(text: "attached"))
            ])

        let request = try #require(client.requests(CreateAgentRequest.self).first)
        #expect(request.config.provider == "codex")
        #expect(request.config.cwd == "/tmp/draft-scratch")
        #expect(request.config.model == "fast")
        #expect(request.config.modeId == "plan")
        #expect(request.workspaceId == "ws-1")
        #expect(request.initialPrompt == "say ready")
        #expect(request.attachments?.count == 1)
        #expect(agentId == "e02d8100-d528-4dae-ad00-88d911bc3777")
        #expect(draft.text.isEmpty)
        #expect(draft.pendingPrompt == nil)
        #expect(draft.error == nil)
        #expect(!draft.isCreating)
    }

    @Test func createFailureKeepsTheTextAndShowsTheDaemonError() async {
        let client = FakeDaemonClient()
        let catalog = await catalogue(client)
        client.onSend(CreateAgentRequest.self) { _ in
            let json = #"""
                {"status":"agent_create_failed","requestId":"r","error":"no such workspace","errorCode":"not_found"}
                """#
            return try JSONDecoder().decode(
                CreateAgentRequest.Response.self, from: Data(json.utf8))
        }
        let draft = DraftSession(workspaceId: "ws-1", cwd: "/tmp/draft-scratch")
        draft.seed(catalog: catalog)
        draft.text = "say ready"

        let agentId = await draft.create(using: catalog)

        #expect(agentId == nil)
        #expect(draft.text == "say ready", "the draft comes back with the text intact")
        #expect(draft.pendingPrompt == nil)
        #expect(draft.error == "no such workspace")
        #expect(!draft.isCreating)

        // The next send clears the old error before trying again.
        draft.clearError()
        #expect(draft.error == nil)
    }

    @Test func createWithoutACatalogueAnswersWithAnErrorAndKeepsTheText() async {
        let client = FakeDaemonClient()
        let catalog = AgentControlStore(client: client)
        let draft = DraftSession(workspaceId: nil, cwd: "/tmp/draft-scratch")
        draft.text = "hello"

        let agentId = await draft.create(using: catalog)

        #expect(agentId == nil)
        #expect(draft.text == "hello")
        #expect(draft.error == "This host reports no available provider.")
        #expect(client.requests.isEmpty)
    }

    @Test func canSendNeedsSomethingToSayOrAnAttachment() async {
        let client = FakeDaemonClient()
        let catalog = await catalogue(client)
        let draft = DraftSession(workspaceId: "ws-1", cwd: "/tmp/draft-scratch")
        draft.seed(catalog: catalog)

        #expect(!draft.canSend(hasAttachments: false))
        #expect(draft.canSend(hasAttachments: true))
        draft.text = "   "
        #expect(!draft.canSend(hasAttachments: false))
        draft.text = "hello"
        #expect(draft.canSend(hasAttachments: false))
    }
}
