#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One turn: your bubble, the process header, the process body, the answer.
struct ClaudeTurnView: View {
    let turn: Turn
    let typography: ClaudeTypography
    let onMarkdown: (MarkdownAction) -> Void
    /// Reads a workspace image through the daemon (M5b); nil renders local image paths as chips.
    var localImageLoader: ((String) async -> UIImage?)? = nil
    /// The seqEnd of the match flash this row should paint, if any.
    var highlightedSeq: Int?
    /// The seqEnd of the current match; work groups containing it expand.
    var findTarget: Int?
    /// Called with an absolute path when the reader taps a filename in a Read/Edit/Write row.
    var onOpenFile: ((String) -> Void)?
    /// The scopes the rewind menu offers on your bubbles; empty hides it (M7d).
    var rewindChoices: [RewindScope] = []
    /// Called with (scope, messageId); the transcript presents the confirmation dialog.
    var onRewind: ((RewindScope, String) -> Void)? = nil

    /// Nil until the reader taps, so the default can follow the turn's phase.
    @State private var userExpanded: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var isRunning: Bool { turn.phase == .running }
    var isExpanded: Bool { userExpanded ?? isRunning }

    /// The answer stays visible even when the turn folds.
    var finalProse: TimelineRow? {
        guard !isRunning, case .prose(let row)? = turn.segments.last else { return nil }
        return row
    }

    var bodySegments: [Turn.Segment] {
        finalProse == nil ? turn.segments : Array(turn.segments.dropLast())
    }

    var showsHeader: Bool { isRunning || !bodySegments.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let row = turn.userMessage, case .userMessage(let message) = row.item {
                // The provider has to acknowledge the prompt before it can be rewound to.
                let rewindable = message.messageId != nil && !rewindChoices.isEmpty
                ClaudeUserBubble(
                    text: message.text, isPending: row.isPending,
                    rewindChoices: rewindable ? rewindChoices : [],
                    onRewind: rewindable ? { scope in onRewind?(scope, message.messageId ?? "") } : nil
                )
                .id("row:\(row.seqEnd)")
                .background(findHighlight(row.seqEnd))
            }
            if showsHeader { header }
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(bodySegments) { segment in
                        ClaudeSegmentView(
                            segment: segment, turnIsRunning: isRunning, typography: typography,
                            onMarkdown: onMarkdown, localImageLoader: localImageLoader,
                            highlightedSeq: highlightedSeq, findTarget: findTarget,
                            onOpenFile: onOpenFile)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -2)))
            }
            if let finalProse, case .assistantMessage(let message) = finalProse.item {
                ClaudeProse(markdown: message.text, typography: typography, onAction: onMarkdown, localImageLoader: localImageLoader, isStreaming: isRunning)
                    .id("row:\(finalProse.seqEnd)")
                    .background(findHighlight(finalProse.seqEnd))
            }
            if !isRunning, !copyText.isEmpty {
                HStack(spacing: 17) {
                    ClaudeCopyButton(text: copyText, label: "Copy response")
                }
                .padding(.top, 2)
            }
        }
        .onChange(of: turn.phase) { _, phase in
            // A finished turn folds itself away; the answer stays on the page.
            if phase != .running {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { userExpanded = nil }
            }
        }
    }

    /// A brief wash on the matched row; `findHighlight` reads the view's flash parameter.
    func findHighlight(_ seqEnd: Int) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(ClaudePalette.warning.opacity(highlightedSeq == seqEnd ? 0.18 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: highlightedSeq)
    }

    var copyText: String {
        var parts: [String] = []
        for segment in turn.segments {
            if case .prose(let row) = segment, case .assistantMessage(let message) = row.item {
                parts.append(message.text)
            }
        }
        return parts.joined(separator: "\n\n")
    }

    var header: some View {
        Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
                userExpanded = !isExpanded
            }
        } label: {
            HStack(spacing: 8) {
                switch turn.phase {
                case .running:
                    ClaudeLiveStatusLine(turn: turn, typography: typography)
                case .completed:
                    Text(turn.duration.map(DurationText.completed) ?? "Completed")
                        .font(typography.sans(14))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    Spacer(minLength: 0)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(typography.sans(14))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                ClaudeChevron(expanded: isExpanded)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(isExpanded ? "Collapses the work in this turn" : "Shows the work in this turn")
    }
}

/// A segment of a turn.

struct ClaudeSegmentView: View {
    let segment: Turn.Segment
    let turnIsRunning: Bool
    let typography: ClaudeTypography
    let onMarkdown: (MarkdownAction) -> Void
    /// Reads a workspace image through the daemon (M5b); nil renders local image paths as chips.
    var localImageLoader: ((String) async -> UIImage?)? = nil
    var highlightedSeq: Int?
    var findTarget: Int?
    var onOpenFile: ((String) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch segment {
        case .work(let group):
            ClaudeWorkGroupCell(
                group: group, turnIsRunning: turnIsRunning, typography: typography,
                highlightedSeq: highlightedSeq, findTarget: findTarget, onOpenFile: onOpenFile)
        case .prose(let row):
            if case .assistantMessage(let message) = row.item {
                ClaudeProse(markdown: message.text, typography: typography, onAction: onMarkdown, localImageLoader: localImageLoader, isStreaming: turnIsRunning)
                    .id("row:\(row.seqEnd)")
                    .background {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(ClaudePalette.warning.opacity(highlightedSeq == row.seqEnd ? 0.18 : 0))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: highlightedSeq)
                    }
            }
        case .todo(let row):
            if case .todo(let list) = row.item { ClaudeTodoCard(list: list) }
        case .notice(let row):
            ClaudeNoticeRow(item: row.item)
        }
    }
}

/// "2 thoughts, 1 tool call": the counted header, then a transparent card of rows, each opening on
/// its own. The card is capped at `min(400 pt, 50% of height)` and scrolls inside.
#endif
