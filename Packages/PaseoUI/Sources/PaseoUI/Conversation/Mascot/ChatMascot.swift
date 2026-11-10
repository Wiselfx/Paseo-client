#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The mascot's wiring: every input the crab reacts to, read from the R3 digest and the host
/// aggregates — no scans of the timeline (R6 §3).
///
/// | Input | Source |
/// |---|---|
/// | failed tool calls | `store.timeline.failedToolCalls` (seq-aware through `mascotSeqFloor`) |
/// | running subagents | `store.timeline.runningSubAgentCount` |
/// | compaction | `store.timeline.lastCompactionStatus` |
/// | activity | `store.timeline.latestRowKind` + `latestRowId` |
/// | busy / pending / attention | `session.runningAgentCount`, `.pendingPermissionCount`, `.attentionCount` |
///
/// The 1 s ticker runs only while the machine has something left to expire, and stops while the
/// surface is obscured (R4/R5 environment).
struct MascotDriver: ViewModifier {
    let store: ConversationStore
    let session: HostSession
    let controller: ChatController

    @Environment(\.isSurfaceObscured) private var isSurfaceObscured

    func body(content: Content) -> some View {
        content
            // History arrives after the view appears, so baselines are taken when the first load
            // is ready; seeding on appear left them empty and history's failures played as errors
            // (B11).
            .onAppear {
                if case .ready = store.phase { controller.seedMascotBaselines() }
            }
            .onChange(of: store.phase) { _, phase in
                if case .ready = phase { controller.seedMascotBaselines() }
            }
            .onChange(of: store.activeTurnId) { _, newId in
                controller.turnBoundaryChanged(newId)
            }
            .onChange(of: store.timeline.latestRowId) { _, _ in
                controller.activityChanged()
            }
            .onChange(of: store.timeline.failedToolCalls) { _, calls in
                controller.failedToolCallsChanged(calls)
            }
            .onChange(of: store.timeline.runningSubAgentCount) { _, count in
                controller.feedMascot(.subagentsChanged(count: count, at: Date()))
            }
            .onChange(of: store.timeline.lastCompactionStatus) { _, _ in
                controller.compactionChanged()
            }
            .onChange(of: session.runningAgentCount) { _, count in
                controller.feedMascot(.busySessionsChanged(count: count, at: Date()))
            }
            .onChange(of: session.pendingPermissionCount) { _, count in
                controller.feedMascot(.pendingInteractionsChanged(count: count, at: Date()))
            }
            .onChange(of: session.attentionCount) { _, _ in
                controller.attentionChanged()
            }
            .task(id: ticking) {
                guard ticking else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    controller.mascot.tick(now: Date())
                }
            }
    }

    /// True while the mascot's own clock has work to do: on stage, waking, or counting down to
    /// sleep. Once it is asleep only an event can move it, so the ticker stops (P3).
    private var ticking: Bool {
        controller.mascot.state != .sleeping && !isSurfaceObscured
    }
}

extension ChatController {
    func feedMascot(_ event: MascotEvent) {
        mascot.handle(event)
    }

    /// Runs once, when the conversation's first load is ready (UX spec §4.4): baselines the
    /// one-shot histories from the loaded state, then hands the machine the current levels.
    func seedMascotBaselines() {
        guard !mascotSeeded else { return }
        mascotSeeded = true
        let now = Date()
        // The oldest row present is the floor: anything below it is history, not a live event.
        mascotSeqFloor = store.timeline.rows.first?.seqStart ?? 0
        signalledToolFailureIds = Set(allFailedToolCallIds)
        attentionActive = session.attentionCount > 0
        compactionOpen = store.timeline.lastCompactionStatus == "loading"
        if let activeTurnId = store.activeTurnId {
            mascotLiveTurnId = activeTurnId
            feedMascot(.turnStarted(at: now))
        }
        feedMascot(.busySessionsChanged(count: session.runningAgentCount, at: now))
        feedMascot(.pendingInteractionsChanged(count: session.pendingPermissionCount, at: now))
        feedMascot(.subagentsChanged(count: store.timeline.runningSubAgentCount, at: now))
        if compactionOpen { feedMascot(.compactionStarted(at: now)) }
    }

    /// Every failed tool call the digest knows, by `callId`.
    var allFailedToolCallIds: [String] {
        store.timeline.failedToolCalls.map(\.callId)
    }

