import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Host-scoped settings and presence for one daemon: the mutable config document, provider enable
/// switches, agent profiles, slash commands, push-token registration and the 15 s heartbeat.
///
/// Owned by `HostSession`. Configuration writes are surgical patches: only the fields the caller
/// sets go out, so unknown daemon config survives untouched.
///
/// IMPLEMENTATION TICKET: docs/tickets/PHASE3-BACKEND.md (T10)
@MainActor @Observable
public final class HostSettingsStore {
    public enum Phase: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    /// The last successful read or patch response. Nil until `load()` succeeds.
    public private(set) var config: DaemonConfig?
    /// Last failed load, patch, command or push action. Cleared by the next success.
    public private(set) var error: String?
    public private(set) var isSaving = false
    /// Slash commands by agent id, as last loaded.
    public private(set) var commandsByAgent: [String: [AgentSlashCommand]] = [:]
    /// Last command-listing error per agent id.
    public private(set) var commandErrorsByAgent: [String: String] = [:]

    // Capability flags, read once per `server_info`.
    /// `features.agentProfiles`: old daemons silently drop the key when saving config.
    public private(set) var supportsProfiles = false
    /// `features.pushTokenRevocation`: only capable daemons accept `push.unregister.request`.
    public private(set) var supportsPushTokenRevocation = false
    /// `features.daemonDiagnostics`: only capable daemons answer `diagnostics.request`.
    public private(set) var supportsDaemonDiagnostics = false

    // Presence state. The app drives this from focus and visibility changes.
    public private(set) var isPresenting = false
    public private(set) var focusedAgentId: String?
    public private(set) var appVisible = true
    public private(set) var lastPresenceSentAt: Date?
    /// Number of heartbeats written to the socket, including the immediate ones on changes.
    public private(set) var presenceSentCount = 0

    private let client: any DaemonClient
    private let heartbeatInterval: Duration
    private var deviceType: PresenceDeviceType = .mobile
    private var appVisibilityChangedAt: String?
    private var presenceTask: Task<Void, Never>?
    /// Last `providers_snapshot_update` entries seen, by provider id. The first update only
    /// seeds this baseline (upstream ignores initial discovery); later updates are diffed
    /// against it to decide whether slash commands must be refetched.
    private var providerSnapshotBaseline: [String: ProviderSnapshotEntry]?
    /// True once `serverInfoChanged` has run. A later call means the daemon reconnected
    /// (`HostSession` reports every `.connected`), so cached commands are dropped.
    private var hasSeenServerInfo = false

    /// - Parameter heartbeatInterval: 15 s in the app; tests pass a short interval.
    public init(client: any DaemonClient, heartbeatInterval: Duration = .seconds(15)) {
        self.client = client
        self.heartbeatInterval = heartbeatInterval
    }

    // MARK: Config

    /// Reads the daemon config. Safe to call again (pull to refresh, or after a reconnect).
    public func load() async {
        phase = .loading
        do {
            let response = try await client.send(GetDaemonConfigRequest())
            config = response.config
            error = nil
            phase = .ready
        } catch {
            let message = hostSettingsErrorText(error)
            self.error = message
            phase = .failed(message)
        }
    }

