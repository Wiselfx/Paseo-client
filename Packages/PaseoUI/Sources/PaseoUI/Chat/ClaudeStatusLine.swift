#if canImport(UIKit)
import Combine
import Foundation
import PaseoStore
import SwiftUI

/// The states the waiting line shows while the turn runs (`docs/research/08-dsh-live-observation.md`
/// §3.1): the fixed set the copy names, plus the model's own words — a started file call fills
/// `{file}`, a shell call contributes its own first line as the `description` argument would,
/// and reasoning contributes the clause the model is on.
enum ClaudeActivity: Hashable {
    case thinking
    case writing
    case preparingToolCall
    case runningTools
    case reading(String)
    case editing(String)
    case writingFile(String)
    /// The model's own words — a shell call's command line or a reasoning clause.
    case model(String)

    var text: String {
        switch self {
        case .thinking: "Thinking…"
        case .writing: "Writing…"
        case .preparingToolCall: "Preparing a tool call…"
        case .runningTools: "Running tools…"
        case .reading(let file): "Reading \(file)"
        case .editing(let file): "Editing \(file)"
        case .writingFile(let file): "Writing \(file)"
        case .model(let words): words
        }
    }

    /// The call's own words may not be lost to the standing wording lock: they wait for it and
    /// are written at the first tick that finds it expired.
    var isCallOwnWords: Bool {
        switch self {
        case .reading, .editing, .writingFile, .model: true
        default: false
        }
    }

    /// Which state to show, read off the open turn's newest block.
    static func current(for turn: Turn) -> ClaudeActivity {
        guard let segment = turn.segments.last else { return .thinking }
        switch segment {
        case .work(let group):
            guard let row = group.rows.last else { return .thinking }
            switch row.item {
            case .reasoning(let reasoning):
                if let clause = ClaudeReasoningClause.extract(from: reasoning.text) {
                    return .model(clause)
                }
                return .thinking
            case .toolCall(let call): return forToolCall(call)
            default: return .thinking
            }
        case .prose, .todo, .notice:
            return .writing
        }
    }

    /// True when the newest block is reasoning — the case where a previously read clause is held
    /// across the gaps between clauses (`wait-state.ts`: the model's own clause is held).
    static func reasoningIsNewest(_ turn: Turn) -> Bool {
        guard case .work(let group) = turn.segments.last, let row = group.rows.last else { return false }
        if case .reasoning = row.item { return true }
        return false
    }

    static func forToolCall(_ call: ToolCall) -> ClaudeActivity {
        switch call.detail {
        case .read(let path, _):
            return .reading(fileName(path))
        case .edit(let path, _, _, _):
            return .editing(fileName(path))
        case .write(let path, _):
            return .writingFile(fileName(path))
        case .shell(let command, _, _, _):
            // Our protocol model carries no separate `description` argument for shell calls,
            // so the command's own first line stands in — first letter capitalised, whitespace
            // collapsed — the shape the reference applies to a real `description`.
            let line = firstLine(command)
            guard !line.isEmpty else { return .runningTools }
            let collapsed = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return .model(collapsed.prefix(1).uppercased() + collapsed.dropFirst())
        case .unknown:
            return call.status == .running ? .preparingToolCall : .runningTools
        default:
            return .runningTools
        }
    }

    static func firstLine(_ text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? text
        return line.trimmingCharacters(in: .whitespaces)
    }

    static func fileName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

extension Turn {
    /// Changes whenever the turn produces new readable content, so the status line can tell how
    /// long the model has been silent.
    var claudeActivityKey: String {
        guard let segment = segments.last else { return "\(id):empty" }
        switch segment {
        case .work(let group):
            guard let row = group.rows.last else { return "\(id):work-empty" }
            return "\(id):\(row.id):\(claudeTextLength(row.item))"
        case .prose(let row), .todo(let row), .notice(let row):
            return "\(id):\(row.id):\(claudeTextLength(row.item))"
        }
    }

    private func claudeTextLength(_ item: TimelineItem) -> Int {
        switch item {
        case .reasoning(let reasoning): reasoning.text.count
        case .assistantMessage(let message): message.text.count
        case .toolCall(let call): call.status.isTerminal ? 1 : 0
        case .todo(let list): list.items.count
        case .error(let message): message.count
        case .notification(_, let message): message.count
        case .compaction(let status, _, _): status.count
        case .unknown(let type, _): type.count
        case .userMessage(let message): message.text.count
        }
    }
}

/// Loader (18 × 14, the accent), the words with the host's highlight band swept across them,
/// the turn clock, and "No response yet" after 10 s of silence (doc 08 §2, §3).
struct ClaudeLiveStatusLine: View {
    let turn: Turn
    let typography: ClaudeTypography
    @State private var activity: ClaudeActivity
    @State private var wordingChangedAt = Date()
    /// A wording of the call's own words seen during a stand, held to be written first when it ends.
    @State private var pendingDetail: ClaudeActivity?
    /// The clause the model last said it was on, held across the gaps between clauses.
    @State private var lastModelWords: String?
    @State private var lastActivityAt = Date()
    @State private var now = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Ticks the clock and the wording lock four times a second (`TICK_MS`).
    private let ticker = Timer.publish(every: ClaudeMotion.tick, on: .main, in: .common).autoconnect()

