import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Everything you do to an agent besides chatting: the provider catalogue for the new-agent
/// pickers, creating an agent, and routing live permission events to open conversations.
///
/// Per-agent changes (mode, model, thinking, rename, archive, answering a permission) live on
/// `ConversationStore`, because that is where the snapshot and the card are.
///
/// IMPLEMENTATION TICKET: docs/tickets/T6-agent-control.md
@MainActor @Observable
public final class AgentControlStore {
    public enum CatalogPhase: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public private(set) var phase: CatalogPhase = .idle
    /// Providers in the daemon's own order, with models, modes and thinking options.
    public private(set) var providers: [ProviderSnapshotEntry] = []
    /// Plain capability flag, read once from `server_info.features.providersSnapshot`.
    /// When false the store uses the per-provider list RPCs instead of the snapshot.
    public private(set) var isSupported = true
    /// Last failed create or catalogue load, for a banner. Cleared by the next success.
    public private(set) var actionError: String?
    /// The snapshot returned by the last successful `createAgent`, so the UI can open it at once.
    public private(set) var lastCreatedAgent: AgentSnapshot?

    private let client: any DaemonClient
    /// Scope of the catalogue we hold, i.e. the `cwd` of the last `loadCatalog`.
    /// `providers_snapshot_update` frames for other workspaces share the socket; applying those
    /// would swap the pickers' models out from under the user.
    private var catalogCwd: String?
    /// Plain capability flag, read once from `server_info.features.creationLifecycle`. With it the
    /// caller's create is sent as `agent.create.request` (receipts, caller-owned key); without it
    /// the legacy `create_agent_request` is the only path. Never branch on this in a view.
    private var supportsCreationLifecycle = false

    public init(client: any DaemonClient) {
        self.client = client
    }

    // MARK: Catalogue

    /// Loads the catalogue for the pickers. `cwd` targets a workspace-specific catalogue; omit it
    /// for the global one. Safe to call again (pull to refresh).
    public func loadCatalog(cwd: String? = nil) async {
        catalogCwd = cwd
        phase = .loading
        actionError = nil
        do {
            if isSupported {
                let response = try await client.send(GetProvidersSnapshotRequest(cwd: cwd))
                // `notModified` means the entries we hold are still current.
                if response.notModified != true { providers = response.entries }
            } else {
                providers = try await legacyCatalog(cwd: cwd)
            }
            phase = .ready
        } catch {
            phase = .failed(message(for: error))
        }
    }

    /// Forces the daemon to re-probe provider availability, then reloads the catalogue.
    public func refreshCatalog(cwd: String? = nil) async {
        guard isSupported else {
            await loadCatalog(cwd: cwd)
            return
        }
        do {
            _ = try await client.send(RefreshProvidersSnapshotRequest(cwd: cwd))
        } catch {
            actionError = message(for: error)
        }
        await loadCatalog(cwd: cwd)
    }

    /// Providers that can start an agent right now (enabled and probed ready).
    public var readyProviders: [ProviderSnapshotEntry] { providers.filter(\.isAvailable) }

    public func provider(_ providerId: String) -> ProviderSnapshotEntry? {
        providers.first { $0.provider == providerId }
    }

    /// Selectable models, in the daemon's order.
    public func models(forProvider providerId: String) -> [AgentModelDefinition] {
        (provider(providerId)?.models ?? []).filter { $0.isSelectable != false }
    }

    public func modes(forProvider providerId: String) -> [AgentMode] {
        provider(providerId)?.modes ?? []
    }

    public func thinkingOptions(forProvider providerId: String, modelId: String) -> [ProviderThinkingOption] {
        (provider(providerId)?.models ?? []).first { $0.id == modelId }?.thinkingOptions ?? []
    }

    public func defaultModel(forProvider providerId: String) -> AgentModelDefinition? {
        let models = models(forProvider: providerId)
        return models.first { $0.isDefault == true } ?? models.first
    }

    // MARK: Creation

