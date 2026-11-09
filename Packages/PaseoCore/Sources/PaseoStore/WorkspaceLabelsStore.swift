import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// The label catalog: every label on this host (name + color), kept live by the
/// `workspace.label.update` subscription. Assignments live on the workspace descriptors
/// (`WorkspaceDescriptor.labels`), kept fresh by the directory's own `workspace_update` feed.
///
/// IMPLEMENTATION TICKET: docs/tickets/M2.12-workspace-labels.md
@MainActor @Observable
public final class WorkspaceLabelsStore {
    public enum LoadPhase: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public private(set) var phase: LoadPhase = .idle
    /// The catalog, sorted by name (case-insensitive).
    public private(set) var labels: [WorkspaceLabelDefinition] = []
    public private(set) var error: String?
    /// Last failed create/rename/recolor/delete/assign.
    public private(set) var actionError: String?
    public private(set) var isWorking = false
    /// `features.workspaceLabels` (added in v0.5.0).
    public private(set) var supportsLabels = false
    /// `features.ownedSubscriptions` plus this client's hello capability.
    public private(set) var supportsOwnedSubscriptions = false

    private let client: any DaemonClient
    private var subscriptionId: String?
    private var syncCursor: SyncCursor?
    /// A push arrived while the cursor didn't line up; resync on the next foreground.
    public private(set) var needsResync = false
    /// The catalog may have changed in a way a cursor catch-up can't express (a kind we
    /// don't know, or pushes before the first list): force a full snapshot resync.
    private var forceSnapshot = false

    private struct SyncCursor: Sendable, Equatable {
        var generation: String
        var afterSeq: Int
    }

    public init(client: any DaemonClient) {
        self.client = client
    }

    // MARK: Loading

    /// Lists the catalog and subscribes this socket to `workspace.label.update` pushes.
    /// No-op on daemons without the feature: sending `workspace.label.list.request` there
    /// would just fail.
    public func load() async {
        phase = .loading
        error = nil
        guard supportsLabels else {
            labels = []
            syncCursor = nil
            phase = .ready
            return
        }
        do {
            let response = try await client.send(WorkspaceLabelListRequest(subscribe: .init()))
            let previousSubscriptionId = subscriptionId
            subscriptionId = response.subscriptionId
            // A modern socket creates a new owned subscription per subscribe; an old one would
            // keep delivering the same changes (and break the seq cursor). Release it.
            if supportsOwnedSubscriptions, let previousSubscriptionId,
                previousSubscriptionId != subscriptionId
            {
                await client.releaseOwnedSubscription(previousSubscriptionId)
            }
            switch response.sync.mode {
            case .snapshot:
                labels = sorted(response.labels)
            case .changes:
                applyChanges(labels: response.labels, removals: response.sync.removals)
            case .unknown:
                // A mode we don't know: trust the full snapshot (safest).
                labels = sorted(response.labels)
            }
            syncCursor = SyncCursor(generation: response.sync.generation, afterSeq: response.sync.headSeq)
            phase = .ready
        } catch {
            self.error = paseoStoreErrorText(error)
            phase = .failed(paseoStoreErrorText(error))
        }
    }

    /// Applies one `workspace.label.update` push. Out-of-order pushes (gaps) resync the catalog.
    internal func handle(_ update: WorkspaceLabelUpdate) {
        guard let cursor = syncCursor else {
            // No baseline yet (load not run or failed): nothing to catch up from, so the next
            // resync must be a full snapshot, not an incremental cursor sync.
            needsResync = true
            forceSnapshot = true
            return
        }
        if update.generation != cursor.generation || update.seq != cursor.afterSeq + 1 {
            needsResync = true
            return
        }
        apply(update)
        syncCursor = SyncCursor(generation: update.generation, afterSeq: update.seq)
    }

    /// Catches the catalog up after a gap, without re-subscribing: a `sync` request with the
    /// current cursor returns just the changes since it (or a full `snapshot` if the daemon's
    /// journal no longer covers it). Unknown update kinds force a full re-list instead.
    internal func resyncIfNeeded() async {
        guard needsResync else { return }
        needsResync = false
        if forceSnapshot || syncCursor == nil {
            forceSnapshot = false
            await load()
            return
        }
        if let cursor = syncCursor,
            let response = try? await client.send(
                WorkspaceLabelListRequest(
                    sync: .init(generation: cursor.generation, afterSeq: cursor.afterSeq)))
        {
            switch response.sync.mode {
            case .snapshot:
                labels = sorted(response.labels)
            case .changes:
                applyChanges(labels: response.labels, removals: response.sync.removals)
            case .unknown:
                labels = sorted(response.labels)
            }
            syncCursor = SyncCursor(generation: response.sync.generation, afterSeq: response.sync.headSeq)
            return
        }
        await load()
    }

    // MARK: Mutations

    /// Creates a label and assigns it to `workspaceId` in one RPC (`assignment.set` with an
    /// unknown label mints the catalog entry).
    @discardableResult
    public func createAndAssign(
        name: String, color: WorkspaceLabelColor, toWorkspace workspaceId: String
    ) async -> Bool {
        await setAssignment(
            workspaceId: workspaceId,
            label: WorkspaceLabelDefinition(name: normalized(name), color: color),
            assigned: true)
    }

