import Foundation

// Schedules: daemon-managed recurring agent runs, and the heartbeats expressed as `agent` targets.
// The RPCs are slash-namespaced flat names (`schedule/create`), not dotted like newer areas.
//
// Source: packages/protocol/src/schedule/types.ts `ScheduleStatusSchema`, `ScheduleCadenceSchema`,
// `ScheduleTargetSchema`, `ScheduleRunSchema`, `StoredScheduleSchema`, `ScheduleSummarySchema`, and
// packages/protocol/src/schedule/rpc-schemas.ts `ScheduleCreateRequestSchema`,
// `ScheduleListRequestSchema`, `ScheduleInspectRequestSchema`, `ScheduleLogsRequestSchema`,
// `SchedulePauseRequestSchema`, `ScheduleResumeRequestSchema`, `ScheduleDeleteRequestSchema`,
// `ScheduleRunOnceRequestSchema`, `ScheduleUpdateRequestSchema` and their responses.
//
// Forward compatibility: unknown enum values are kept, missing nullable fields decode as nil, and
// unknown fields on a newer daemon are ignored.

// Source: schedule/types.ts `ScheduleStatusSchema`.
public enum ScheduleStatus: Sendable, Hashable, Decodable {
    case active
    case paused
    case completed
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "active": self = .active
        case "paused": self = .paused
        case "completed": self = .completed
        case let other: self = .unknown(other)
        }
    }
}

// Source: schedule/types.ts `ScheduleTargetSchema.new-agent.config.isolation`.
public enum ScheduleIsolation: Sendable, Hashable, Codable {
    case local
    case worktree
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "local": self = .local
        case "worktree": self = .worktree
        case let other: self = .unknown(other)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .local: try c.encode("local")
        case .worktree: try c.encode("worktree")
        case .unknown(let raw): try c.encode(raw)
        }
    }
}

// Source: schedule/types.ts `ScheduleCadenceSchema`.

/// When a schedule fires: a fixed interval, or a cron expression in an optional timezone.
public enum ScheduleCadence: Sendable, Hashable, Codable {
    case every(everyMs: Int)
    case cron(expression: String, timezone: String?)
    case unknown(String)

    private enum K: String, CodingKey {
        case type, everyMs, expression, timezone
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .type) {
        case "every":
            self = .every(everyMs: try c.decode(Int.self, forKey: .everyMs))
        case "cron":
            self = .cron(
                expression: try c.decode(String.self, forKey: .expression),
                timezone: try c.decodeIfPresent(String.self, forKey: .timezone))
        case let other:
            self = .unknown(other)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case .every(let everyMs):
            try c.encode("every", forKey: .type)
            try c.encode(everyMs, forKey: .everyMs)
        case .cron(let expression, let timezone):
            try c.encode("cron", forKey: .type)
            try c.encode(expression, forKey: .expression)
            try c.encodeIfPresent(timezone, forKey: .timezone)
        case .unknown(let raw):
            try c.encode(raw, forKey: .type)
        }
    }
}

// Source: schedule/types.ts `ScheduleTargetSchema.new-agent.config`.

/// The agent a `new-agent` schedule creates on each run. `cwd` is used exactly as sent: the
/// daemon does not expand `~`.
public struct ScheduleNewAgentConfig: Sendable, Hashable, Codable {
    public var provider: String
    public var cwd: String
    public var modeId: String?
    public var model: String?
    public var thinkingOptionId: String?
    public var archiveOnFinish: Bool?
    public var isolation: ScheduleIsolation?
    public var title: String?
    public var providerOptions: [String: JSONValue]?
    public var featureValues: [String: JSONValue]?
    public var systemPrompt: String?
    public var mcpServers: [String: JSONValue]?

    public init(
        provider: String,
        cwd: String,
        modeId: String? = nil,
        model: String? = nil,
        thinkingOptionId: String? = nil,
        archiveOnFinish: Bool? = nil,
        isolation: ScheduleIsolation? = nil,
        title: String? = nil,
        providerOptions: [String: JSONValue]? = nil,
        featureValues: [String: JSONValue]? = nil,
        systemPrompt: String? = nil,
        mcpServers: [String: JSONValue]? = nil
    ) {
        self.provider = provider
        self.cwd = cwd
        self.modeId = modeId
        self.model = model
        self.thinkingOptionId = thinkingOptionId
        self.archiveOnFinish = archiveOnFinish
        self.isolation = isolation
        self.title = title
        self.providerOptions = providerOptions
        self.featureValues = featureValues
        self.systemPrompt = systemPrompt
        self.mcpServers = mcpServers
    }
}

// Source: schedule/types.ts `ScheduleTargetSchema` plus the create-only `self` variant in
// schedule/rpc-schemas.ts `ScheduleCreateTargetSchema`.

