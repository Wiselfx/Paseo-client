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
    @ViewBuilder var mascotCrab: some View {
        if mascotEnabled {
            ComposerCrab(state: mascot.state)
                .offset(y: -72)
        }
    }

}
#endif
