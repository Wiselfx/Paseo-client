#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One turn: your bubble, the process header, the process body, the answer.
///
/// In `Collapse turns` mode (Settings → General → Chat), completed turns older than the most
/// recent one collapse to the prompt plus the first ~6 lines of the reply with a **Show more**
/// row; **Show less** folds back. Find expands whatever holds a match automatically.
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
    /// M7h rewind-based message actions: true only where the provider can rewind the conversation.
    var canRewrite: Bool = false
    /// Called with (messageId, text) when Edit is chosen; the transcript puts the text back in
    /// the composer and rewinds to before the message on confirm.
    var onEdit: ((String, String) -> Void)? = nil
    /// Called with (messageId, text) when Rerun is chosen; the transcript rewinds and resends.
    var onRerun: ((String, String) -> Void)? = nil
    /// M7h fork: called with the final assistant row when Fork is chosen. Nil hides the button.
    var onFork: ((TimelineRow) -> Void)? = nil
    /// False for every turn except the most recent one; only that turn never collapses.
    var isLatestTurn: Bool = true

    /// Nil until the reader taps, so the default can follow the turn's phase.
    @State private var userExpanded: Bool?
    /// Collapse-turns override: true = Show more (expanded), false = Show less (folded),
    /// nil = the mode's default.
    @State private var userExpandedTurn: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ChatDisplayMode.storageKey) private var chatDisplay = ChatDisplayMode.full.rawValue

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

    /// `collapseTurns` applies to completed, non-latest turns only; a failure always renders fully.
    var chatDisplayMode: ChatDisplayMode {
        ChatDisplayMode(rawValue: chatDisplay) ?? .full
    }

    var showsCollapsedTurn: Bool {
        guard chatDisplayMode == .collapseTurns, turn.phase == .completed, !isLatestTurn else {
            return false
        }
        // Find keeps whatever holds the match visible — it wins over the user's fold too.
        if turnContains(findTarget) { return false }
        if let userExpandedTurn { return !userExpandedTurn }
        return true
    }

    /// Whether any row of this turn covers `seq`.
    func turnContains(_ seq: Int?) -> Bool {
        guard let seq else { return false }
        if let row = turn.userMessage, row.seqStart <= seq, seq <= row.seqEnd { return true }
        for segment in turn.segments {
            switch segment {
            case .work(let group):
                if group.rows.contains(where: { $0.seqStart <= seq && seq <= $0.seqEnd }) {
                    return true
                }
            case .prose(let row), .todo(let row), .notice(let row):
                if row.seqStart <= seq, seq <= row.seqEnd { return true }
            }
        }
        return false
    }

    /// `@relative/path` tokens in your bubble, as tappable `paseo-file:` links (M7g).
    var bubbleAttributed: (String) -> AttributedString {
        { text in
            FilePathLinks.attributed(
                text, font: typography.sans(14), foreground: ClaudePalette.primaryInk,
                linkColor: ClaudePalette.proseLink)
        }
    }

    var showShowLess: Bool {
        chatDisplayMode == .collapseTurns && turn.phase == .completed && !isLatestTurn
            && userExpandedTurn == true
    }

    var body: some View {
        if showsCollapsedTurn {
            collapsedTurn
        } else {
            fullTurn
        }
    }

    /// The folded turn: the prompt plus the first ~6 lines of the reply, then **Show more**.
    @ViewBuilder private var collapsedTurn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let row = turn.userMessage, case .userMessage(let message) = row.item {
                let rewindable = message.messageId != nil && !rewindChoices.isEmpty
                ClaudeUserBubble(
                    text: message.text, isPending: row.isPending,
                    rewindChoices: rewindable ? rewindChoices : [],
                    onRewind: rewindable ? { scope in onRewind?(scope, message.messageId ?? "") } : nil,
                    attributed: bubbleAttributed(message.text),
                    canRewrite: canRewrite,
                    onEdit: rewindable ? { onEdit?(message.messageId ?? "", message.text) } : nil,
                    onRerun: rewindable ? { onRerun?(message.messageId ?? "", message.text) } : nil
                )
                .id("row:\(row.seqEnd)")
                .background(findHighlight(row.seqEnd))
            }
            if let finalProse, case .assistantMessage(let message) = finalProse.item {
                ZStack(alignment: .bottom) {
                    ClaudeProse(markdown: FilePathLinks.linkified(markdown: message.text), typography: typography, onAction: onMarkdown, localImageLoader: localImageLoader)
                        .frame(maxHeight: 6 * 23, alignment: .top)
                        .clipped()
                    LinearGradient(
                        stops: [
                            .init(color: ClaudePalette.background.opacity(0), location: 0),
                            .init(color: ClaudePalette.background, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 26)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            } else {
                // A turn with no answer section (all work / no prose): keep it honest.
                Text("This turn ended without a reply.")
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            }
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    userExpandedTurn = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Show more")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show more of this turn")
        }
    }

    private var fullTurn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let row = turn.userMessage, case .userMessage(let message) = row.item {
                // The provider has to acknowledge the prompt before it can be rewound to.
                let rewindable = message.messageId != nil && !rewindChoices.isEmpty
                ClaudeUserBubble(
                    text: message.text, isPending: row.isPending,
                    rewindChoices: rewindable ? rewindChoices : [],
                    onRewind: rewindable ? { scope in onRewind?(scope, message.messageId ?? "") } : nil,
                    attributed: bubbleAttributed(message.text),
                    canRewrite: canRewrite,
                    onEdit: rewindable ? { onEdit?(message.messageId ?? "", message.text) } : nil,
                    onRerun: rewindable ? { onRerun?(message.messageId ?? "", message.text) } : nil
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
                ClaudeProse(markdown: FilePathLinks.linkified(markdown: message.text), typography: typography, onAction: onMarkdown, localImageLoader: localImageLoader, isStreaming: isRunning)
                    .id("row:\(finalProse.seqEnd)")
                    .background(findHighlight(finalProse.seqEnd))
            }
            if !isRunning, let forkTarget = finalProse, (!copyText.isEmpty || onFork != nil) {
                HStack(spacing: 17) {
                    if !copyText.isEmpty {
                        ClaudeCopyButton(text: copyText, label: "Copy response")
                    }
                    if let onFork {
                        // Fork chat from here: seed a new agent with the history up to this answer.
                        Button {
                            Haptics.selection()
                            onFork(forkTarget)
                        } label: {
                            Image(systemName: "arrow.branch")
                                .font(.system(size: 15, weight: .light))
                                .foregroundStyle(ClaudePalette.tertiaryInk)
                                .frame(width: 28, height: 28)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Fork from here")
                    }
                }
                .padding(.top, 2)
            }
            if showShowLess {
                Button {
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                        userExpandedTurn = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Show less")
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show less of this turn")
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
                ClaudeProse(markdown: FilePathLinks.linkified(markdown: message.text), typography: typography, onAction: onMarkdown, localImageLoader: localImageLoader, isStreaming: turnIsRunning)
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
