import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// The daemon's recurring agent runs: list, inspect, create, update, pause/resume, run once,
/// logs and delete. Heartbeats are just schedules whose target is an existing agent, so they use
/// the same store.
///
/// There are no push events for schedules: call `load()` to refresh after a mutation, and the
/// daemon is polled by the caller while a screen is open.
///
/// IMPLEMENTATION TICKET: docs/tickets/PHASE3-BACKEND.md (T9)
@MainActor @Observable
public final class SchedulesStore {
    public enum Phase: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    /// The daemon's list order (createdAt ascending).
    public private(set) var schedules: [ScheduleSummary] = []
    /// Last error from `load`, for the list's error state.
    public private(set) var error: String?
    /// Last failed mutation, for a banner. Cleared by the next success.
    public private(set) var actionError: String?
    /// Plain capability flag, read once from `server_info.permissions`: every schedule RPC needs
    /// `automation.manage`.
    public private(set) var isSupported = true
    /// The full record from the last `inspect`, `update` or `runOnce`.
    public private(set) var selected: StoredSchedule?
    /// Which schedule `selected` describes. Nil before anything is inspected.
    public private(set) var selectedId: String?
    /// Runs from the last `loadLogs`, `inspect` or `runOnce`.
    public private(set) var runs: [ScheduleRun] = []
    public private(set) var isLoadingLogs = false
    /// The schedule returned by the last successful `create`.
    public private(set) var lastCreated: ScheduleSummary?

    private let client: any DaemonClient

    public init(client: any DaemonClient) {
        self.client = client
    }

    // MARK: Read state

    public func schedule(id: String) -> ScheduleSummary? {
        schedules.first { $0.id == id }
    }

    /// Loads the list (pull to refresh). Keeps the old rows on failure so a transient error does
    /// not blank the screen.
    public func load() async {
        if phase != .ready { phase = .loading }
        do {
            let response = try await client.send(ScheduleListRequest())
            if let error = response.error {
                self.error = error
                phase = .failed(error)
                return
            }
            // No push events for schedules: the list polls. Publish only on real change so
            // a quiet poll neither re-evaluates every row nor disturbs the reader's scroll.
            if response.schedules != schedules {
                schedules = response.schedules
            }
            error = nil
            phase = .ready
        } catch {
            let message = paseoStoreErrorText(error)
            self.error = message
            phase = .failed(message)
        }
    }

    /// Same as `load()`; kept for symmetry with the other stores' pull-to-refresh.
    public func refresh() async {
        await load()
    }