    /// Assigns (or unassigns) a label on a workspace. Unknown labels are minted.
    @discardableResult
    public func setAssignment(
        workspaceId: String, label: WorkspaceLabelDefinition, assigned: Bool
    ) async -> Bool {
        guard supportsLabels else {
            actionError = "This daemon does not support workspace labels."
            return false
        }
        let name = normalized(label.name)
        guard !name.isEmpty else {
            actionError = "A label name is required."
            return false
        }
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await client.send(
                WorkspaceLabelAssignmentSetRequest(
                    workspaceId: workspaceId,
                    label: WorkspaceLabelDefinition(name: name, color: label.color),
                    assigned: assigned))
            upsert(response.label)
            workspaceDirectory?.patchLabels(workspaceId, response.workspaceLabels)
            actionError = nil
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    /// Renames and/or recolors a label in one RPC (`update.request`).
    @discardableResult
    public func updateLabel(
        name: String, newName: String? = nil, color: WorkspaceLabelColor? = nil
    ) async -> Bool {
        guard supportsLabels else {
            actionError = "This daemon does not support workspace labels."
            return false
        }
        let trimmed = normalized(name)
        guard !trimmed.isEmpty else {
            actionError = "A label name is required."
            return false
        }
        if let newName, normalized(newName).isEmpty {
            actionError = "A label name is required."
            return false
        }
        guard newName != nil || color != nil else {
            actionError = "Nothing to update."
            return false
        }
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await client.send(
                WorkspaceLabelUpdateRequest(
                    name: trimmed,
                    newName: normalized(newName).flatMap { $0 == trimmed ? nil : $0 },
                    color: color))
            // The update event patches the catalog; patch eagerly too so the row feels instant.
            labels.removeAll {
                key($0.name) == key(trimmed) || key($0.name) == key(response.label.name)
            }
            labels.append(response.label)
            labels = sorted(labels)
            actionError = nil
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    /// Deletes a label everywhere (`delete.request`). Returns the affected workspace count on success.
    @discardableResult
    public func deleteLabel(name: String) async -> Bool {
        guard supportsLabels else {
            actionError = "This daemon does not support workspace labels."
            return false
        }
        let trimmed = normalized(name)
        guard !trimmed.isEmpty else {
            actionError = "A label name is required."
            return false
        }
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await client.send(WorkspaceLabelDeleteRequest(name: trimmed))
            labels.removeAll { key($0.name) == key(trimmed) }
            _ = response
            actionError = nil
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    /// Read-only count of workspaces the delete would hit (`delete.inspect.request`).
    public func inspectDelete(name: String) async -> Int? {
        guard supportsLabels else { return nil }
        let trimmed = normalized(name)
        guard !trimmed.isEmpty else { return nil }
        do {
            let response = try await client.send(WorkspaceLabelDeleteInspectRequest(name: trimmed))
            return response.affectedWorkspaceCount
        } catch {
            actionError = paseoStoreErrorText(error)
            return nil
        }
    }

    // MARK: HostSession handoff

    internal func update(serverInfo: ServerInfo?) {
        supportsLabels = serverInfo?.hasFeature("workspaceLabels") ?? false
        supportsOwnedSubscriptions = serverInfo?.supportsOwnedSubscriptions ?? false
    }

    /// A reconnect drops the daemon's owned subscriptions; forget the id without releasing it on
    /// the dead socket.
    internal func prepareForReconnect() {
        subscriptionId = nil
    }

    /// Set by `HostSession` at construction; used to mirror assignment responses into the
    /// workspace descriptors without waiting for the next `workspace_update` push.
    internal var workspaceDirectory: WorkspaceDirectory?

    // MARK: Internals

    private func apply(_ update: WorkspaceLabelUpdate) {
        switch update {
        case .upsert(let label, let previousName, _, _):
            if let previousName {
                labels.removeAll { key($0.name) == key(previousName) }
            }
            upsert(label)
        case .remove(let name, _, _):
            labels.removeAll { key($0.name) == key(name) }
        case .unknown:
            needsResync = true
            forceSnapshot = true
        }
    }

    private func applyChanges(
        labels newLabels: [WorkspaceLabelDefinition], removals: [WorkspaceLabelListRequest.SyncMetadata.Removal]
    ) {
        for removal in removals where !removal.name.isEmpty {
            labels.removeAll { key($0.name) == key(removal.name) }
        }
        for label in newLabels {
            upsert(label)
        }
    }

    private func upsert(_ label: WorkspaceLabelDefinition) {
        if let index = labels.firstIndex(where: { key($0.name) == key(label.name) }) {
            labels[index] = label
        } else {
            labels.append(label)
        }
        labels = sorted(labels)
    }

    private func sorted(_ list: [WorkspaceLabelDefinition]) -> [WorkspaceLabelDefinition] {
        list.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func normalized(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalized(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func key(_ name: String) -> String {
        normalized(name).lowercased()
    }
}
