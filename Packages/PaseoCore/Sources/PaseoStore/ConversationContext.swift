import Foundation
import Observation
import PaseoKit
import PaseoProtocol

// T16: the context-window meter for the chat, kept live from the stream.
// The daemon reports usage on snapshots (`agent.lastUsage`) and merges the window fields on
// `usage.list_reports`-style stream events; totals and windowing never go backwards here.

/// One live turn's usage, in completion order (G13 C16). Only turns observed live carry
/// figures; the projected history does not. The chart starts where these start —
/// never fake zeros for older turns. A recorded bar is always that turn's own
/// figure: per-query values verbatim, cumulative values as the growth since the
/// previous turn's final (see `recordTurnUsage`).
///
/// Provider table (frozen upstream `packages/server/src/server/agent/providers/`):
/// - pi: NO usage on `turn_completed` (`pi/agent.ts:2583` emits without `usage`;
///   `usagePoller.completeTurn` publishes a usage event afterwards). Figures are
///   session totals (`pi/usage-poller.ts:24`, `toAgentUsage` from `get_session_stats`;
///   `pi/cli-runtime.ts:209`). Tokens AND cost: delta.
/// - opencode: `usage_updated` per step and `turn_completed` both carry
///   `usageFromV2(SessionInfo)` (`opencode/v2/usage.ts:30`,
///   `opencode/v2/turns.ts:303`, `opencode/v2/mapping.ts:40`): session tokens and
///   session cost. Tokens AND cost: delta.
/// - claude: `turn_completed` carries the SDK result usage (`claude/agent.ts:5124`,
///   via `buildResultUsage` at `:2207`): `output_tokens` is per-query (latest),
///   `total_cost_usd` is possibly session-cumulative (delta).
/// - unknown providers: delta for both (most providers report session totals).
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

    /// The per-turn chart window (G13 C16): the last 30 turns, oldest first, with
    /// the still-open turn appended. The sheet draws this directly — values,
    /// never a re-parse per body pass.
    public var recentTurnUsage: [TurnUsagePoint] {
        var points = turnUsage
        if let turnId = openUsageTurnID,
            (openUsageTokens ?? 0) > 0 || (openUsageCost ?? 0) > 0
        {
            points.append(TurnUsagePoint(
                turnId: turnId,
                outputTokens: openUsageTokens ?? 0,
                costUsd: openUsageCost ?? 0))
        }
        return Array(points.suffix(TurnUsagePoint.chartWindow))
    }

    /// Only claude's output tokens arrive per-query (see the table on
    /// `TurnUsagePoint`); every other figure is a session total and needs the
    /// delta from the previous turn's final.
    private static func tokensArePerTurn(provider: String?) -> Bool {
        provider == "claude"
    }

    /// Collects one usage event into its turn's point (G13 C16): a turn's point
    /// gathers every figure that arrives from its `turn_started` until the next
    /// `turn_started` — on `turn_completed` AND on `usage_updated` — so pi's
    /// post-completion usage lands on the turn it belongs to. The open point is
    /// updated in place (usage events are rare: one store write each), then
    /// frozen by the next turn's start. `turnId` falls back to the open turn, so
    /// a figure without one still lands correctly; an explicit different id
    /// freezes and retargets (out-of-order delivery).
    internal func recordTurnUsage(turnId: String?, provider: String?, usage: AgentUsage) {
        let target = turnId ?? openUsageTurnID
        guard let target else { return }
        if target != openUsageTurnID {
            freezeOpenUsage()
            openUsageTurnID = target
        }
        if let tokens = usage.outputTokens, tokens >= 0 {
            if Self.tokensArePerTurn(provider: provider) {
                openUsageTokens = tokens
            } else {
                // Cumulative: the bar is the growth since the previous turn's
                // final. The first observation has no previous: the bar is the
                // value itself. A drop is a session reset: no negative bars,
                // the baseline restarts here.
                let base = baselineTokens ?? 0
                openUsageTokens = max(0, tokens - base)
                baselineTokens = tokens
            }
        }
        if let cost = usage.totalCostUsd, cost >= 0 {
            // Cost is always cumulative (see the table): the bar is the growth.
            // The first observation has no previous, so it records no cost.
            // A drop is a reset: no negative, baseline restarts.
            openUsageCost = baselineCost.map { max(0, cost - $0) } ?? 0
            baselineCost = cost
        }
    }

    /// Freezes the open point into the series, if it has a real figure. A turn of
    /// pure zeros records nothing. Bounded: the chart shows 30, the store keeps
    /// three windows. Rewinds never un-spend: nothing here is ever removed.
    internal func freezeOpenUsage() {
        defer {
            openUsageTurnID = nil
            openUsageTokens = nil
            openUsageCost = nil
        }
        guard let turnId = openUsageTurnID,
            (openUsageTokens ?? 0) > 0 || (openUsageCost ?? 0) > 0
        else { return }
        turnUsage.append(TurnUsagePoint(
            turnId: turnId,
            outputTokens: openUsageTokens ?? 0,
            costUsd: openUsageCost ?? 0))
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
