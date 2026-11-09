import Foundation
import Observation
import PaseoProtocol

/// The last agent settings picked for a new session on this host, so the next draft starts where
/// the last one left off (UX-SPEC §3.1: "Defaults are the last-used provider/model/mode for this
/// host"). In memory only: the daemon keeps per-provider form preferences upstream
/// (`paseo-reference/packages/app/src/hooks/use-agent-form-state.ts`), which this client does not
/// read, so a relaunch falls back to the catalogue's defaults.
public struct DraftPreferences: Equatable, Sendable {
    public var providerId: String?
    public var modelId: String?
    public var thinkingOptionId: String?
    public var modeId: String?

    public init(
        providerId: String? = nil, modelId: String? = nil, thinkingOptionId: String? = nil,
        modeId: String? = nil
    ) {
        self.providerId = providerId
        self.modelId = modelId
        self.thinkingOptionId = thinkingOptionId
        self.modeId = modeId
    }
}

/// A session that does not exist yet: a workspace plus the provider, model, thinking and mode its
/// agent will be created with, and the text typed so far (UX-SPEC §3).
///
/// The agent is created on the first send, with the prompt and attachments as its first turn
/// (upstream's draft tab: `paseo-reference/packages/app/src/screens/workspace/workspace-screen.tsx`,
/// `composer/draft/create-flow.ts`). Nothing here talks to a socket except `create`, which goes
/// through `AgentControlStore` like every other creation.
@MainActor @Observable
public final class DraftSession {
    /// The settings a create call carries, built once from the draft so a test can read them
    /// without a socket.
    public struct CreationArguments: Equatable, Sendable {
        public var workspaceId: String?
        public var cwd: String
        public var providerId: String
        public var modelId: String?
        public var modeId: String?
        public var thinkingOptionId: String?
        public var featureValues: [String: JSONValue]?
    }

    /// The workspace the session will live in; nil when the host has no workspaces at all.
    public private(set) var workspaceId: String?
    public private(set) var cwd: String
    /// What the composer holds.
    public var text = ""
    public private(set) var providerId: String?
    public private(set) var modelId: String?
    public private(set) var thinkingOptionId: String?
    public private(set) var modeId: String?
    /// Profiles are not part of the draft's controls sheet (UX-SPEC §3.1), so this is only ever
    /// what a caller seeded.
    public private(set) var featureValues: [String: JSONValue]?
    /// A create RPC is in flight. Sends are ignored meanwhile.
    public private(set) var isCreating = false
    /// The last failure, shown above the composer. Cleared by the next send.
    public private(set) var error: String?
    /// The prompt shown as a pending bubble while the agent is created.
    public private(set) var pendingPrompt: String?
    public private(set) var preferences: DraftPreferences

    public init(
        workspaceId: String?, cwd: String, preferences: DraftPreferences = DraftPreferences(),
        featureValues: [String: JSONValue]? = nil
    ) {
        self.workspaceId = workspaceId
        self.cwd = cwd
        self.preferences = preferences
        self.featureValues = featureValues
    }

    // MARK: Seeding

    /// Picks the provider, model, thinking and mode to start from: the last-used ones when the
    /// catalogue still offers them, else the first available provider and its defaults. Safe to
    /// call again when the catalogue arrives late.
    public func seed(catalog: AgentControlStore) {
        let available = catalog.readyProviders
        guard !available.isEmpty else { return }
        let remembered = preferences.providerId.flatMap { id in
            available.first { $0.provider == id }
        }
        let provider = remembered?.provider ?? available[0].provider
        providerId = provider
        let lastUsed = remembered != nil

        let models = catalog.models(forProvider: provider)
        let rememberedModel = lastUsed ? preferences.modelId : nil
        modelId =
            rememberedModel.flatMap { id in models.first { $0.id == id }?.id }
            ?? catalog.defaultModel(forProvider: provider)?.id

        let rememberedThinking = lastUsed ? preferences.thinkingOptionId : nil
        let options = modelId.map {
            catalog.thinkingOptions(forProvider: provider, modelId: $0)
        } ?? []
        thinkingOptionId =
            rememberedThinking.flatMap { id in options.first { $0.id == id }?.id }
            ?? defaultThinking(catalog: catalog, provider: provider, modelId: modelId)

        let modes = catalog.modes(forProvider: provider)
        let rememberedMode = lastUsed ? preferences.modeId : nil
        modeId =
            rememberedMode.flatMap { id in modes.first { $0.id == id }?.id }
            ?? catalog.provider(provider)?.defaultModeId
            ?? modes.first?.id
    }

