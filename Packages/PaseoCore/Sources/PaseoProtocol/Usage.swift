import Foundation

// Provider plan usage ("usage reports") and the context-window meter.
// Source: messages.ts `AgentUsageSchema`, `AgentCacheWasteSchema`, `AgentModelCostSchema`,
// `ProviderUsageToneSchema`, `ProviderUsageStatusSchema`, `ProviderUsageWindowSchema`,
// `ProviderUsageBalanceSchema`, `ProviderUsageDetailSchema`, `ProviderUsageSchema`,
// `ProviderUsageListResponseMessageSchema`, `UsageProblemSchema`, `AvailableUsageReportSchema`,
// `UsageReportSchema`, `UsageReportEntrySchema`, `UsageListReportsUpdateMessageSchema`,
// `UsageListReportsResponseMessageSchema`, `UsageListReportsRequestMessageSchema`.
//
// `AgentUsage` rides `agent_update` / `fetch_agents` snapshots and `turn_completed` stream
// events; `usage.list_reports` streams one `usage.list_reports.update` per report, then a
// correlated `usage.list_reports.response`. All decoders here tolerate unknown fields.

// MARK: - Agent usage (per agent, rides the snapshot)

public struct AgentCacheWaste: Sendable, Hashable, Codable {
    public var tokens: Int
    public var costUsd: Double
    public var missCount: Int

    public init(tokens: Int, costUsd: Double, missCount: Int) {
        self.tokens = tokens
        self.costUsd = costUsd
        self.missCount = missCount
    }
}

public struct AgentModelCost: Sendable, Hashable, Codable {
    public var key: String
    public var costUsd: Double
    public var tokens: Int

    public init(key: String, costUsd: Double, tokens: Int) {
        self.key = key
        self.costUsd = costUsd
        self.tokens = tokens
    }
}

/// `AgentUsageSchema`. Every field is optional: providers report what they know.
public struct AgentUsage: Sendable, Hashable, Codable {
    public var inputTokens: Int?
    public var cachedInputTokens: Int?
    public var cacheWriteTokens: Int?
    public var outputTokens: Int?
    public var totalCostUsd: Double?
    public var contextWindowMaxTokens: Int?
    public var contextWindowUsedTokens: Int?
    public var sessionCacheHitRatePct: Double?
    public var lastTurnCacheHitRatePct: Double?
    public var cacheWaste: AgentCacheWaste?
    public var costByModel: [AgentModelCost]?

    public init(
        inputTokens: Int? = nil, cachedInputTokens: Int? = nil, cacheWriteTokens: Int? = nil,
        outputTokens: Int? = nil, totalCostUsd: Double? = nil, contextWindowMaxTokens: Int? = nil,
        contextWindowUsedTokens: Int? = nil, sessionCacheHitRatePct: Double? = nil,
        lastTurnCacheHitRatePct: Double? = nil, cacheWaste: AgentCacheWaste? = nil,
        costByModel: [AgentModelCost]? = nil
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.outputTokens = outputTokens
        self.totalCostUsd = totalCostUsd
        self.contextWindowMaxTokens = contextWindowMaxTokens
        self.contextWindowUsedTokens = contextWindowUsedTokens
        self.sessionCacheHitRatePct = sessionCacheHitRatePct
        self.lastTurnCacheHitRatePct = lastTurnCacheHitRatePct
        self.cacheWaste = cacheWaste
        self.costByModel = costByModel
    }
}

// MARK: - Provider usage (host-side plan quotas)

/// `ProviderUsageToneSchema`. Unknown values decode as `.unknown`.
public enum ProviderUsageTone: Sendable, Hashable, Codable {
    case `default`, ok, warning, danger
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "default": self = .default
        case "ok": self = .ok
        case "warning": self = .warning
        case "danger": self = .danger
        default: self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }

    public var wireValue: String {
        switch self {
        case .default: "default"
        case .ok: "ok"
        case .warning: "warning"
        case .danger: "danger"
        case .unknown(let raw): raw
        }
    }
}