    /// Creates an agent and returns its id, or `nil` with `actionError` set.
    ///
    /// `cwd` places the runtime; `workspaceId` re-homes it into an existing workspace (omit to use
    /// the caller's). `prompt` is sent as the first turn. `attachments`, when given, ride the
    /// create request verbatim — e.g. the chat-history seed for a fork.
    ///
    /// `idempotencyKey` is the caller's operation key: the same key must come back on a retry of
    /// the same create, so a request whose answer was lost joins the daemon's in-flight creation
    /// instead of starting a second agent (`docs/hub.md`, "Creation"). The caller owns its
    /// lifetime; a changed intent needs a new key (`creation/index.ts:120-130` rejects a reused key
    /// with a different fingerprint). When the daemon advertises `creationLifecycle` and a key is
    /// given, the create goes out as `agent.create.request`; otherwise the legacy request is used,
    /// as upstream's fallback does (`creation/index.ts:183-199`).
    public func createAgent(
        cwd: String,
        workspaceId: String? = nil,
        provider: String,
        model: String? = nil,
        modeId: String? = nil,
        thinkingOptionId: String? = nil,
        featureValues: [String: JSONValue]? = nil,
        prompt: String? = nil,
        title: String? = nil,
        attachments: [AgentAttachment]? = nil,
        idempotencyKey: String? = nil
    ) async -> String? {
        actionError = nil
        lastCreatedAgent = nil

        let trimmedPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = AgentSessionConfig(
            provider: provider, cwd: cwd, modeId: modeId, model: model,
            thinkingOptionId: thinkingOptionId,
            featureValues: (featureValues?.isEmpty == false) ? featureValues : nil,
            title: title)
        let firstPrompt = (trimmedPrompt?.isEmpty == false) ? trimmedPrompt : nil
        let sentAttachments = (attachments?.isEmpty == false) ? attachments : nil

        if let idempotencyKey, supportsCreationLifecycle {
            let request = CreateAgentModernRequest(
                idempotencyKey: idempotencyKey, config: config, initialPrompt: firstPrompt,
                workspaceId: workspaceId, attachments: sentAttachments,
                // The first message is the prompt; it shares the operation's identity so a retry
                // cannot land it twice. Upstream keeps a separate message id for the same reason
                // (`docs/hub.md`: "reuses the first message ID after failures").
                clientMessageId: firstPrompt == nil ? nil : idempotencyKey)
            do {
                let response = try await client.send(request)
                guard let agent = response.agent else {
                    actionError = response.error ?? "The daemon could not create the agent."
                    return nil
                }
                lastCreatedAgent = agent
                return agent.id
            } catch {
                actionError = message(for: error)
                return nil
            }
        }

        var request = CreateAgentRequest(
            config: config,
            initialPrompt: firstPrompt,
            workspaceId: workspaceId,
            attachments: sentAttachments)
        // Upstream sends the key on the legacy request only without a prompt: the keyed legacy
        // create cannot carry one (`creation/index.ts:183-199`).
        if let idempotencyKey, firstPrompt == nil {
            request.idempotencyKey = idempotencyKey
            request.clientMessageId = idempotencyKey
        }

        do {
            let response = try await client.send(request)
            guard response.status == "agent_created", let agent = response.agent else {
                actionError = response.error ?? "The daemon could not create the agent."
                return nil
            }
            lastCreatedAgent = agent
            return agent.id
        } catch {
            actionError = message(for: error)
            return nil
        }
    }

    // MARK: HostSession handoff

    /// Called once per `server_info`; the capability is read here and nowhere else.
    internal func serverInfoChanged(_ info: ServerInfo?) {
        guard let info else { return }
        isSupported = info.hasFeature("providersSnapshot")
        supportsCreationLifecycle = info.hasFeature("creationLifecycle")
    }

    /// Routes unsolicited catalogue and permission messages: the pickers' incremental snapshot
    /// pushes, and permission events to the conversation that shows the card.
    internal func handle(
        messageType: String, raw: Data, conversations: [String: ConversationStore]
    ) {
        let decoder = JSONDecoder()
        switch messageType {
        case "agent_permission_request":
            guard
                let event = try? decoder.decode(
                    SessionPayloadEnvelope<AgentPermissionRequestEvent>.self, from: raw
                ).payload
            else { return }
            conversations[event.agentId]?.addPermission(event.request)

        case "agent_permission_resolved":
            guard
                let event = try? decoder.decode(
                    SessionPayloadEnvelope<AgentPermissionResolvedEvent>.self, from: raw
                ).payload
            else { return }
            conversations[event.agentId]?.removePermission(requestId: event.requestId)

        case "providers_snapshot_update":
            applySnapshotUpdate(raw)

        default:
            break
        }
    }

    // MARK: Internals

    /// Merges an incremental catalogue push for the scope we last requested. A provider that came
    /// back `loading` in the first snapshot becomes `ready` here, models and all, so the pickers
    /// fill in without another request.
    private func applySnapshotUpdate(_ raw: Data) {
        guard isSupported,
            let update = try? JSONDecoder().decode(
                SessionPayloadEnvelope<ProvidersSnapshotUpdate>.self, from: raw
            ).payload,
            update.cwd == catalogCwd
        else { return }

        for entry in update.entries {
            if let index = providers.firstIndex(where: { $0.provider == entry.provider }) {
                providers[index] = entry
            } else {
                providers.append(entry)
            }
        }
        if phase != .ready { phase = .ready }
    }

    /// Older daemons have no provider snapshot: one availability probe, then models and modes per
    /// available provider. Same entry shape, so callers don't branch.
    private func legacyCatalog(cwd: String?) async throws -> [ProviderSnapshotEntry] {
        let available = try await client.send(ListAvailableProvidersRequest())
        var entries: [ProviderSnapshotEntry] = []
        for item in available.providers {
            guard item.available else {
                entries.append(
                    ProviderSnapshotEntry(
                        provider: item.provider, status: .unavailable, error: item.error))
                continue
            }
            let models = try? await client.send(
                ListProviderModelsRequest(provider: item.provider, cwd: cwd))
            let modes = try? await client.send(
                ListProviderModesRequest(provider: item.provider, cwd: cwd))
            entries.append(
                ProviderSnapshotEntry(
                    provider: item.provider, status: .ready, error: models?.error ?? modes?.error,
                    models: models?.models, modes: modes?.modes))
        }
        return entries
    }
}

/// One readable line for an error, for `actionError` and the catalogue phase.
private func message(for error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}
