import Foundation
import Observation
import PaseoKit
import PaseoProtocol

// T16: the context-window meter for the chat, kept live from the stream.
// The daemon reports usage on snapshots (`agent.lastUsage`) and merges the window fields on
// `usage.list_reports`-style stream events; totals and windowing never go backwards here.

/// One live turn's usage, in completion order (G13 C16). Only turns observed live carry
/// per-turn figures (`turn_completed`/`usage_updated`); the projected history does not.
/// The chart starts where these start — never fake zeros for older turns. Both figures
/// are plain values: a turn that reported nothing for a metric keeps 0, and the bar
/// for a recorded turn is always that turn's own figure, never a delta.
public struct TurnUsagePoint: Sendable, Hashable, Equatable {
    /// The daemon's turn id, when the event carried one. Nil points still order by
    /// completion (append order).
    public var turnId: String?
    /// This turn's output tokens, or 0 when the event carried no figure.
    public var outputTokens: Int
    /// This turn's cost in USD, or 0 when the event carried no figure.
    public var costUsd: Double

    public init(turnId: String?, outputTokens: Int, costUsd: Double) {
        self.turnId = turnId
        self.outputTokens = outputTokens
        self.costUsd = costUsd
    }
}

/// What the composer's context meter renders: how full the window is, plus the session's cost
/// and cache figures when the provider reports them. All fields are optional; a provider that
/// says nothing about usage leaves `contextUsage` nil.
public struct ContextUsage: Sendable, Hashable {
    /// Tokens currently occupying the context window, if the provider reports it.
    public var usedTokens: Int?
    /// Size of the context window, if the provider reports it.
    public var maxTokens: Int?
    /// `usedTokens / maxTokens` as a percentage, 0…100, when both are known and `maxTokens > 0`.
    public var percentUsed: Double?
    /// Session-wide cost in USD, when the provider reports it.
    public var totalCostUsd: Double?
    public var inputTokens: Int?
    public var outputTokens: Int?
    /// Session-wide prompt-cache hit rate in percent, if the provider reports it.
    public var sessionCacheHitRatePct: Double?
    public var lastTurnCacheHitRatePct: Double?
    public var cacheWaste: AgentCacheWaste?
    public var costByModel: [AgentModelCost]?
}

extension ConversationStore {
    /// Live context-window usage for this agent. `nil` until the host reports usage.
    public var contextUsage: ContextUsage? {
        guard let usage = agent?.lastUsage else { return nil }
        let percent: Double? = {
            guard let used = usage.contextWindowUsedTokens, let max = usage.contextWindowMaxTokens,
                max > 0
            else { return nil }
            return Double(used) / Double(max) * 100
        }()
        return ContextUsage(
            usedTokens: usage.contextWindowUsedTokens,
            maxTokens: usage.contextWindowMaxTokens,
            percentUsed: percent,
            totalCostUsd: usage.totalCostUsd,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            sessionCacheHitRatePct: usage.sessionCacheHitRatePct,
            lastTurnCacheHitRatePct: usage.lastTurnCacheHitRatePct,
            cacheWaste: usage.cacheWaste,
            costByModel: usage.costByModel)
    }

    /// Adopts the context-window keys from a stream usage event into the snapshot. Cumulative
    /// counters (input/output/cached tokens, cost, hit rates, waste) stay with the snapshot —
    /// the stream's usage events carry per-turn figures and would clobber them otherwise.
    internal func applyContextWindow(_ usage: AgentUsage) {
        guard usage.contextWindowUsedTokens != nil || usage.contextWindowMaxTokens != nil else {
            return
        }
        var merged = agent?.lastUsage ?? AgentUsage()
        if let used = usage.contextWindowUsedTokens { merged.contextWindowUsedTokens = used }
        if let max = usage.contextWindowMaxTokens { merged.contextWindowMaxTokens = max }
        guard let snapshot = agent else { return }
        var updated = snapshot
        updated.lastUsage = merged
        applyAgent(updated)
    }

    /// The per-turn chart window (G13 C16): the last 30 recorded turns, oldest first.
    /// The sheet draws this directly — values, never a re-parse per body pass.
    public var recentTurnUsage: [TurnUsagePoint] {
        Array(turnUsage.suffix(TurnUsagePoint.chartWindow))
    }

    /// Appends one live turn's per-turn figures (G13 C16): the `turn_completed`
    /// event's own usage, not a delta. A point is recorded only when the event
    /// carries at least one non-negative figure; nonsense (negatives) never
    /// becomes a bar. Bounded: the chart shows 30, the store keeps three windows.
    internal func recordTurnUsage(turnId: String?, usage: AgentUsage) {
        let tokens = usage.outputTokens ?? -1
        let cost = usage.totalCostUsd ?? -1
        guard tokens >= 0 || cost >= 0 else { return }
        turnUsage.append(TurnUsagePoint(
            turnId: turnId,
            outputTokens: max(tokens, 0),
            costUsd: max(cost, 0)))
        if turnUsage.count > TurnUsagePoint.keepWindow {
            turnUsage.removeFirst(turnUsage.count - TurnUsagePoint.keepWindow)
        }
    }
}

extension TurnUsagePoint {
    /// Bars on screen.
    static let chartWindow = 30
    /// Points kept in the store (three chart windows; rewinds never un-spend cost).
    static let keepWindow = 90
}