    init(turn: Turn, typography: ClaudeTypography = ClaudeTypography()) {
        self.turn = turn
        self.typography = typography
        _activity = State(initialValue: ClaudeActivity.current(for: turn))
    }

    private var elapsed: TimeInterval { max(1, now.timeIntervalSince(turn.startedAt ?? now)) }
    private var showsOvertime: Bool { now.timeIntervalSince(lastActivityAt) >= ClaudeMotion.overtime }

    var body: some View {
        HStack(spacing: 6) {
            ClaudeLoader()
            ClaudeSweepText(text: activity.text, font: typography.sans(14))
                .id(activity)
                .transition(.asymmetric(insertion: .claudeWordEntrance, removal: .claudeWordExit))
            Text(DurationText.short(elapsed))
                .font(typography.sans(13).monospacedDigit())
                .foregroundStyle(ClaudePalette.captionInk)
                .padding(.leading, 2)
            if showsOvertime {
                Text("No response yet")
                    .font(typography.sans(11, weight: .medium))
                    .foregroundStyle(ClaudePalette.warning)
                    .padding(.horizontal, 6)
                    .padding(.leading, 2)
                    .frame(height: 16)
                    .background(ClaudePalette.warning.opacity(0.16), in: .rect(cornerRadius: 5))
                    .transition(.offset(y: 4).combined(with: .scale(scale: 0.92)).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .animation(reduceMotion ? nil : .easeInOut(duration: ClaudeMotion.swap), value: activity)
        .animation(EdgeDrawer.settleAnimation(reduceMotion: reduceMotion), value: showsOvertime)
        .onChange(of: turn.claudeActivityKey) { _, _ in lastActivityAt = Date() }
        .onReceive(ticker) { date in
            now = date
            var next = ClaudeActivity.current(for: turn)
            if case .model(let words) = next {
                lastModelWords = words
            } else if next == .thinking, ClaudeActivity.reasoningIsNewest(turn), let held = lastModelWords {
                next = .model(held)
            }
            // A wording stands for a second so a fast turn reads as one line, not a flicker.
            // The call's own words are never lost to the lock: they wait for it and are written
            // first when it ends.
            if date.timeIntervalSince(wordingChangedAt) >= ClaudeMotion.wordLock {
                let winner = pendingDetail ?? next
                if winner != activity {
                    activity = winner
                    wordingChangedAt = date
                    lastActivityAt = date
                }
                pendingDetail = nil
            } else if next.isCallOwnWords, next != activity {
                pendingDetail = next
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(activity.text)
    }
}

/// The words with the host's highlight band swept across them while the turn runs.
/// The band is a masked copy of the glyphs tinted the shimmer ink — never a coloured wash.
struct ClaudeSweepText: View {
    let text: String
    let font: Font
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The words' first appearance anchors the band's 300 ms delay.
    @State private var start = Date()

    @ViewBuilder var body: some View {
        let base = Text(text).font(font).foregroundStyle(ClaudePalette.secondaryInk)
        if reduceMotion {
            base
        } else {
            // Display rate, not a 30 Hz cap: the band must not step at 120 Hz (P3).
            TimelineView(.animation) { context in
                base.overlay(alignment: .leading) {
                    if let phase = ClaudeSweep.phase(startedAt: start, at: context.date) {
                        Text(text)
                            .font(font)
                            .foregroundStyle(ClaudePalette.shimmerInk)
                            .mask(ClaudeSweep.windowGradient(phase: phase))
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}

/// The swap the line trades wordings by: old words leave upward through a 2 pt blur, new words
/// enter from below, 150 ms ease-in-out with an 8 pt travel.
private struct ClaudeBlurSwap: ViewModifier {
    var blur: CGFloat
    var y: CGFloat
    var alpha: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(blur, AnimatablePair(y, alpha)) }
        set {
            blur = newValue.first
            y = newValue.second.first
            alpha = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        content.blur(radius: blur).offset(y: y).opacity(alpha)
    }
}

extension AnyTransition {
    static var claudeWordEntrance: AnyTransition {
        .modifier(
            active: ClaudeBlurSwap(blur: 2, y: 8, alpha: 0),
            identity: ClaudeBlurSwap(blur: 0, y: 0, alpha: 1))
    }

    static var claudeWordExit: AnyTransition {
        .modifier(
            active: ClaudeBlurSwap(blur: 2, y: -8, alpha: 0),
            identity: ClaudeBlurSwap(blur: 0, y: 0, alpha: 1))
    }
}
#endif