/// Where a run goes: a fresh agent, an existing agent, or (create only) the caller itself.
public enum ScheduleTarget: Sendable, Hashable, Codable {
    case newAgent(ScheduleNewAgentConfig)
    case agent(agentId: String)
    /// Only `schedule/create` accepts this; stored schedules never use it.
    case selfAgent(agentId: String)
    case unknown(String)

    private enum K: String, CodingKey {
        case type, agentId, config
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .type) {
        case "new-agent":
            self = .newAgent(try c.decode(ScheduleNewAgentConfig.self, forKey: .config))
        case "agent":
            self = .agent(agentId: try c.decode(String.self, forKey: .agentId))
        case "self":
            self = .selfAgent(agentId: try c.decode(String.self, forKey: .agentId))
        case let other:
            self = .unknown(other)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case .newAgent(let config):
            try c.encode("new-agent", forKey: .type)
            try c.encode(config, forKey: .config)
        case .agent(let agentId):
            try c.encode("agent", forKey: .type)
            try c.encode(agentId, forKey: .agentId)
        case .selfAgent(let agentId):
            try c.encode("self", forKey: .type)
            try c.encode(agentId, forKey: .agentId)
        case .unknown(let raw):
            try c.encode(raw, forKey: .type)
        }
    }
}

// Source: schedule/types.ts `ScheduleRunSchema.status`.
public enum ScheduleRunStatus: Sendable, Hashable, Decodable {
    case running
    case succeeded
    case failed
    case unknown(String)

    public var isTerminal: Bool {
        switch self {
        case .running, .unknown: false
        case .succeeded, .failed: true
        }
    }

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "running": self = .running
        case "succeeded": self = .succeeded
        case "failed": self = .failed
        case let other: self = .unknown(other)
        }
    }
}

// Source: schedule/types.ts `ScheduleRunSchema`.

/// One dispatch attempt. A failed run is recorded here; it never crashes the daemon.
public struct ScheduleRun: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var scheduledFor: String
    public var startedAt: String
    public var endedAt: String?
    public var status: ScheduleRunStatus
    /// The agent the run created or prompted. Nil while running, or when creation failed.
    public var agentId: String?
    public var workspaceId: String?
    public var output: String?
    public var error: String?

    public init(
        id: String,
        scheduledFor: String,
        startedAt: String,
        endedAt: String? = nil,
        status: ScheduleRunStatus,
        agentId: String? = nil,
        workspaceId: String? = nil,
        output: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.scheduledFor = scheduledFor
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.agentId = agentId
        self.workspaceId = workspaceId
        self.output = output
        self.error = error
    }
}

// Source: schedule/types.ts `ScheduleSummarySchema` (`StoredScheduleSchema` without `runs`).

/// The row `schedule/list` returns, and what create/pause/resume return.
public struct ScheduleSummary: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var name: String?
    public var prompt: String
    public var cadence: ScheduleCadence
    public var target: ScheduleTarget
    public var status: ScheduleStatus
    public var createdAt: String
    public var updatedAt: String
    public var nextRunAt: String?
    public var lastRunAt: String?
    public var pausedAt: String?
    public var expiresAt: String?
    public var maxRuns: Int?

    public init(
        id: String,
        name: String? = nil,
        prompt: String,
        cadence: ScheduleCadence,
        target: ScheduleTarget,
        status: ScheduleStatus,
        createdAt: String,
        updatedAt: String,
        nextRunAt: String? = nil,
        lastRunAt: String? = nil,
        pausedAt: String? = nil,
        expiresAt: String? = nil,
        maxRuns: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.cadence = cadence
        self.target = target
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
        self.pausedAt = pausedAt
        self.expiresAt = expiresAt
        self.maxRuns = maxRuns
    }
}

// Source: schedule/types.ts `StoredScheduleSchema`.

/// The full record `schedule/inspect`, `schedule/update` and `schedule/run-once` return.
public struct StoredSchedule: Sendable, Hashable, Decodable, Identifiable {
    public var summary: ScheduleSummary
    public var runs: [ScheduleRun]

    public var id: String { summary.id }
    /// The newest run, if any.
    public var lastRun: ScheduleRun? { runs.last }

    public init(summary: ScheduleSummary, runs: [ScheduleRun] = []) {
        self.summary = summary
        self.runs = runs
    }

    private enum K: String, CodingKey { case runs }

    public init(from decoder: Decoder) throws {
        summary = try ScheduleSummary(from: decoder)
        runs = try decoder.container(keyedBy: K.self).decode([ScheduleRun].self, forKey: .runs)
    }
}

// Source: schedule/rpc-schemas.ts `ScheduleCreateRequestSchema`, `ScheduleCreateResponseSchema`.