    /// Applies one surgical patch and stores the daemon's effective config. Returns false with
    /// `error` set when the daemon rejects it or the socket fails.
    ///
    /// `set_daemon_config_request` has no revision field: `expectedRevision` belongs to the
    /// project-config RPC (`write_project_config_request`), not to daemon config. The daemon's
    /// response is the effective config after the merge, which is what this store adopts.
    @discardableResult
    public func save(_ patch: DaemonConfigPatch) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await client.send(SetDaemonConfigRequest(config: patch))
            config = response.config
            error = nil
            phase = .ready
            return true
        } catch {
            self.error = hostSettingsErrorText(error)
            return false
        }
    }

    /// Provider rows in the daemon's config, in provider-id order.
    public var providerSettings: [(provider: String, settings: DaemonProviderConfig)] {
        (config?.providers ?? [:]).sorted { $0.key < $1.key }.map { (provider: $0.key, settings: $0.value) }
    }

    /// The user's custom models for one provider, from `config.providers[id].additionalModels`.
    public func additionalModels(for provider: String) -> [DaemonProviderModel] {
        config?.providers[provider]?.additionalModels ?? []
    }

    /// The result of the last `providerDiagnostic(_:)` call for a provider, keyed by provider id.
    public private(set) var providerDiagnostics: [String: ProviderDiagnosticState] = [:]

    /// What one provider's diagnostic did most recently. Observable; the UI reads it.
    public enum ProviderDiagnosticState: Sendable, Equatable {
        case loading
        /// The daemon's probe output; shown mono in the provider sheet.
        case ready(String)
        /// The probe failed; the message is shown in place of the log.
        case failed(String)
    }

    /// A provider is enabled unless the config explicitly disables it.
    public func isProviderEnabled(_ providerId: String) -> Bool {
        config?.providers[providerId]?.enabled ?? true
    }

    /// Flips one provider's enable switch. This is a config patch: `providers` is a per-provider
    /// merge, not a replacement.
    @discardableResult
    public func setProviderEnabled(_ providerId: String, _ enabled: Bool) async -> Bool {
        var patch = DaemonConfigPatch()
        patch.providers = [providerId: DaemonConfigPatch.Provider(enabled: enabled)]
        return await save(patch)
    }

    /// Saved profiles. Empty unless the daemon advertises `features.agentProfiles`.
    public var profiles: [AgentProfile] {
        guard supportsProfiles else { return [] }
        return config?.agentProfiles ?? []
    }

    /// Persists the whole profile list; there is no per-profile RPC. Gated on the daemon's
    /// `features.agentProfiles`: returns false with `error` set when the daemon cannot store
    /// profiles (an old daemon would silently drop the key on save).
    @discardableResult
    public func saveProfiles(_ next: [AgentProfile]) async -> Bool {
        guard supportsProfiles else {
            error = "This host cannot store agent profiles."
            return false
        }
        var patch = DaemonConfigPatch()
        patch.agentProfiles = next
        return await save(patch)
    }

    /// Re-runs the daemon's probe for one provider and stores the result. Failures are stored as
    /// `.failed(message)`, never thrown; the daemon's probe can take a while, so this uses a
    /// longer timeout than ordinary requests.
    @discardableResult
    public func providerDiagnostic(_ provider: String) async -> Bool {
        providerDiagnostics[provider] = .loading
        do {
            let response = try await client.send(
                ProviderDiagnosticRequest(provider: provider), timeout: .seconds(120))
            providerDiagnostics[provider] = .ready(response.diagnostic)
            return true
        } catch {
            providerDiagnostics[provider] = .failed(hostSettingsErrorText(error))
            return false
        }
    }

    // MARK: Slash commands

    /// Loads the slash-command menu for one agent. With `draft` it asks for the commands a draft
    /// would have instead of the live agent's.
    @discardableResult
    public func loadCommands(for agentId: String, draft: AgentDraftConfig? = nil) async -> [AgentSlashCommand] {
        do {
            let response = try await client.send(
                ListCommandsRequest(agentId: agentId, draftConfig: draft))
            if let error = response.error {
                commandErrorsByAgent[agentId] = error
                return commandsByAgent[agentId] ?? []
            }
            commandErrorsByAgent[agentId] = nil
            commandsByAgent[agentId] = response.commands
            return response.commands
        } catch {
            commandErrorsByAgent[agentId] = hostSettingsErrorText(error)
            return commandsByAgent[agentId] ?? []
        }
    }

    public func commands(for agentId: String) -> [AgentSlashCommand] {
        commandsByAgent[agentId] ?? []
    }

    public func commandError(for agentId: String) -> String? {
        commandErrorsByAgent[agentId]
    }

    /// Drops cached commands when a conversation closes.
    public func clearCommands(for agentId: String) {
        commandsByAgent[agentId] = nil
        commandErrorsByAgent[agentId] = nil
    }

    /// Drops every cached slash-command list, so the next `loadCommands` refetches.
    ///
    /// Upstream refetches an agent's commands via React Query invalidation
    /// (`agent-commands/cache/index.ts`, `data/push-router.ts`): on a
    /// `providers_snapshot_update` when that agent's provider entry changes in a relevant
    /// field (status, enabled, source, models, modes, defaultModeId), and on an explicit
    /// provider refresh (all catalogs). Session commands are keyed by agent id only, so a
    /// model/mode change on a live agent does not itself refetch; draft commands are keyed
    /// by provider/cwd/mode/model/thinking, so a new draft config is a new fetch (which
    /// `loadCommands(draft:)` already does, uncached by config). `daemon_config_changed`
    /// does not invalidate commands upstream. This store has no agent→provider map, so a
    /// relevant provider change drops all agents' lists — a superset of upstream's
    /// provider-scoped predicate, never a stale subset.
    public func invalidateCommands() {
        commandsByAgent = [:]
        commandErrorsByAgent = [:]
    }

    // MARK: Host diagnostics

    /// What the last `loadDiagnostics()` did. `.unsupported` is quiet: daemons without
    /// `features.daemonDiagnostics` never answer the request, so no request is sent and no
    /// error is recorded.
    public enum DiagnosticsState: Sendable, Equatable {
        case idle
        case unsupported
        case loading
        /// The daemon's diagnostic bundle, verbatim. The UI scrubs it before display/share.
        case ready(String)
        case failed(String)
    }

    public private(set) var diagnosticsState: DiagnosticsState = .idle

    /// Runs the daemon's whole-host diagnostic (`diagnostics.request`, gated on
    /// `features.daemonDiagnostics`). Returns false without sending anything when the daemon
    /// is not capable; the state becomes `.unsupported` and `error` is untouched. Failures
    /// are stored as `.failed(message)`, never thrown.
    @discardableResult
    public func loadDiagnostics() async -> Bool {
        guard supportsDaemonDiagnostics else {
            diagnosticsState = .unsupported
            return false
        }
        diagnosticsState = .loading
        do {
            let response = try await client.send(
                DaemonDiagnosticsRequest(), timeout: .seconds(120))
            diagnosticsState = .ready(response.diagnostic)
            return true
        } catch {
            diagnosticsState = .failed(hostSettingsErrorText(error))
            return false
        }
    }

    // MARK: Presence

    /// Starts the 15 s heartbeat and sends one immediately. Call when the app becomes active.
    public func startPresence(
        deviceType: PresenceDeviceType = .mobile, focusedAgentId: String? = nil, appVisible: Bool = true
    ) {
        guard !isPresenting else {
            updatePresence(focusedAgentId: focusedAgentId, appVisible: appVisible)
            return
        }
        self.deviceType = deviceType
        self.focusedAgentId = focusedAgentId
        self.appVisible = appVisible
        self.appVisibilityChangedAt = nil
        isPresenting = true
        sendHeartbeat()

        let interval = heartbeatInterval
        presenceTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard let self else { return }
                self.sendHeartbeat()
            }
        }
    }

    /// The user focused an agent (or closed the conversation when nil). Sends immediately.
    public func updateFocus(_ agentId: String?) {
        focusedAgentId = agentId
        guard isPresenting else { return }
        sendHeartbeat()
    }

    /// The app moved between foreground and background. Sends immediately on a real change.
    public func updateVisibility(_ visible: Bool) {
        guard appVisible != visible else { return }
        appVisible = visible
        appVisibilityChangedAt = Self.timestamp()
        guard isPresenting else { return }
        sendHeartbeat()
    }

    /// One call for focus and visibility changes together, e.g. from a scene-phase handler.
    public func updatePresence(focusedAgentId: String?, appVisible: Bool) {
        let visibilityChanged = self.appVisible != appVisible
        self.focusedAgentId = focusedAgentId
        self.appVisible = appVisible
        if visibilityChanged { appVisibilityChangedAt = Self.timestamp() }
        guard isPresenting else { return }
        sendHeartbeat()
    }

    /// Stops the heartbeat. Call when the app goes away or the host is removed.
    public func stopPresence() {
        isPresenting = false
        presenceTask?.cancel()
        presenceTask = nil
    }

    // MARK: Push

    /// Registers an Expo push token. Fire-and-forget: the daemon sends no response.
    public func registerPushToken(_ token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "A push token is required."
            return
        }
        do {
            try await client.send(RegisterPushToken(token: trimmed))
            error = nil
        } catch {
            self.error = hostSettingsErrorText(error)
        }
    }

    /// Revokes a push token. Returns false with `error` set when the host cannot revoke tokens.
    @discardableResult
    public func unregisterPushToken(_ token: String) async -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "A push token is required."
            return false
        }
        guard supportsPushTokenRevocation else {
            error = "This host cannot revoke push tokens."
            return false
        }
        do {
            _ = try await client.send(PushUnregisterRequest(token: trimmed))
            error = nil
            return true
        } catch {
            self.error = hostSettingsErrorText(error)
            return false
        }
    }

    // MARK: HostSession handoff

    /// Called once per `server_info`; capability flags are read here and nowhere else.
    /// A call after the first means a reconnect, so cached slash commands are dropped and
    /// refetched on next use (upstream invalidates the providers snapshot on reconnect,
    /// whose update path invalidates commands the same way).
    internal func serverInfoChanged(_ info: ServerInfo?) {
        supportsProfiles = info?.hasFeature("agentProfiles") ?? false
        supportsPushTokenRevocation = info?.hasFeature("pushTokenRevocation") ?? false
        supportsDaemonDiagnostics = info?.hasFeature("daemonDiagnostics") ?? false
        if !supportsDaemonDiagnostics, diagnosticsState != .loading {
            diagnosticsState = .unsupported
        }
        if hasSeenServerInfo {
            invalidateCommands()
        } else {
            hasSeenServerInfo = true
        }
    }

    /// Pushed `status` messages this ticket owns. `daemon_config_changed` carries the full config.
    /// `providers_snapshot_update` diffs the provider catalogue against the last seen entries:
    /// a change in a field that can alter an agent's command list (status, enabled, source,
    /// models, modes, defaultModeId — upstream's `relevant` predicate in
    /// `agent-commands/cache/index.ts`) invalidates the cached commands. The first update
    /// only seeds the baseline, matching upstream ignoring initial discovery.
    internal func handle(messageType: String, raw: Data) {
        switch messageType {
        case "status":
            guard
                let changed = try? JSONDecoder().decode(
                    SessionPayloadEnvelope<DaemonConfigChanged>.self, from: raw
                ).payload,
                changed.status == "daemon_config_changed"
            else { return }
            config = changed.config
            if phase != .loading { phase = .ready }
        case "providers_snapshot_update":
            handleProvidersSnapshotUpdate(raw)
        default:
            return
        }
    }

    private func handleProvidersSnapshotUpdate(_ raw: Data) {
        guard
            let update = try? JSONDecoder().decode(
                SessionPayloadEnvelope<ProvidersSnapshotUpdate>.self, from: raw
            ).payload
        else { return }
        let current = Dictionary(
            uniqueKeysWithValues: update.entries.map { ($0.provider, $0) })
        if let baseline = providerSnapshotBaseline {
            if Self.relevantProviderChange(from: baseline, to: current) {
                invalidateCommands()
            }
        }
        providerSnapshotBaseline = current
    }

    /// The upstream `relevant` comparison: only status, enabled, source, models, modes and
    /// defaultModeId can change what `list_commands_request` would return. Label, error
    /// text and fetched-at churn must not refetch.
    private static func relevantProviderChange(
        from previous: [String: ProviderSnapshotEntry], to current: [String: ProviderSnapshotEntry]
    ) -> Bool {
        guard previous.count == current.count else { return true }
        for (provider, entry) in current {
            guard let before = previous[provider] else { return true }
            if before.status != entry.status
                || before.enabled != entry.enabled
                || before.source != entry.source
                || before.models != entry.models
                || before.modes != entry.modes
                || before.defaultModeId != entry.defaultModeId
            {
                return true
            }
        }
        return false
    }

    // MARK: Internals

    private func sendHeartbeat() {
        let now = Date()
        lastPresenceSentAt = now
        presenceSentCount += 1
        let message = ClientHeartbeat(
            deviceType: deviceType,
            focusedAgentId: focusedAgentId,
            lastActivityAt: Self.timestamp(now),
            appVisible: appVisible,
            appVisibilityChangedAt: appVisibilityChangedAt)
        let client = self.client
        Task {
            try? await client.send(message)
        }
    }

    private static func timestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// One readable line for an error, for `error` and phases.
private func hostSettingsErrorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}
