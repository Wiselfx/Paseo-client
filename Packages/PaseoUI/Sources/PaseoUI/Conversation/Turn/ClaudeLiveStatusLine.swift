#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// Loader (18 × 14, the accent), the words with the host's highlight band swept across them,
/// the turn clock, and "No response yet" after 10 s of silence (doc 08 §2, §3).
///
/// Nothing here runs at the display rate: the band has its own stepped clock over the words alone
/// (`ClaudeSweepLabel`), the clock ticks once a second, and the wording lock and the silence badge
/// are timers that fire once.
struct ClaudeLiveStatusLine: View {
    let turn: Turn
    @State private var activity: ClaudeActivity
    @State private var wordingChangedAt = Date()
    /// A wording of the call's own words seen during a stand, held to be written first when it ends.
    @State private var pendingDetail: ClaudeActivity?
    /// The clause the model last said it was on, held across the gaps between clauses.
    @State private var lastModelWords: String?
    @State private var lastActivityAt = Date()
    @State private var overtime = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(turn: Turn) {
        self.turn = turn
        _activity = State(initialValue: ClaudeActivity.current(for: turn))
    }

    var body: some View {
        let next = ClaudeActivity.current(for: turn)
        HStack(spacing: 6) {
            ClaudeLoader()
            ClaudeSweepLabel(startedAt: wordingChangedAt, rest: Palette.secondaryInk) { ink in
                Text(activity.text).font(.paseo(.callout)).foregroundStyle(ink)
            }
            .id(activity)
            .transition(.asymmetric(insertion: .claudeWordEntrance, removal: .claudeWordExit))
            ClaudeElapsedClock(since: turn.startedAt)
                .padding(.leading, 2)
            if overtime {
                Text("No response yet")
                    .font(.paseo(.caption2, weight: .medium))
                    .foregroundStyle(Palette.warning)
                    .padding(.horizontal, 6)
                    .padding(.leading, 2)
                    .frame(height: 16)
                    .background(Palette.warning.opacity(0.16), in: .rect(cornerRadius: Radius.sm))
                    .transition(.offset(y: 4).combined(with: .scale(scale: 0.92)).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .animation(Motion.swap.resolved(reduceMotion: reduceMotion), value: activity)
        // OCU §12: the overtime badge settles critically damped, like every surface.
        .animation(Motion.settle.resolved(reduceMotion: reduceMotion), value: overtime)
        .onChange(of: next) { _, _ in advanceActivity(at: Date()) }
        .onChange(of: turn.claudeActivityKey) { _, _ in lastActivityAt = Date() }
        // The wording lock: whatever arrived during the stand is written when it ends.
        .task(id: wordingChangedAt) {
            try? await Task.sleep(for: .seconds(ClaudeMotion.wordLock))
            guard !Task.isCancelled else { return }
            advanceActivity(at: Date())
        }
        // Silence: the badge appears after `overtime` seconds with nothing new.
        .task(id: lastActivityAt) {
            if overtime { overtime = false }
            let remaining = ClaudeMotion.overtime - Date().timeIntervalSince(lastActivityAt)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled else { return }
            overtime = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(activity.text)
    }

    /// The wording lock: a wording stands for a second so a fast turn reads as one line, not a
    /// flicker. The call's own words are never lost to the lock: they wait for it and are written
    /// first when it ends.
    private func advanceActivity(at date: Date) {
        var next = ClaudeActivity.current(for: turn)
        if case .model(let words) = next {
            lastModelWords = words
        } else if next == .thinking, ClaudeActivity.reasoningIsNewest(turn), let held = lastModelWords {
            next = .model(held)
        }
        if date.timeIntervalSince(wordingChangedAt) >= ClaudeMotion.wordLock {
            let winner = pendingDetail ?? next
            pendingDetail = nil
            if winner != activity {
                activity = winner
                wordingChangedAt = date
                lastActivityAt = date
            }
        } else if next.isCallOwnWords, next != activity {
            // Held for the end of the stand (the timer above re-reads the rest then).
            pendingDetail = next
        }
    }
}
#endif
