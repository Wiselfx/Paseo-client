#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

extension ClaudeChatView {
    // MARK: Mascot (M5a)

    func feedMascot(_ event: MascotEvent) {
        mascot.handle(event)
    }

    /// Runs once when the view appears: baselines the one-shot histories so opening the
    /// conversation doesn't re-fire them, then hands the machine the current levels.
    func seedMascotBaselines() {
        let now = Date()
        signalledToolFailureIds = Set(failedToolCallIds)
        attentionActive = attentionCount > 0
        compactionOpen = lastCompactionStatus == "loading"
        if store.activeTurnId != nil { feedMascot(.turnStarted(at: now)) }
        feedMascot(.busySessionsChanged(count: busySessions, at: now))
        feedMascot(.pendingInteractionsChanged(count: pendingInteractions, at: now))
        feedMascot(.subagentsChanged(count: runningSubagents, at: now))
        if compactionOpen { feedMascot(.compactionStarted(at: now)) }
    }

    /// `rowId|kind` of the newest row; only the kind drives the activity switch.
    var mascotActivitySignature: String {
        guard let last = store.timeline.rows.last else { return "|" }
        return "\(last.id)|\(mascotRowTag(last.item))"
    }

    func mascotRowTag(_ item: TimelineItem) -> String {
        switch item {
        case .reasoning: "reasoning"
        case .toolCall: "toolCall"
        default: "other"
        }
    }

    /// Failed tool calls whose failure is not an AbortError — the machine's `toolFailed`.
    var failedToolCallIds: [String] {
        store.timeline.rows.compactMap { row in
            if case .toolCall(let call) = row.item, call.status == .failed,
                MascotToolError.isFailure(call)
            {
                return call.callId
            }
            return nil
        }
    }

    /// Running sub-agent tool calls of the followed session.
    var runningSubagents: Int {
        store.timeline.rows.filter { row in
            if case .toolCall(let call) = row.item, call.status == .running,
                case .subAgent = call.detail
            {
                return true
            }
            return false
        }.count
    }

    /// The raw `status` of the newest compaction row (`loading` / `completed` / unknown), or nil.
    var lastCompactionStatus: String? {
        store.timeline.rows.compactMap { row -> String? in
            if case .compaction(let status) = row.item { return status }
            return nil
        }.last
    }

    /// Busy sessions in the workspace (the followed one included), as the machine wants them.
    var busySessions: Int {
        session.agents.filter { $0.status == .running }.count
    }

    /// Workspace-wide pending interactions: approvals, questions, plan reviews.
    var pendingInteractions: Int {
        session.agents.reduce(0) { $0 + $1.pendingPermissions.count }
    }

    /// Sessions that finished unread while out of view.
    var attentionCount: Int {
        session.agents.filter { $0.requiresAttention == true }.count
    }

    /// The crab, feet on the composer card's top edge, flush with its right edge, above the card.
    /// 104 × 72 pt of art; only the resting body takes touches.
    /// Long-press opens the cost bubble (M17): the conversation's cost/tokens from the
    /// context-usage data, when the provider reports them. Tap stays the poke. The bubble
    /// sits above the crab and closes on tap or after a few seconds. No balance line —
    /// Paseo has no balance source.
    @ViewBuilder var mascotCrab: some View {
        if mascotEnabled {
            ComposerCrab(state: mascot.state)
                .onLongPressGesture(minimumDuration: 0.35) { showCostBubble = true }
                .overlay(alignment: .topTrailing) {
                    if showCostBubble, let usage = store.contextUsage,
                        usage.totalCostUsd != nil || usage.inputTokens != nil || usage.outputTokens != nil
                    {
                        costBubble(usage: usage)
                            .fixedSize()
                            .alignmentGuide(.top) { $0[.bottom] + 6 }
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
                            .onTapGesture { showCostBubble = false }
                            .task {
                                try? await Task.sleep(for: .seconds(4))
                                showCostBubble = false
                            }
                    }
                }
                .animation(.easeOut(duration: 0.18), value: showCostBubble)
                .offset(y: -72)
        }
    }

    private func costBubble(usage: ContextUsage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Session cost")
                .font(.system(size: 11))
                .foregroundStyle(ClaudePalette.secondary)
            if let cost = usage.totalCostUsd {
                Text(ClaudeContextSheet.cost(cost))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ClaudePalette.ink)
            }
            if let tokens = tokenTotal(usage) {
                Text("\(tokens.formatted()) tokens")
                    .font(.system(size: 12))
                    .foregroundStyle(ClaudePalette.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ClaudePalette.panel, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ClaudePalette.cardBorder, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session cost")
    }

    private func tokenTotal(_ usage: ContextUsage) -> Int? {
        switch (usage.inputTokens, usage.outputTokens) {
        case let (i?, o?): i + o
        case let (i?, nil): i
        case let (nil, o?): o
        case (nil, nil): nil
        }
    }

}
#endif
