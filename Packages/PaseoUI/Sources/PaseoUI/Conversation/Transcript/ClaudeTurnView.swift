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
    let onMarkdown: (MarkdownAction) -> Void
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
    /// Fork, with the target menu (V1): called with the chosen target and the row to pin the
    /// boundary at. Nil hides the menu — no host support, or nothing to fork from.
    var onFork: ((ClaudeForkTarget, TimelineRow) async -> Void)? = nil
    /// The running turn's fork. No boundary: the whole timeline as it stands, partially streamed
    /// answer included (upstream `turn-footer.tsx:38-46`). Nil hides it.
    var onForkInFlight: ((ClaudeForkTarget) async -> Void)? = nil
    /// A rewind is in flight: the rewind items on your bubbles are locked (upstream
    /// `rewind-menu.tsx` `isLocked`, fed by `use-rewind-agent-mutation.ts` `isPending`).
    var rewindInFlight: Bool = false
    /// The fork menu offers "Fork in a new workspace" beside the tab target.
    var canForkWorkspace: Bool = false
    /// False for every turn except the most recent one; only that turn never collapses.
    var isLatestTurn: Bool = true
    /// The user stopped this turn (`ConversationStore.canceledTurnIds`): it shows no "Completed in"
    /// text. The parent reads the store and passes the flag; the row never reads the store (N5 A).
    var isCanceled: Bool = false

    /// Nil until the reader taps, so the default can follow the turn's phase.
    @State private var userExpanded: Bool?
    /// Collapse-turns override: true = expanded (full work), nil = the mode's default.
    @State private var userExpandedTurn: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ChatDisplayMode.storageKey) private var chatDisplay = ChatDisplayMode.full.rawValue

    var isRunning: Bool { turn.phase == .running }
    /// The work is shown while it runs, when the reader opened it, and when the current find match lives
    /// in it (upstream `view.tsx:687`: find reveals a match inside a collapsed turn by opening the turn
    /// first). A match in the prompt or in the answer needs no opening.
    var isExpanded: Bool { userExpanded ?? (isRunning || findTargetsWork) }

    /// True when the find match is a row of the work (an assistant message before the answer, a tool
    /// call, a thought), which the folded turn does not draw.
    var findTargetsWork: Bool {
        guard let seq = findTarget else { return false }
        var segments = turn.segments[...]
        if case .prose? = segments.last { segments = segments.dropLast() }
        for segment in segments {
            switch segment {
            case .work(let group):
                if group.rows.contains(where: { $0.seqStart <= seq && seq <= $0.seqEnd }) { return true }
            case .prose(let row), .todo(let row), .notice(let row):
                if row.seqStart <= seq, seq <= row.seqEnd { return true }
            }
        }
        return false
    }

    /// The answer stays visible even when the turn folds.
    var finalProse: TimelineRow? {
        guard !isRunning, case .prose(let row)? = turn.segments.last else { return nil }
        return row
    }

    /// The answer: the last segment when it is prose, shown while the turn runs (work shown) and
    /// after it completes. Running with the work folded keeps the streaming prose hidden.
    var answerProse: TimelineRow? {
        guard case .prose(let row)? = turn.segments.last else { return nil }
        return !isRunning || isExpanded ? row : nil
    }

    /// The segments the full turn draws, in one `ForEach` keyed by segment id (W1). Opened, that is
    /// every segment; folded, the rows that stay visible plus the answer. Before, the answer had a
    /// slot of its own outside the work stack, so a streamed message was destroyed and rebuilt —
    /// every markdown piece and code block, its unrevealed backlog painted at once — the moment a
    /// tool call followed it and it moved into the stack.
    var shownSegments: [Turn.Segment] {
        if isExpanded { return turn.segments }
        var shown = turn.segments.filter { segment in
            guard case .notice(let row) = segment else { return false }
            switch row.item {
            case .userMessage, .compaction: return true
            default: return false
            }
        }
        if let answerProse { shown.append(.prose(answerProse)) }
        return shown
    }

    /// The segments other than the answer: what the work header stands for.
    var bodySegments: ArraySlice<Turn.Segment> {
        answerProse == nil ? turn.segments[...] : turn.segments.dropLast()
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

    /// Rows that stay visible while the work is folded: messages you sent while this turn ran, and
    /// compaction markers. Upstream never folds these away (`turn-collapse/model.ts:102`
    /// `staysVisibleWhenCollapsed`), so they render whether the work is shown or folded: in place
    /// inside the work when shown, after the summary when not.
    var visibleRows: [TimelineRow] {
        turn.segments.compactMap { (segment: Turn.Segment) -> TimelineRow? in
            guard case .notice(let row) = segment else { return nil }
            switch row.item {
            case .userMessage, .compaction: return row
            default: return nil
            }
        }
    }

    /// The overview sentence under the prompt. In `collapseTurns` it is the whole fold affordance;
    /// the answer below it is never clipped, so there is no separate "Show more".
    var turnSummaryLabel: String { TurnSummary(turn: turn).detailsLabel }

    var body: some View {
        let _ = PaseoPerf.body("TurnView")
        let _ = PaseoPerf.why(Self.self)
        // The haptics sit outside the branch: opening the folded turn removes `collapsedTurn`
        // from the tree, and a modifier attached inside it would go with it.
        Group {
            if showsCollapsedTurn {
                collapsedTurn
            } else {
                fullTurn
            }
        }
        .paseoFeedback(.selection, trigger: userExpanded) { _, new in new != nil }
        .paseoFeedback(.selection, trigger: userExpandedTurn) { _, new in new != nil }
    }

    /// The folded turn: the prompt plus the turn summary, then the answer in full.
    /// Every message is always shown in full (UX spec §4.3); the fold hides work, never prose.
    @ViewBuilder private var collapsedTurn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let row = turn.userMessage, case .userMessage(let message) = row.item {
                TurnPrompt(
                    row: row, message: message,
                    rewindChoices: rewindChoices, rewindInFlight: rewindInFlight,
                    isHighlighted: highlightedSeq == row.seqEnd, onRewind: onRewind)
            }
            // Upstream TurnSummaryLine sits under the user message, above the final reply, and
            // opens the turn's work.
            Button {
                withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                    userExpandedTurn = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text(turnSummaryLabel)
                    Image(systemName: "chevron.down")
                        .font(.glyph(.small, weight: .semibold))
                }
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(turnSummaryLabel)
            .accessibilityValue("Collapsed")
            .accessibilityHint("Shows the work in this turn")
            // Messages sent mid-turn and compaction markers stay visible while the work is folded.
            ForEach(visibleRows) { row in
                ClaudeVisibleRow(row: row, highlightedSeq: highlightedSeq)
            }
            if let finalProse, case .assistantMessage(let message) = finalProse.item {
                ClaudeProse(markdown: message.text, onAction: onMarkdown)
                if let todoState = turn.todoState {
                    // One card per turn for its todos and plan (live while running),
                    // ahead of the file changes.
                    TurnTodoCard(state: todoState).equatable()
                }
                if !isRunning, let summary = turn.changeSummary {
                    TurnChangesCard(summary: summary, turnID: turn.id).equatable()
                }
            } else {
                // A turn with no answer section (all work / no prose): keep it honest.
                Text("This turn ended without a reply.")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
    }

    private var fullTurn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let row = turn.userMessage, case .userMessage(let message) = row.item {
                TurnPrompt(
                    row: row, message: message,
                    rewindChoices: rewindChoices, rewindInFlight: rewindInFlight,
                    isHighlighted: highlightedSeq == row.seqEnd, onRewind: onRewind)
            }
            if showsHeader { header }
            // One stack, keyed by segment, for the work and the answer alike: a message keeps its
            // views whether it is the newest segment, settles above a tool call that follows it,
            // or stays as the answer when the finished turn folds its work away.
            ForEach(shownSegments) { segment in
                if !isExpanded, case .notice(let row) = segment {
                    ClaudeVisibleRow(row: row, highlightedSeq: highlightedSeq)
                } else {
                    ClaudeSegmentView(
                        segment: segment, turnIsRunning: isRunning,
                        isTail: isRunning && segment.id == turn.segments.last?.id,
                        onMarkdown: onMarkdown,
                        highlightedSeq: highlightedSeq, findTarget: findTarget,
                        onOpenFile: onOpenFile)
                        .transition(.opacity.combined(with: .offset(y: -2)))
                }
            }
            if let todoState = turn.todoState {
                // One card per turn for its todos and plan (live while running).
                TurnTodoCard(state: todoState).equatable()
            }
            if !isRunning, let summary = turn.changeSummary {
                // The turn's file changes close the turn, after the final prose.
                TurnChangesCard(summary: summary, turnID: turn.id).equatable()
            }
            if !isRunning, showsAnswerFooter {
                HStack(spacing: 17) {
                    if hasProse {
                        ClaudeCopyButton(text: copyText, label: "Copy response")
                    }
                    if let onFork, let forkTarget = finalProse {
                        ClaudeForkMenu(allowsWorkspace: canForkWorkspace) { target in
                            await onFork(target, forkTarget)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .onChange(of: turn.phase) { _, phase in
            // A finished turn folds itself away; the answer stays on the page.
            if phase != .running {
                withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) { userExpanded = nil }
            }
        }
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
                        ClaudeLiveStatusLine(turn: turn)
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    isExpanded ? "Collapses the work in this turn" : "Shows the work in this turn")
                if let onForkInFlight {
                    ClaudeForkMenu(allowsWorkspace: canForkWorkspace) { target in
                        await onForkInFlight(target)
                    }
                }
                ClaudeChevron(expanded: isExpanded)
            }
        } else {
            Button { toggleWork() } label: {
                HStack(spacing: 8) {
                    switch turn.phase {
                    case .running:
                        ClaudeLiveStatusLine(turn: turn)
                    case .completed:
                        // A stopped turn says nothing here: upstream has no wording for it (N5 A).
                        if !isCanceled {
                            // A clock before the duration, as the reasoning line has one (user directive).
                            Image(systemName: "clock")
                                .font(.paseo(.callout))
                                .foregroundStyle(Palette.secondaryInk)
                                .accessibilityHidden(true)
                            Text(turn.duration.map(DurationText.completed) ?? "Completed")
                                .font(.paseo(.callout))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        Spacer(minLength: 0)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.paseo(.callout))
                            .foregroundStyle(Palette.failureInk)
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

    /// True when the answer footer has anything to show: copy or the fork menu (needs a boundary
    /// row).
    var showsAnswerFooter: Bool {
        hasProse || (onFork != nil && finalProse != nil)
    }

    /// Whether the turn said anything: what Copy needs, without joining the whole reply per pass.
    var hasProse: Bool {
        turn.segments.contains { segment in
            guard case .prose(let row) = segment, case .assistantMessage(let message) = row.item
            else { return false }
            return !message.text.isEmpty
        }
    }

    func toggleWork() {
        withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
            userExpanded = !isExpanded
        }
    }
}
#endif