public struct ScheduleCreateRequest: PaseoRequest {
    public static let type = "schedule/create"
    public static let responseType = "schedule/create/response"

    public var requestId = ""
    public var prompt: String
    public var name: String?
    public var cadence: ScheduleCadence
    public var target: ScheduleTarget
    public var maxRuns: Int?
    public var expiresAt: String?
    public var runOnCreate: Bool?

    public init(
        prompt: String,
        cadence: ScheduleCadence,
        target: ScheduleTarget,
        name: String? = nil,
        maxRuns: Int? = nil,
        expiresAt: String? = nil,
        runOnCreate: Bool? = nil
    ) {
        self.prompt = prompt
        self.cadence = cadence
        self.target = target
        self.name = name
        self.maxRuns = maxRuns
        self.expiresAt = expiresAt
        self.runOnCreate = runOnCreate
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var schedule: ScheduleSummary?
        public var error: String?
    }
}

// Source: schedule/rpc-schemas.ts `ScheduleListRequestSchema`, `ScheduleListResponseSchema`.

public struct ScheduleListRequest: PaseoRequest {
    public static let type = "schedule/list"
    public static let responseType = "schedule/list/response"

    public var requestId = ""

    public init() {}

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var schedules: [ScheduleSummary]
        public var error: String?
    }
}

// Source: schedule/rpc-schemas.ts `ScheduleInspectRequestSchema`, `ScheduleInspectResponseSchema`.

public struct ScheduleInspectRequest: PaseoRequest {
    public static let type = "schedule/inspect"
    public static let responseType = "schedule/inspect/response"

    public var requestId = ""
    public var scheduleId: String

    public init(scheduleId: String) {
        self.scheduleId = scheduleId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var schedule: StoredSchedule?
        public var error: String?
    }
}

// Source: schedule/rpc-schemas.ts `ScheduleLogsRequestSchema`, `ScheduleLogsResponseSchema`.

public struct ScheduleLogsRequest: PaseoRequest {
    public static let type = "schedule/logs"
    public static let responseType = "schedule/logs/response"

    public var requestId = ""
    public var scheduleId: String

    public init(scheduleId: String) {
        self.scheduleId = scheduleId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var runs: [ScheduleRun]
        public var error: String?
    }
}

// Source: schedule/rpc-schemas.ts `SchedulePauseRequestSchema`, `SchedulePauseResponseSchema`.

public struct SchedulePauseRequest: PaseoRequest {
    public static let type = "schedule/pause"
    public static let responseType = "schedule/pause/response"

    public var requestId = ""
    public var scheduleId: String

    public init(scheduleId: String) {
        self.scheduleId = scheduleId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var schedule: ScheduleSummary?
        public var error: String?
    }
}

// Source: schedule/rpc-schemas.ts `ScheduleResumeRequestSchema`, `ScheduleResumeResponseSchema`.

public struct ScheduleResumeRequest: PaseoRequest {
    public static let type = "schedule/resume"
    public static let responseType = "schedule/resume/response"

    public var requestId = ""
    public var scheduleId: String

    public init(scheduleId: String) {
        self.scheduleId = scheduleId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var schedule: ScheduleSummary?
        public var error: String?
    }
}

// Source: schedule/rpc-schemas.ts `ScheduleDeleteRequestSchema`, `ScheduleDeleteResponseSchema`.

public struct ScheduleDeleteRequest: PaseoRequest {
    public static let type = "schedule/delete"
    public static let responseType = "schedule/delete/response"

    public var requestId = ""
    public var scheduleId: String

    public init(scheduleId: String) {
        self.scheduleId = scheduleId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var scheduleId: String
        public var error: String?
    }
}

// Source: schedule/rpc-schemas.ts `ScheduleRunOnceRequestSchema`, `ScheduleRunOnceResponseSchema`.

public struct ScheduleRunOnceRequest: PaseoRequest {
    public static let type = "schedule/run-once"
    public static let responseType = "schedule/run-once/response"

    public var requestId = ""
    public var scheduleId: String

    public init(scheduleId: String) {
        self.scheduleId = scheduleId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var schedule: StoredSchedule?
        public var error: String?
    }
}

// Source: schedule/rpc-schemas.ts `ScheduleUpdateRequestSchema`, `ScheduleUpdateResponseSchema`.

/// Whether an optional `schedule/update` field is omitted, set, or explicitly cleared (`null`).
/// `nil` alone cannot say the difference between "leave it" and "clear it".
public enum SchedulePatch<Value: Sendable & Hashable>: Sendable, Hashable {
    case unchanged
    case set(Value)
    case clear
}

// Source: schedule/rpc-schemas.ts `ScheduleUpdateNewAgentConfigSchema`.

