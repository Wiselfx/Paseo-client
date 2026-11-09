#if canImport(UIKit)
import Combine
import Foundation
import PaseoStore
import SwiftUI

/// The fixed set of states the waiting line shows (`docs/research/06-dsh-ux-spec.md` §2).
/// No whimsical verbs: one of these, with the model's own file where the app can read it.
enum ClaudeActivity: Hashable {
    case thinking
    case writing
    case preparingToolCall
    case runningTools
    case reading(String)
    case editing(String)
    case writingFile(String)

    var text: String {
        switch self {
        case .thinking: "Thinking…"
        case .writing: "Writing…"
        case .preparingToolCall: "Preparing a tool call…"
        case .runningTools: "Running tools…"
        case .reading(let file): "Reading \(file)"
        case .editing(let file): "Editing \(file)"
        case .writingFile(let file): "Writing \(file)"
        }
    }

    /// Which state to show, read off the open turn's newest block.
    static func current(for turn: Turn) -> ClaudeActivity {
        guard let segment = turn.segments.last else { return .thinking }
        switch segment {
        case .work(let group):
            guard let row = group.rows.last else { return .thinking }
            switch row.item {
            case .reasoning: return .thinking
            case .toolCall(let call): return forToolCall(call)
            default: return .thinking
            }
        case .prose, .todo, .notice:
            return .writing
        }
    }

    static func forToolCall(_ call: ToolCall) -> ClaudeActivity {
        switch call.detail {
        case .read(let path, _):
            return .reading(fileName(path))
        case .edit(let path, _, _, _):
            return .editing(fileName(path))
        case .write(let path, _):
            return .writingFile(fileName(path))
        case .unknown:
            return call.status == .running ? .preparingToolCall : .runningTools
        default:
            return .runningTools
        }
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
        case .compaction(let status): status.count
        case .unknown(let type, _): type.count
        case .userMessage(let message): message.text.count
        }
    }
}

/// Loader dots (18 × 14 box, 4 pt accents bouncing and flattening against the floor), the words
/// with their highlight sweep, the turn clock, and "No response yet" after 10 s of silence.
struct ClaudeLiveStatusLine: View {
    let turn: Turn
    let typography: ClaudeTypography
    @State private var activity: ClaudeActivity
    @State private var wordingChangedAt = Date()
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
            ClaudeLoaderDots()
            ClaudeSweepText(text: activity.text, font: typography.sans(14))
                .id(activity)
                .transition(
                    .asymmetric(
                        insertion: .offset(y: 8).combined(with: .opacity),
                        removal: .offset(y: -8).combined(with: .opacity))
                )
            Text(DurationText.short(elapsed))
                .font(typography.mono(13))
                .foregroundStyle(ClaudePalette.captionInk)
                .padding(.leading, 2)
            if showsOvertime {
                Text("No response yet")
                    .font(typography.sans(11, weight: .medium))
                    .foregroundStyle(ClaudePalette.warning)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(ClaudePalette.warning.opacity(0.16), in: .rect(cornerRadius: 5))
                    .transition(.offset(y: 4).combined(with: .scale(scale: 0.92)).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .animation(reduceMotion ? nil : .easeInOut(duration: ClaudeMotion.swap), value: activity)
        .animation(
            reduceMotion ? nil : .spring(response: ClaudeMotion.open, dampingFraction: 0.62),
            value: showsOvertime)
        .onChange(of: turn.claudeActivityKey) { _, _ in lastActivityAt = Date() }
        .onReceive(ticker) { date in
            now = date
            let next = ClaudeActivity.current(for: turn)
            // A wording stands for a second so a fast turn reads as one line, not a flicker.
            if next != activity, date.timeIntervalSince(wordingChangedAt) >= ClaudeMotion.wordLock {
                activity = next
                wordingChangedAt = date
                lastActivityAt = date
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(activity.text)
    }
}

/// The words with the host's highlight band swept across them while the turn runs.
struct ClaudeSweepText: View {
    let text: String
    let font: Font
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder var body: some View {
        let base = Text(text).font(font).foregroundStyle(ClaudePalette.secondaryInk)
        if reduceMotion {
            base
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let phase =
                    context.date.timeIntervalSinceReferenceDate.truncatingRemainder(
                        dividingBy: ClaudeMotion.statusPeriod) / ClaudeMotion.statusPeriod
                base.overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: max(0, phase - 0.25)),
                            .init(color: ClaudePalette.ink.opacity(0.85), location: phase),
                            .init(color: .clear, location: min(1, phase + 0.25)),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .mask(Text(text).font(font))
                }
            }
        }
    }
}

/// Three accents bouncing out of phase, flattening as they land.
struct ClaudeLoaderDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let period: Double = 0.5

    var body: some View {
        if reduceMotion {
            dots(at: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                dots(at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func dots(at time: TimeInterval) -> some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                let raw = time / period + Double(index) * 0.4
                let phase = raw - raw.rounded(.down)
                let lift = CGFloat(max(0, sin(Double.pi * phase)))
                Circle()
                    .fill(ClaudePalette.orange)
                    .frame(width: 4, height: 4)
                    .scaleEffect(x: 1, y: 1 - 0.35 * lift, anchor: .bottom)
                    .offset(y: -7 * lift)
            }
        }
        .frame(width: 18, height: 14, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
#endif
