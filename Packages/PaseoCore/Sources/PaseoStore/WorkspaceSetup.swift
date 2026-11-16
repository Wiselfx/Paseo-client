import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Worktree setup observation, one instance per host.
///
/// The modern path (`workspace.setup.subscribe.request` + `workspace_setup_progress` frames,
/// released with `subscription.release.request`) requires the client to advertise
/// `owned_subscriptions`, which this client does not (see `ClientCapabilities.implemented`); the
/// daemon answers the subscribe RPC with "Workspace setup observation requires owned
/// subscriptions". When the capability is absent this store falls back to polling
/// `workspace_setup_status_request` — live on this daemon, no subscription needed. The subscribe
/// machinery is implemented and unit-tested for the day the client advertises the capability.
///
/// IMPLEMENTATION TICKET: docs/tickets/M2.10-setup-archive-warning.md
@MainActor @Observable
public final class WorkspaceSetupObservationStore {
    public struct Capabilities: Sendable, Equatable {
        /// `features.workspaceSetupObservation`: the status/subscribe RPCs exist.
        public var observation = false
        /// `features.workspaceSetupRun`: `workspace.setup.run.request` exists.
        public var run = false
        /// True only when this client advertises `owned_subscriptions` in its hello. This client
        /// does not (see `ClientCapabilities.implemented`), so the subscribe path is never taken
        /// today; the machinery exists and is unit-tested for when that changes.
        public var ownedSubscriptions = false

        public init() {}
    }

    public private(set) var capabilities = Capabilities()
    /// Latest snapshot per workspace id, from status, subscribe or progress frames.
    public private(set) var snapshots: [String: WorkspaceSetupSnapshot] = [:]
    /// Workspaces with an in-flight status poll.
    public private(set) var isPolling: Set<String> = []
    /// Last operation failure, for a banner; nil after the last success.
    public private(set) var error: String?

    /// False until `update(serverInfo:)` runs at least once.
    public var isSupported: Bool { capabilities.observation }

    private let client: any DaemonClient
    private var subscriptionIds: [String: String] = [:]
    private var pollTasks: [String: Task<Void, Never>] = [:]

    public init(client: any DaemonClient) {
        self.client = client
    }

    // MARK: Capabilities

    /// Test-only escape hatch: forces the owned_subscriptions answer the client's hello would
    /// carry on a modern socket. Lets tests exercise the subscribe + release path end to end.
    internal func setOwnedSubscriptionCapabilityForTesting(_ value: Bool) {
        capabilities.ownedSubscriptions = value
    }

    /// Reads `features` once per connection; nothing else here checks them.
    public func update(serverInfo: ServerInfo?) {
        capabilities.observation = serverInfo?.hasFeature("workspaceSetupObservation") ?? false
        capabilities.run = serverInfo?.hasFeature("workspaceSetupRun") ?? false
        // Read the client's *hello* capability, not the host's feature flag: the daemon only
        // accepts owned subscriptions on sockets that advertised owned_subscriptions, and only
        // runs the subscribe RPC when the client also advertises the observation companion.
        // The host still has to advertise the feature, because a daemon that never heard of the
        // capability keeps the legacy detach paths (`OwnedSubscriptions`).
        capabilities.ownedSubscriptions =
            ClientCapabilities.implemented[SetupCapabilityNames.ownedSubscriptions] == true
            && (serverInfo?.supportsOwnedSubscriptions ?? false)
    }

    // MARK: Observing

    /// Starts observing a workspace. Uses the subscribe path when the host advertises observation
    /// *and* the connection is modern; otherwise falls back to a one-shot status read and a poll
    /// while the snapshot says `running`.
    public func observe(_ workspaceId: String) async {
        if capabilities.observation {
            if capabilities.ownedSubscriptions {
                await subscribe(workspaceId)
            } else {
                await refresh(workspaceId)
                startPollingIfRunning(workspaceId)
            }
        } else {
            error = "This daemon cannot observe setup runs."
        }
    }

    /// Reads the status snapshot once.
    public func refresh(_ workspaceId: String) async {
        guard capabilities.observation else {
            error = "This daemon cannot observe setup runs."
            return
        }
        do {
            let response = try await client.send(WorkspaceSetupStatusRequest(workspaceId: workspaceId))
            applySnapshot(response.snapshot, for: workspaceId)
            error = nil
        } catch {
            self.error = setupErrorText(error)
        }
    }

    /// Stops observing and releases the owned subscription if one is held.
    public func stopObserving(_ workspaceId: String) async {
        pollTasks[workspaceId]?.cancel()
        pollTasks.removeValue(forKey: workspaceId)
        isPolling.remove(workspaceId)
        if let subscriptionId = subscriptionIds.removeValue(forKey: workspaceId) {
            await client.releaseOwnedSubscription(subscriptionId)
        }
    }