/// A partial new-agent config. `model`, `modeId` and `thinkingOptionId` can be cleared; the rest
/// can only be set.
public struct ScheduleNewAgentConfigUpdate: Sendable, Hashable {
    public var provider: String?
    public var model: SchedulePatch<String>
    public var modeId: SchedulePatch<String>
    public var thinkingOptionId: SchedulePatch<String>
    public var archiveOnFinish: Bool?
    public var isolation: ScheduleIsolation?
    public var cwd: String?

    public init(
        provider: String? = nil,
        model: SchedulePatch<String> = .unchanged,
        modeId: SchedulePatch<String> = .unchanged,
        thinkingOptionId: SchedulePatch<String> = .unchanged,
        archiveOnFinish: Bool? = nil,
        isolation: ScheduleIsolation? = nil,
        cwd: String? = nil
    ) {
        self.provider = provider
        self.model = model
        self.modeId = modeId
        self.thinkingOptionId = thinkingOptionId
        self.archiveOnFinish = archiveOnFinish
        self.isolation = isolation
        self.cwd = cwd
    }
}

// Source: schedule/rpc-schemas.ts `ScheduleUpdateRequestSchema`, `ScheduleUpdateResponseSchema`.

public struct ScheduleUpdateRequest: PaseoRequest {
    public static let type = "schedule/update"
    public static let responseType = "schedule/update/response"

    public var requestId = ""
    public var scheduleId: String
    public var name: SchedulePatch<String>
    public var prompt: String?
    public var cadence: ScheduleCadence?
    public var newAgentConfig: ScheduleNewAgentConfigUpdate?
    public var maxRuns: SchedulePatch<Int>
    public var expiresAt: SchedulePatch<String>

    public init(
        scheduleId: String,
        name: SchedulePatch<String> = .unchanged,
        prompt: String? = nil,
        cadence: ScheduleCadence? = nil,
        newAgentConfig: ScheduleNewAgentConfigUpdate? = nil,
        maxRuns: SchedulePatch<Int> = .unchanged,
        expiresAt: SchedulePatch<String> = .unchanged
    ) {
        self.scheduleId = scheduleId
        self.name = name
        self.prompt = prompt
        self.cadence = cadence
        self.newAgentConfig = newAgentConfig
        self.maxRuns = maxRuns
        self.expiresAt = expiresAt
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var schedule: StoredSchedule?
        public var error: String?
    }

    private enum K: String, CodingKey {
        case requestId, scheduleId, name, prompt, cadence, newAgentConfig, maxRuns, expiresAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(scheduleId, forKey: .scheduleId)
        try Self.encode(name, into: &c, forKey: .name)
        try c.encodeIfPresent(prompt, forKey: .prompt)
        try c.encodeIfPresent(cadence, forKey: .cadence)
        if let newAgentConfig {
            var nested = c.nestedContainer(
                keyedBy: ScheduleNewAgentConfigUpdate.Key.self, forKey: .newAgentConfig)
            try newAgentConfig.encode(into: &nested)
        }
        try Self.encode(maxRuns, into: &c, forKey: .maxRuns)
        try Self.encode(expiresAt, into: &c, forKey: .expiresAt)
    }

    private static func encode<Value: Sendable & Hashable & Encodable>(
        _ patch: SchedulePatch<Value>, into container: inout KeyedEncodingContainer<K>, forKey key: K
    ) throws {
        switch patch {
        case .unchanged:
            break
        case .set(let value):
            try container.encode(value, forKey: key)
        case .clear:
            try container.encodeNil(forKey: key)
        }
    }
}

extension ScheduleNewAgentConfigUpdate {
    fileprivate enum Key: String, CodingKey {
        case provider, model, modeId, thinkingOptionId, archiveOnFinish, isolation, cwd
    }

    fileprivate func encode(into container: inout KeyedEncodingContainer<Key>) throws {
        try container.encodeIfPresent(provider, forKey: .provider)
        try Self.encode(model, into: &container, forKey: .model)
        try Self.encode(modeId, into: &container, forKey: .modeId)
        try Self.encode(thinkingOptionId, into: &container, forKey: .thinkingOptionId)
        try container.encodeIfPresent(archiveOnFinish, forKey: .archiveOnFinish)
        try container.encodeIfPresent(isolation, forKey: .isolation)
        try container.encodeIfPresent(cwd, forKey: .cwd)
    }

    private static func encode(
        _ patch: SchedulePatch<String>, into container: inout KeyedEncodingContainer<Key>, forKey key: Key
    ) throws {
        switch patch {
        case .unchanged:
            break
        case .set(let value):
            try container.encode(value, forKey: key)
        case .clear:
            try container.encodeNil(forKey: key)
        }
    }
}