    /// Loads the full record (including `runs`) into `selected`.
    public func inspect(_ scheduleId: String) async -> Bool {
        actionError = nil
        do {
            let response = try await client.send(ScheduleInspectRequest(scheduleId: scheduleId))
            if let error = response.error {
                actionError = error
                return false
            }
            guard let schedule = response.schedule else {
                actionError = "The daemon returned no schedule."
                return false
            }
            apply(schedule)
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    /// Loads the run history into `runs`.
    public func loadLogs(_ scheduleId: String) async -> Bool {
        actionError = nil
        isLoadingLogs = true
        defer { isLoadingLogs = false }
        do {
            let response = try await client.send(ScheduleLogsRequest(scheduleId: scheduleId))
            if let error = response.error {
                actionError = error
                return false
            }
            selectedId = scheduleId
            runs = response.runs
            if selected?.id != scheduleId { selected = nil }
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    // MARK: Mutations

    /// Creates a schedule and inserts it into the list. Returns nil with `actionError` set when
    /// the daemon rejects it.
    public func create(_ draft: ScheduleDraft) async -> ScheduleSummary? {
        actionError = nil
        lastCreated = nil

        let prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            actionError = "A schedule prompt is required."
            return nil
        }
        if case .cron(let expression, _) = draft.cadence,
            expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            actionError = "A cron expression is required."
            return nil
        }
        if let maxRuns = draft.maxRuns, maxRuns <= 0 {
            actionError = "Max runs must be a positive number."
            return nil
        }
        if case .unknown = draft.target {
            actionError = "This daemon does not support that schedule target."
            return nil
        }

        let request = ScheduleCreateRequest(
            prompt: prompt,
            cadence: draft.cadence,
            target: draft.target,
            name: normalizedName(draft.name),
            maxRuns: draft.maxRuns,
            expiresAt: draft.expiresAt,
            runOnCreate: draft.runOnCreate ? true : nil)

        do {
            let response = try await client.send(request)
            if let error = response.error {
                actionError = error
                return nil
            }
            guard let schedule = response.schedule else {
                actionError = "The daemon returned no schedule."
                return nil
            }
            upsert(schedule)
            lastCreated = schedule
            return schedule
        } catch {
            actionError = paseoStoreErrorText(error)
            return nil
        }
    }

    /// Creates a heartbeat: a cron schedule that prompts one existing agent. Heartbeats have no
    /// separate wire type; this is the `agent` target from schedule section 14.2.
    public func createHeartbeat(
        agentId: String,
        prompt: String,
        cron: String,
        timezone: String? = nil,
        name: String? = nil,
        maxRuns: Int? = nil
    ) async -> ScheduleSummary? {
        await create(
            ScheduleDraft(
                name: name, prompt: prompt,
                cadence: .cron(expression: cron, timezone: timezone),
                target: .agent(agentId: agentId), maxRuns: maxRuns))
    }

    /// Applies a partial update. `edits` decides which fields change; an explicit `clear` sends
    /// `null` for a field the wire allows to be cleared.
    public func update(_ scheduleId: String, _ edits: ScheduleEdits) async -> Bool {
        actionError = nil

        var prompt: String?
        if let raw = edits.prompt {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                actionError = "A schedule prompt is required."
                return false
            }
            prompt = trimmed
        }

        let request = ScheduleUpdateRequest(
            scheduleId: scheduleId,
            name: edits.name,
            prompt: prompt,
            cadence: edits.cadence,
            newAgentConfig: edits.newAgentConfig,
            maxRuns: edits.maxRuns,
            expiresAt: edits.expiresAt)

        do {
            let response = try await client.send(request)
            if let error = response.error {
                actionError = error
                return false
            }
            guard let schedule = response.schedule else {
                actionError = "The daemon returned no schedule."
                return false
            }
            apply(schedule)
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    public func pause(_ scheduleId: String) async -> Bool {
        actionError = nil
        do {
            let response = try await client.send(SchedulePauseRequest(scheduleId: scheduleId))
            if let error = response.error {
                actionError = error
                return false
            }
            guard let schedule = response.schedule else {
                actionError = "The daemon returned no schedule."
                return false
            }
            upsert(schedule)
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    public func resume(_ scheduleId: String) async -> Bool {
        actionError = nil
        do {
            let response = try await client.send(ScheduleResumeRequest(scheduleId: scheduleId))
            if let error = response.error {
                actionError = error
                return false
            }
            guard let schedule = response.schedule else {
                actionError = "The daemon returned no schedule."
                return false
            }
            upsert(schedule)
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    public func runOnce(_ scheduleId: String) async -> Bool {
        actionError = nil
        do {
            let response = try await client.send(ScheduleRunOnceRequest(scheduleId: scheduleId))
            if let error = response.error {
                actionError = error
                return false
            }
            guard let schedule = response.schedule else {
                actionError = "The daemon returned no schedule."
                return false
            }
            apply(schedule)
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    public func delete(_ scheduleId: String) async -> Bool {
        actionError = nil
        do {
            let response = try await client.send(ScheduleDeleteRequest(scheduleId: scheduleId))
            if let error = response.error {
                actionError = error
                return false
            }
            schedules.removeAll { $0.id == response.scheduleId || $0.id == scheduleId }
            if selectedId == scheduleId || selectedId == response.scheduleId {
                clearSelection()
            }
            if lastCreated?.id == scheduleId || lastCreated?.id == response.scheduleId {
                lastCreated = nil
            }
            return true
        } catch {
            actionError = paseoStoreErrorText(error)
            return false
        }
    }

    /// Drops the inspected schedule so a detail screen can close.
    public func clearSelection() {
        selected = nil
        selectedId = nil
        runs = []
    }

    // MARK: HostSession handoff

    /// Called once per `server_info`; the capability is read here and nowhere else.
    internal func serverInfoChanged(_ info: ServerInfo?) {
        guard let info else { return }
        isSupported = info.permissions?.contains("automation.manage") ?? true
    }

    // MARK: Internals

    private func apply(_ schedule: StoredSchedule) {
        selected = schedule
        selectedId = schedule.id
        runs = schedule.runs
        upsert(schedule.summary)
    }

    private func upsert(_ schedule: ScheduleSummary) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
        if var stored = selected, stored.id == schedule.id {
            stored.summary = schedule
            selected = stored
        }
    }

    private func normalizedName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A new schedule: the prompt, when it fires, and where each run goes.
public struct ScheduleDraft: Sendable {
    public var name: String?
    public var prompt: String
    public var cadence: ScheduleCadence
    public var target: ScheduleTarget
    public var maxRuns: Int?
    public var expiresAt: String?
    public var runOnCreate: Bool

    public init(
        name: String? = nil,
        prompt: String,
        cadence: ScheduleCadence,
        target: ScheduleTarget,
        maxRuns: Int? = nil,
        expiresAt: String? = nil,
        runOnCreate: Bool = false
    ) {
        self.name = name
        self.prompt = prompt
        self.cadence = cadence
        self.target = target
        self.maxRuns = maxRuns
        self.expiresAt = expiresAt
        self.runOnCreate = runOnCreate
    }
}

/// A partial `schedule/update`. Unchanged fields stay as they are; `SchedulePatch.clear` sends
/// the wire's explicit `null`.
public struct ScheduleEdits: Sendable {
    public var name: SchedulePatch<String>
    public var prompt: String?
    public var cadence: ScheduleCadence?
    public var maxRuns: SchedulePatch<Int>
    public var expiresAt: SchedulePatch<String>
    public var newAgentConfig: ScheduleNewAgentConfigUpdate?

    public init(
        name: SchedulePatch<String> = .unchanged,
        prompt: String? = nil,
        cadence: ScheduleCadence? = nil,
        maxRuns: SchedulePatch<Int> = .unchanged,
        expiresAt: SchedulePatch<String> = .unchanged,
        newAgentConfig: ScheduleNewAgentConfigUpdate? = nil
    ) {
        self.name = name
        self.prompt = prompt
        self.cadence = cadence
        self.maxRuns = maxRuns
        self.expiresAt = expiresAt
        self.newAgentConfig = newAgentConfig
    }
}

/// The badge a row shows. The daemon stores only `active`/`paused`/`completed`; expiry and a
/// missing agent target are computed here, as the web app does.
public enum ScheduleState: Sendable, Hashable {
    case active
    case paused
    case expired
    case finished
    case targetGone
    case unknown

    /// The "ended" filter in the schedules screen.
    public var isEnded: Bool {
        switch self {
        case .active, .paused, .unknown: false
        case .expired, .finished, .targetGone: true
        }
    }
}

extension ScheduleSummary {
    /// `knownAgentIds` nil means the agent directory has not loaded yet, so a missing `agent`
    /// target is not proof the agent is gone.
    public func state(now: Date = Date(), knownAgentIds: Set<String>? = nil) -> ScheduleState {
        if let expiresAt, let date = PaseoDate.parse(expiresAt), date <= now {
            return .expired
        }
        if case .agent(let agentId) = target, let knownAgentIds, !knownAgentIds.contains(agentId) {
            return .targetGone
        }
        switch status {
        case .active: return .active
        case .paused: return .paused
        case .completed: return .finished
        case .unknown: return .unknown
        }
    }
}

extension StoredSchedule {
    public func state(now: Date = Date(), knownAgentIds: Set<String>? = nil) -> ScheduleState {
        summary.state(now: now, knownAgentIds: knownAgentIds)
    }
}