    /// The model's own default level when there is one, else the provider default (nil = the
    /// provider's choice, which the create request omits).
    private func defaultThinking(
        catalog: AgentControlStore, provider: String, modelId: String?
    ) -> String? {
        guard let modelId else { return nil }
        return catalog.models(forProvider: provider)
            .first(where: { $0.id == modelId })?.defaultThinkingOptionId
    }

    // MARK: Picks

    /// Switching provider drops the old provider's model, thinking and mode for that provider's
    /// defaults: the models are not shared.
    public func selectProvider(_ id: String, catalog: AgentControlStore) {
        providerId = id
        modelId = catalog.defaultModel(forProvider: id)?.id
        thinkingOptionId = defaultThinking(catalog: catalog, provider: id, modelId: modelId)
        modeId = catalog.provider(id)?.defaultModeId ?? catalog.modes(forProvider: id).first?.id
        recordPreferences()
    }

    /// A new model carries its own thinking options; the level resets to the model's default.
    public func selectModel(_ id: String, catalog: AgentControlStore) {
        modelId = id
        thinkingOptionId = defaultThinking(
            catalog: catalog, provider: providerId ?? "", modelId: id)
        recordPreferences()
    }

    public func selectThinking(_ id: String?) {
        thinkingOptionId = id
        recordPreferences()
    }

    public func selectMode(_ id: String?) {
        modeId = id
        recordPreferences()
    }

    /// Moves the draft to another workspace; the settings stay.
    public func move(toWorkspace workspaceId: String, cwd: String) {
        self.workspaceId = workspaceId
        self.cwd = cwd
    }

    public func clearError() {
        error = nil
    }

    private func recordPreferences() {
        preferences = DraftPreferences(
            providerId: providerId, modelId: modelId, thinkingOptionId: thinkingOptionId,
            modeId: modeId)
    }

    // MARK: Creation

    /// True when a send can create the agent: a provider with a model, and something to say.
    public func canSend(hasAttachments: Bool) -> Bool {
        guard !isCreating, providerId != nil, modelId != nil else { return false }
        return hasAttachments || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What the create request will carry, or nil while the catalogue still owes a provider.
    public var creationArguments: CreationArguments? {
        guard let providerId, let modelId else { return nil }
        return CreationArguments(
            workspaceId: workspaceId, cwd: cwd, providerId: providerId, modelId: modelId,
            modeId: modeId, thinkingOptionId: thinkingOptionId, featureValues: featureValues)
    }

    /// Creates the agent with the prompt as its first turn. On failure the text comes back into
    /// the composer and `error` explains why (UX-SPEC §3.2); on success the draft is spent and
    /// the caller navigates to `agentId`.
    public func create(
        using catalog: AgentControlStore, attachments: [AgentAttachment]? = nil
    ) async -> String? {
        guard !isCreating else { return nil }
        guard let arguments = creationArguments else {
            error = "This host reports no available provider."
            return nil
        }
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty || !(attachments ?? []).isEmpty else { return nil }

        isCreating = true
        error = nil
        // The prompt leaves the field at once: it is the pending bubble now (UX-SPEC §3.2).
        pendingPrompt = prompt.isEmpty ? nil : prompt
        text = ""
        defer { isCreating = false }

        let agentId = await catalog.createAgent(
            cwd: arguments.cwd,
            workspaceId: arguments.workspaceId,
            provider: arguments.providerId,
            model: arguments.modelId,
            modeId: arguments.modeId,
            thinkingOptionId: arguments.thinkingOptionId,
            featureValues: arguments.featureValues,
            prompt: prompt.isEmpty ? nil : prompt,
            attachments: attachments)

        guard let agentId else {
            // Back to the draft with the text intact, unless the user has started something new.
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let pending = pendingPrompt
            {
                text = pending
            }
            pendingPrompt = nil
            error = catalog.actionError ?? "The daemon could not create the agent."
            return nil
        }
        pendingPrompt = nil
        return agentId
    }
}