/// `ProviderUsageStatusSchema`.
public enum ProviderUsageStatus: Sendable, Hashable, Codable {
    case available, unavailable, error
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "available": self = .available
        case "unavailable": self = .unavailable
        case "error": self = .error
        default: self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }

    public var wireValue: String {
        switch self {
        case .available: "available"
        case .unavailable: "unavailable"
        case .error: "error"
        case .unknown(let raw): raw
        }
    }
}

public struct ProviderUsageWindow: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var label: String
    public var shortLabel: String?
    public var summary: Bool?
    public var usedPct: Double?
    public var remainingPct: Double?
    public var resetsAt: String?
    public var runsOutAt: String?
    public var shortfallPct: Double?
    public var tone: ProviderUsageTone?
}

public struct ProviderUsageBalance: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var label: String
    public var used: Double?
    public var remaining: Double?
    public var limit: Double?
    public var unit: Unit
    public var resetsAt: String?
    public var tone: ProviderUsageTone?

    public enum Unit: Sendable, Hashable, Codable {
        case usd, credits, requests, tokens
        case unknown(String)

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            switch raw {
            case "usd": self = .usd
            case "credits": self = .credits
            case "requests": self = .requests
            case "tokens": self = .tokens
            default: self = .unknown(raw)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(wireValue)
        }

        public var wireValue: String {
            switch self {
            case .usd: "usd"
            case .credits: "credits"
            case .requests: "requests"
            case .tokens: "tokens"
            case .unknown(let raw): raw
            }
        }
    }
}

public struct ProviderUsageDetail: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var label: String
    public var value: String
    public var tone: ProviderUsageTone?
}

/// `ProviderUsageSchema` — the legacy (`provider.usage.list`) per-provider entry.
public struct ProviderUsage: Sendable, Hashable, Decodable {
    public var providerId: String
    public var displayName: String
    public var status: ProviderUsageStatus
    public var planLabel: String?
    public var sourceLabel: String?
    public var fetchedAt: String?
    public var nextRefreshAt: String?
    public var windows: [ProviderUsageWindow]
    public var balances: [ProviderUsageBalance]?
    public var details: [ProviderUsageDetail]?
    public var error: String?
}

public struct ProviderUsageListRequest: PaseoRequest {
    public static let type = "provider.usage.list.request"
    public static let responseType = "provider.usage.list.response"
    public typealias Response = ProviderUsageListResponse
    public var requestId = ""
    public init() {}
}

public struct ProviderUsageListResponse: Decodable, Sendable {
    public var requestId: String
    public var fetchedAt: String
    public var providers: [ProviderUsage]
}

/// `UsageProblemSchema` — the per-source problem behind an `unavailable` report.
public enum UsageProblem: Sendable, Hashable, Decodable {
    case expired(expiresAt: String, refreshedBy: String?)
    case rejected(status: Int, refreshedBy: String?)
    case noQuota(detail: String)
    case unknown(JSONValue)

    private enum K: String, CodingKey { case kind, expiresAt, refreshedBy, status, detail }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "expired":
            self = .expired(
                expiresAt: try c.decode(String.self, forKey: .expiresAt),
                refreshedBy: try c.decodeIfPresent(String.self, forKey: .refreshedBy))
        case "rejected":
            self = .rejected(
                status: try c.decode(Int.self, forKey: .status),
                refreshedBy: try c.decodeIfPresent(String.self, forKey: .refreshedBy))
        case "no_quota":
            self = .noQuota(detail: try c.decode(String.self, forKey: .detail))
        default:
            self = .unknown(try JSONValue(from: decoder))
        }
    }
}

public struct AvailableUsageReport: Sendable, Hashable, Decodable {
    public var status = "available"
    public var planLabel: String?
    public var windows: [ProviderUsageWindow]
    public var balances: [ProviderUsageBalance]?
    public var details: [ProviderUsageDetail]?

