#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One turn: your bubble, the process header, the process body, the answer.
///
/// In `Collapse turns` mode (Settings → General → Chat), completed turns older than the most
/// recent one show the prompt plus the turn summary; **Show less** is gone — the answer itself
/// always renders in full. Find expands whatever holds a match automatically.
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
    /// Fork, with the target menu (V1): called with the chosen target and the row to pin the
    /// boundary at. Nil hides the menu — no host support, or nothing to fork from.
    var onFork: ((ClaudeForkTarget, TimelineRow) async -> Void)? = nil
    /// The running turn's fork. No boundary: the whole timeline as it stands, partially streamed
    /// answer included (upstream `turn-footer.tsx:38-46`). Nil hides it.
    var onForkInFlight: ((ClaudeForkTarget) async -> Void)? = nil
    /// DSH "Delete this turn": called with the turn's own prompt row; the transcript forks at the
    /// row before it. Nil hides the control.
    var onDeleteTurn: ((TimelineRow) -> Void)? = nil
    /// DSH "Retract this message": called with the turn's prompt row (same cut as Delete) — the
    /// transcript puts the text back in the new session's composer.
    var onRetract: ((TimelineRow) -> Void)? = nil
    /// False for every turn except the most recent one; only that turn never collapses.
    var isLatestTurn: Bool = true

    /// Nil until the reader taps, so the default can follow the turn's phase.
    @State private var userExpanded: Bool?
    /// Collapse-turns override: true = expanded (full work), nil = the mode's default.
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

    /// The overview sentence under the prompt. In `collapseTurns` it is the whole fold affordance;
    /// the answer below it is never clipped, so there is no separate "Show more".
    var turnSummaryLabel: String { TurnSummary(turn: turn).detailsLabel }

    /// "Sent by {{name}}" above the bubble (upstream `user-message/index.tsx:95`, rendered
    /// from `message.tsx:481`). No agent registry reaches this view, so the name falls back
    /// to `sender.title ?? sender.id` instead of resolving the agent's live title.
    @ViewBuilder func sentByLine(_ sender: TimelineItem.AgentMessage.Sender) -> some View {
        Text(TurnSummary.sentByLabel(name: TurnSummary.senderName(agentTitle: nil, senderTitle: sender.title, senderID: sender.id)))
            .font(typography.mono(13))
            .foregroundStyle(ClaudePalette.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    var body: some View {
        if showsCollapsedTurn {
            collapsedTurn
        } else {
            fullTurn
        }
    }

    /// The folded turn: the prompt plus the turn summary, then the answer in full.
    /// Every message is always shown in full (UX spec §4.3); the fold hides work, never prose.
    @ViewBuilder private var collapsedTurn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let row = turn.userMessage, case .userMessage(let message) = row.item {
                if let sender = message.sender { sentByLine(sender) }
                let rewindable = message.messageId != nil && !rewindChoices.isEmpty
                // Retract forks the same cut as Edit, so it needs a message the daemon
                // acknowledged — and never while the turn is still producing (DSH hides it).
                let retractible = rewindable && !row.isPending && !isRunning
                ClaudeUserBubble(
                    text: message.text, isPending: row.isPending,
                    rewindChoices: rewindable ? rewindChoices : [],
                    onRewind: rewindable ? { scope in onRewind?(scope, message.messageId ?? "") } : nil,
                    attributed: bubbleAttributed(message.text),
                    canRewrite: canRewrite,
                    onEdit: rewindable ? { onEdit?(message.messageId ?? "", message.text) } : nil,
                    onRerun: rewindable ? { onRerun?(message.messageId ?? "", message.text) } : nil,
                    onRetract: retractible ? { onRetract?(row) } : nil
                )
                .id("row:\(row.seqEnd)")
                .background(findHighlight(row.seqEnd))
            }
            // Upstream TurnSummaryLine sits under the user message, above the final reply, and
            // opens the turn's work.
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    userExpandedTurn = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text(turnSummaryLabel)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(turnSummaryLabel)
            if let finalProse, case .assistantMessage(let message) = finalProse.item {
                ClaudeProse(markdown: FilePathLinks.linkified(markdown: message.text), typography: typography, onAction: onMarkdown, localImageLoader: localImageLoader)
            } else {
                // A turn with no answer section (all work / no prose): keep it honest.
                Text("This turn ended without a reply.")
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            }
        }
    }

    private var fullTurn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let row = turn.userMessage, case .userMessage(let message) = row.item {
                // The provider has to acknowledge the prompt before it can be rewound to.
                if let sender = message.sender { sentByLine(sender) }
                let rewindable = message.messageId != nil && !rewindChoices.isEmpty
                // Retract forks the same cut as Edit, so it needs a message the daemon
                // acknowledged — and never while the turn is still producing (DSH hides it).
                let retractible = rewindable && !row.isPending && !isRunning
                ClaudeUserBubble(
                    text: message.text, isPending: row.isPending,
                    rewindChoices: rewindable ? rewindChoices : [],
                    onRewind: rewindable ? { scope in onRewind?(scope, message.messageId ?? "") } : nil,
                    attributed: bubbleAttributed(message.text),
                    canRewrite: canRewrite,
                    onEdit: rewindable ? { onEdit?(message.messageId ?? "", message.text) } : nil,
                    onRerun: rewindable ? { onRerun?(message.messageId ?? "", message.text) } : nil,
                    onRetract: retractible ? { onRetract?(row) } : nil
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
            if !isRunning, showsAnswerFooter {
                HStack(spacing: 17) {
                    if !copyText.isEmpty {
                        ClaudeCopyButton(text: copyText, label: "Copy response")
                    }
                    if let onFork, let forkTarget = finalProse {
                        ClaudeForkMenu { target in await onFork(target, forkTarget) }
                    }
                    if let onDeleteTurn, let userRow = turn.userMessage {
                        ClaudeTurnActionButton(
                            systemImage: "trash", accessibilityLabel: "Delete this turn"
                        ) { onDeleteTurn(userRow) }
                    }
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

    /// The work header. A running turn gets the fork menu inline (`turn-footer.tsx:139-166`);
    /// the fold toggle shrinks to the status line so the menu's own taps never reach it.
    @ViewBuilder var header: some View {
        if isRunning {
            HStack(spacing: 8) {
                Button { toggleWork() } label: {
                    HStack(spacing: 8) {
                        ClaudeLiveStatusLine(turn: turn, typography: typography)
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    isExpanded ? "Collapses the work in this turn" : "Shows the work in this turn")
                if let onForkInFlight {
                    ClaudeForkMenu { target in await onForkInFlight(target) }
                }
                ClaudeChevron(expanded: isExpanded)
            }
        } else {
            Button { toggleWork() } label: {
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
            .accessibilityHint(
                isExpanded ? "Collapses the work in this turn" : "Shows the work in this turn")
        }
    }

    /// True when the answer footer has anything to show: copy, the fork menu (needs a boundary
    /// row), or the turn's Delete control.
    var showsAnswerFooter: Bool {
        !copyText.isEmpty || (onFork != nil && finalProse != nil) || onDeleteTurn != nil
    }

    func toggleWork() {
        Haptics.selection()
        withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
            userExpanded = !isExpanded
        }
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

/// Where a fork goes. Upstream's `AssistantForkTarget` (`assistant-fork-menu.tsx:14-15`).
enum ClaudeForkTarget: Sendable {
    case tab
    case workspace
}

/// The answer footer's fork control: one button opening the target menu (upstream
/// `assistant-fork-menu.tsx:100-121`). Labels are `en.ts:334-336`, verbatim.
///
/// While a target is in flight the trigger turns into a spinner and is disabled, so neither item
/// can start a second fork. Upstream puts the spinner **inside** the pending item and keeps it
/// enabled; a SwiftUI menu item cannot host a `ProgressView`, so the spinner lives on the trigger.
struct ClaudeForkMenu: View {
    var onFork: (ClaudeForkTarget) async -> Void
    @State private var pending: ClaudeForkTarget?

    var body: some View {
        Menu {
            Button("Fork in a new tab", systemImage: "arrow.branch") { run(.tab) }
                .disabled(pending != nil)
            Button("Fork in a new workspace", systemImage: "square.on.square.dashed") {
                run(.workspace)
            }
            .disabled(pending != nil)
        } label: {
            ClaudeTurnActionGlyph(systemImage: "arrow.branch", busy: pending != nil)
        }
        .buttonStyle(.plain)
        .disabled(pending != nil)
        .accessibilityLabel("Fork chat from here")
    }

    /// Starts one fork at a time and holds the button down until it lands.
    private func run(_ target: ClaudeForkTarget) {
        guard pending == nil else { return }
        Haptics.selection()
        pending = target
        Task {
            await onFork(target)
            pending = nil
        }
    }
}

/// A 28 pt footer control: the glyph, or a small spinner where the glyph was while work runs.
struct ClaudeTurnActionGlyph: View {
    var systemImage: String
    var busy: Bool

    var body: some View {
        Group {
            if busy {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(.rect)
    }
}

/// A plain 28 pt footer action (no menu), e.g. "Delete this turn".
struct ClaudeTurnActionButton: View {
    var systemImage: String
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            ClaudeTurnActionGlyph(systemImage: systemImage, busy: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// "2 thoughts, 1 tool call": the counted header, then a transparent card of rows, each opening on
/// its own. The card is capped at `min(400 pt, 50% of height)` and scrolls inside.

#endif