    /// Failed calls at or above the seed floor: failures the reader watched happen.
    var liveFailedToolCallIds: [String] {
        store.timeline.failedToolCalls
            .filter { $0.seq >= mascotSeqFloor }
            .map(\.callId)
    }

    /// A turn started or ended. Only a turn the mascot was told about can end: a snapshot settling
    /// to nil as history loads is not news (UX spec §4.4).
    func turnBoundaryChanged(_ newId: String?) {
        guard mascotSeeded else { return }
        let now = Date()
        if let newId {
            mascotLiveTurnId = newId
            feedMascot(.turnStarted(at: now))
            return
        }
        guard mascotLiveTurnId != nil else { return }
        mascotLiveTurnId = nil
        switch store.turns.last?.phase {
        case .failed: feedMascot(.turnFailed(at: now))
        default: feedMascot(.turnCompleted(at: now))
        }
    }

    /// The newest row's kind: reasoning streams think, a running tool call works.
    func activityChanged() {
        guard mascotSeeded, store.timeline.latestRowId != nil else { return }
        switch store.timeline.latestRowKind {
        case .reasoning: feedMascot(.activityChanged(.reasoning, at: Date()))
        case .toolCall: feedMascot(.activityChanged(.working, at: Date()))
        default: break
        }
    }

    func failedToolCallsChanged(_ calls: [TimelineState.FailedToolCall]) {
        guard mascotSeeded else {
            signalledToolFailureIds = Set(calls.map(\.callId))
            return
        }
        let unseen = liveFailedToolCallIds.filter { !signalledToolFailureIds.contains($0) }
        guard !unseen.isEmpty else { return }
        for _ in unseen { feedMascot(.toolFailed(at: Date())) }
        signalledToolFailureIds.formUnion(unseen)
    }

    func compactionChanged() {
        let status = store.timeline.lastCompactionStatus
        let now = Date()
        if status == "loading" {
            if !compactionOpen {
                compactionOpen = true
                feedMascot(.compactionStarted(at: now))
            }
        } else if compactionOpen {
            compactionOpen = false
            feedMascot(.compactionEnded(failed: status == "failed", at: now))
        }
    }

    func attentionChanged() {
        let active = session.attentionCount > 0
        if active, !attentionActive { feedMascot(.attention(at: Date())) }
        attentionActive = active
    }
}

/// The crab, feet on the composer card's top edge, flush with its right edge, above the card.
/// 104 × 72 pt of art; only the resting body takes touches.
///
/// **Reads:** `controller.mascot.state`, `controller.showCostBubble`, `store.contextUsage` (only
/// while the bubble is open).
struct MascotCrab: View {
    @Bindable var controller: ChatController
    let store: ConversationStore?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PaseoSettingsKeys.mascot) private var mascotEnabled = true

    var body: some View {
        if mascotEnabled {
            ComposerCrab(state: controller.mascot.state)
                // Long-press opens the cost bubble (M17); tap stays the poke.
                .onLongPressGesture(minimumDuration: 0.35) { controller.showCostBubble = true }
                .overlay(alignment: .topTrailing) {
                    if controller.showCostBubble, let usage = store?.contextUsage,
                        usage.totalCostUsd != nil || usage.inputTokens != nil
                            || usage.outputTokens != nil
                    {
                        costBubble(usage: usage)
                            .fixedSize()
                            .alignmentGuide(.top) { $0[.bottom] + 6 }
                            .transition(
                                .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing))
                            )
                            .onTapGesture { controller.showCostBubble = false }
                            .task {
                                try? await Task.sleep(for: .seconds(4))
                                controller.showCostBubble = false
                            }
                    }
                }
                .animation(
                    Motion.disclosure.resolved(reduceMotion: reduceMotion),
                    value: controller.showCostBubble
                )
                .offset(y: -72)
        }
    }

    private func costBubble(usage: ContextUsage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Session cost")
                .font(.paseo(.caption2))
                .foregroundStyle(Palette.secondaryInk)
            if let cost = usage.totalCostUsd {
                Text(ClaudeContextSheet.cost(cost))
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }
            if let tokens = tokenTotal(usage) {
                Text("\(PaseoFormat.integer(tokens)) tokens")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.cardBorder, lineWidth: 0.5)
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