    public init(
        planLabel: String? = nil, windows: [ProviderUsageWindow] = [],
        balances: [ProviderUsageBalance]? = nil, details: [ProviderUsageDetail]? = nil
    ) {
        status = "available"
        self.planLabel = planLabel
        self.windows = windows
        self.balances = balances
        self.details = details
    }

    private enum K: String, CodingKey {
        case planLabel, windows, balances, details
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        status = "available"
        planLabel = try c.decodeIfPresent(String.self, forKey: .planLabel)
        windows = try c.decodeIfPresent([ProviderUsageWindow].self, forKey: .windows) ?? []
        balances = try c.decodeIfPresent([ProviderUsageBalance].self, forKey: .balances)
        details = try c.decodeIfPresent([ProviderUsageDetail].self, forKey: .details)
    }
}

/// `UsageReportSchema` — discriminated on `status`.
public enum UsageReport: Sendable, Hashable, Decodable {
    case available(AvailableUsageReport)
    case unavailable(problem: UsageProblem)
    case failure(error: String)

    private enum K: String, CodingKey { case status, problem, error }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .status) {
        case "available":
            self = .available(try AvailableUsageReport(from: decoder))
        case "unavailable":
            self = .unavailable(problem: try c.decode(UsageProblem.self, forKey: .problem))
        case "error":
            self = .failure(error: try c.decode(String.self, forKey: .error))
        default:
            self = .failure(error: "unknown report status")
        }
    }
}

/// `UsageReportEntrySchema` — one account the host reports usage for.
public struct UsageReportEntry: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var accountLabel: String?
    public var fetchedAt: String
    public var sourceId: String
    public var sourceLabel: String
    public var icon: String?
    public var report: UsageReport
    public var successfulAt: String?
    public var lastSuccessful: LastSuccessful?

    public struct LastSuccessful: Sendable, Hashable, Decodable {
        public var fetchedAt: String
        public var report: AvailableUsageReport
    }

    public init(
        id: String, accountLabel: String? = nil, fetchedAt: String, sourceId: String,
        sourceLabel: String, icon: String? = nil, report: UsageReport, successfulAt: String? = nil,
        lastSuccessful: LastSuccessful? = nil
    ) {
        self.id = id
        self.accountLabel = accountLabel
        self.fetchedAt = fetchedAt
        self.sourceId = sourceId
        self.sourceLabel = sourceLabel
        self.icon = icon
        self.report = report
        self.successfulAt = successfulAt
        self.lastSuccessful = lastSuccessful
    }

    private enum K: String, CodingKey {
        case id, account, fetchedAt, sourceId, sourceLabel, icon, report, successfulAt, lastSuccessful
    }

    private struct Account: Decodable {
        var label: String?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        accountLabel = try c.decodeIfPresent(Account.self, forKey: .account)?.label
        fetchedAt = try c.decode(String.self, forKey: .fetchedAt)
        sourceId = try c.decode(String.self, forKey: .sourceId)
        sourceLabel = try c.decode(String.self, forKey: .sourceLabel)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        report = try c.decode(UsageReport.self, forKey: .report)
        successfulAt = try c.decodeIfPresent(String.self, forKey: .successfulAt)
        lastSuccessful = try c.decodeIfPresent(LastSuccessful.self, forKey: .lastSuccessful)
    }
}

public struct UsageListReportsRequest: PaseoRequest {
    public static let type = "usage.list_reports.request"
    public static let responseType = "usage.list_reports.response"
    public var requestId = ""
    public var agentId: String?
    public var reportIds: [String]?
    public var forceRefresh: Bool?

    public typealias Response = UsageListReportsResponse

    public init(agentId: String? = nil, reportIds: [String]? = nil, forceRefresh: Bool? = nil) {
        self.agentId = agentId
        self.reportIds = reportIds
        self.forceRefresh = forceRefresh
    }
}

/// The update messages every collector subscribes to; each carries one full report.
public struct UsageListReportsUpdate: Decodable, Sendable {
    public var requestId: String
    public var report: UsageReportEntry
}

public struct UsageListReportsResponse: Decodable, Sendable {
    public var requestId: String
    public var error: String?
}