    /// After a reconnect the daemon forgot every owned subscription: drop the stale ids and
    /// re-subscribe the workspaces this store was observing.
    internal func resubscribe() async {
        let observed = subscriptionIds.keys.sorted()
        subscriptionIds.removeAll()
        guard capabilities.ownedSubscriptions else { return }
        for workspaceId in observed {
            await subscribe(workspaceId)
        }
    }

    /// Reruns the setup command; returns true when the daemon accepted the run.
    /// Requires `features.workspaceSetupRun`.
    public func runSetup(_ workspaceId: String) async -> Bool {
        guard capabilities.run else {
            error = "This daemon cannot rerun setup."
            return false
        }
        do {
            let response = try await client.send(WorkspaceSetupRunRequest(workspaceId: workspaceId))
            if let message = response.error {
                error = message
                return false
            }
            guard response.started else {
                error = "The daemon did not start setup."
                return false
            }
            error = nil
            // A run just started; switch to watching it.
            await refresh(workspaceId)
            startPollingIfRunning(workspaceId)
            return true
        } catch {
            self.error = setupErrorText(error)
            return false
        }
    }

    /// The snapshot for one workspace, when one has been observed or read.
    public func snapshot(for workspaceId: String) -> WorkspaceSetupSnapshot? {
        snapshots[workspaceId]
    }

    /// The server-assigned owned subscription id for a workspace, when the subscribe path is in
    /// use. Nil while polling a legacy socket, or before the subscribe response arrives.
    public func subscriptionId(for workspaceId: String) -> String? {
        subscriptionIds[workspaceId]
    }

    /// Whether setup is running, failed or blocked (the quiet-line cases).
    public func needsAttention(_ workspaceId: String) -> Bool {
        guard let status = snapshots[workspaceId]?.status else { return false }
        switch status {
        case .running, .failed, .blocked: return true
        case .completed, .unknown: return false
        }
    }

    // MARK: Subscribe path (owned subscriptions only)

    private func subscribe(_ workspaceId: String) async {
        // A modern socket treats every subscribe as a new ownership; drop the previous one first
        // so repeated panel appearances don't accumulate duplicate progress frames.
        if let previous = subscriptionIds.removeValue(forKey: workspaceId) {
            await client.releaseOwnedSubscription(previous)
        }
        do {
            let response = try await client.send(WorkspaceSetupSubscribeRequest(workspaceId: workspaceId))
            if let subscriptionId = response.subscriptionId {
                subscriptionIds[workspaceId] = subscriptionId
            }
            applySnapshot(response.snapshot, for: workspaceId)
            error = nil
        } catch {
            // The daemon rejects subscribe when the socket isn't modern; degrade to polling.
            self.error = nil
            await refresh(workspaceId)
            startPollingIfRunning(workspaceId)
        }
    }

    /// Starts a 1 s refresh loop while the snapshot says `running`; cancels otherwise.
    private func startPollingIfRunning(_ workspaceId: String) {
        guard snapshots[workspaceId]?.status == .running else {
            pollTasks[workspaceId]?.cancel()
            pollTasks.removeValue(forKey: workspaceId)
            isPolling.remove(workspaceId)
            return
        }
        guard pollTasks[workspaceId] == nil else { return }
        isPolling.insert(workspaceId)
        let client = self.client
        pollTasks[workspaceId] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let response = try? await client.send(
                    WorkspaceSetupStatusRequest(workspaceId: workspaceId)) else { continue }
                await MainActor.run {
                    self.applySnapshot(response.snapshot, for: workspaceId)
                }
                if response.snapshot?.status != .running {
                    await MainActor.run { self.stopPolling(workspaceId) }
                    return
                }
            }
        }
    }

    private func stopPolling(_ workspaceId: String) {
        pollTasks.removeValue(forKey: workspaceId)
        isPolling.remove(workspaceId)
    }

    private func applySnapshot(_ snapshot: WorkspaceSetupSnapshot?, for workspaceId: String) {
        if let snapshot {
            snapshots[workspaceId] = snapshot
        }
        // Poll while running, stop otherwise, whether the snapshot came from push or poll.
        startPollingIfRunning(workspaceId)
    }

    // MARK: Daemon events

    /// `workspace_setup_progress` frames routed from `HostSession`. Anything else is ignored.
    public func handle(messageType: String, raw: Data) {
        guard messageType == "workspace_setup_progress" else { return }
        guard let progress = try? JSONDecoder().decode(
            SessionPayloadEnvelope<WorkspaceSetupProgress>.self, from: raw).payload else { return }
        applySnapshot(progress.snapshot, for: progress.workspaceId)
        error = nil
    }

    // MARK: Internals

    private func setupErrorText(_ error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
