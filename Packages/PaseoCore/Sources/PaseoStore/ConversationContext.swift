import Foundation
import Observation
import PaseoKit
import PaseoProtocol

// T16: the context-window meter for the chat, kept live from the stream.
// The daemon reports usage on snapshots (`agent.lastUsage`) and merges the window fields on
// `usage.list_reports`-style stream events; totals and windowing never go backwards here.

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
}
