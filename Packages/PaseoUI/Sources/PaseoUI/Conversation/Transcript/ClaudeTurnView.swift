#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One turn: your bubble, the work header, the work, the answer.
///
/// A finished turn folds its work behind one line that says what the work did and how long it
/// took (`TurnOutcomeLine`); one tap opens it. The answer (the turn's last message) always stays
/// on the page, wherever it sits among the work. In `Collapse turns` mode (Settings → General →
/// Chat) older turns also hide their copy / fork buttons (the row keeps its height). Find opens
/// whatever holds a match.
///
/// Spacing is fixed by construction: every slot of the stack (bubble, header, segments, footer)
/// keeps one height for the turn's whole life, and nothing that draws nothing takes a slot, so
/// the distance between your bubble and the answer never changes as the turn runs and ends.
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
        let answerId = lastProse?.id
        for segment in turn.segments where segment.id != answerId {
            switch segment {
            case .work(let group):
                if group.rows.contains(where: { $0.seqStart <= seq && seq <= $0.seqEnd }) { return true }
            case .prose(let row), .todo(let row), .notice(let row):
                if row.seqStart <= seq, seq <= row.seqEnd { return true }
            }
        }
        return false
    }

    /// The turn's last message, wherever it sits: a turn that ends on a tool call still keeps
    /// what it last said on the page when it folds (it used to fold that away with the work).
    var lastProse: TimelineRow? {
        for segment in turn.segments.reversed() {
            if case .prose(let row) = segment { return row }
        }
        return nil
    }

    /// The answer of a finished turn: the fork boundary.
    var finalProse: TimelineRow? { isRunning ? nil : lastProse }

    /// The answer, shown after the turn completes and while it runs with its work shown.
    /// Running with the work folded keeps the streaming prose hidden.
    var answerProse: TimelineRow? {
        !isRunning || isExpanded ? lastProse : nil
    }

    /// The segments the full turn draws, in one `ForEach` keyed by segment id (W1). Opened, that is
    /// every segment; folded, the rows that stay visible plus the answer. Before, the answer had a
    /// slot of its own outside the work stack, so a streamed message was destroyed and rebuilt —
    /// every markdown piece and code block, its unrevealed backlog painted at once — the moment a
    /// tool call followed it and it moved into the stack.
    ///
    /// A segment that draws nothing never takes a slot: in the stack each slot costs a 14 pt gap,
    /// so a todo segment (the card below owns todos) or a message that has not said anything yet
    /// opened a blank gap that closed again later.
    var shownSegments: [Turn.Segment] {
        let drawn = turn.segments.filter(Self.draws)
        if isExpanded { return drawn }
        let answerId = answerProse?.id
        // In document order: messages you sent mid-turn and compaction markers never fold away
        // (upstream `turn-collapse/model.ts:102` `staysVisibleWhenCollapsed`), nor does the answer.
        return drawn.filter { segment in
            if segment.id == answerId { return true }
            guard case .notice(let row) = segment else { return false }
            switch row.item {
            case .userMessage, .compaction: return true
            default: return false
            }
        }
    }

    /// Whether a segment draws anything (`ClaudeSegmentView`): todos draw in the turn's card, and
    /// prose draws only an assistant message with text.
    static func draws(_ segment: Turn.Segment) -> Bool {
        switch segment {
        case .todo:
            return false
        case .prose(let row):
            guard case .assistantMessage(let message) = row.item else { return false }
            return !message.text.isEmpty
        case .work, .notice:
            return true
        }
    }

    /// Whether the turn has anything besides the answer for the header to open.
    var hasWork: Bool {
        let answerId = answerProse?.id
        return turn.segments.contains { $0.id != answerId && Self.draws($0) }
    }

    var chatDisplayMode: ChatDisplayMode {
        ChatDisplayMode(rawValue: chatDisplay) ?? .full
    }

    /// `collapseTurns` trims older finished turns to prompt, outcome line and answer.
    var showsFooter: Bool {
        guard !isRunning, hasProse || (onFork != nil && finalProse != nil) else { return false }
        return chatDisplayMode != .collapseTurns || isLatestTurn
    }

    var body: some View {
        let _ = PaseoPerf.body("TurnView")
        let _ = PaseoPerf.why(Self.self)
        fullTurn
            .paseoFeedback(.selection, trigger: userExpanded) { _, new in new != nil }
    }

    private var fullTurn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let row = turn.userMessage, case .userMessage(let message) = row.item {
                TurnPrompt(
                    row: row, message: message,
                    rewindChoices: rewindChoices, rewindInFlight: rewindInFlight,
                    isHighlighted: highlightedSeq == row.seqEnd, onRewind: onRewind)
            }
            // Every turn has its header line, live or finished, so the answer sits at the same
            // distance from your bubble before and after the turn ends. (It used to vanish from a
            // turn without work when it finished, and the answer jumped up by 38 pt.) One height in
            // every state: the running line carries the 44 pt fork target, the finished one did not,
            // so every turn shrank by 20 pt as it ended.
            header
                .frame(minHeight: Metrics.hitSize)
            // One stack, keyed by segment, for the work and the answer alike: a message keeps its
            // views whether it is the newest segment, settles above a tool call that follows it,
            // or stays as the answer when the finished turn folds its work away.
            ForEach(shownSegments) { segment in
                if !isExpanded, case .notice(let row) = segment {
                    ClaudeVisibleRow(row: row, highlightedSeq: highlightedSeq)
                } else {
                    // Equal segments skip their body (`ClaudeSegmentView ==`), so a streamed token
                    // re-runs only the segment that changed.
                    ClaudeSegmentView(
                        segment: segment, turnIsRunning: isRunning,
                        isTail: isRunning && segment.id == turn.segments.last?.id,
                        onMarkdown: onMarkdown,
                        highlightedSeq: highlightedSeq, findTarget: findTarget,
                        onOpenFile: onOpenFile)
                        .equatable()
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
            if !isRunning {
                // A finished turn always keeps its footer's height, whatever it holds: an older turn
                // in Collapse mode hides the buttons but keeps the row, so sending a new prompt
                // never shrinks the turn above it, and fork support arriving late never grows one.
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
                .frame(minHeight: Metrics.hitSize, alignment: .leading)
                .padding(.top, 2)
                .opacity(showsFooter ? 1 : 0)
                .allowsHitTesting(showsFooter)
                .accessibilityHidden(!showsFooter)
            }
        }
        .onChange(of: turn.phase) { _, phase in
            // A finished turn folds itself away; the answer stays on the page. The fold is one
            // unanimated step: UIKit resizes the transcript cell in the same pass, so an animation
            // here would run on a second clock and look detached. Only the reader's tap animates.
            if phase != .running {
                userExpanded = nil
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
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(
                    isExpanded ? "Collapses the work in this turn" : "Shows the work in this turn")
                if let onForkInFlight {
                    ClaudeForkMenu(allowsWorkspace: canForkWorkspace) { target in
                        await onForkInFlight(target)
                    }
                }
                ClaudeChevron(expanded: isExpanded)
            }
        } else if !hasWork {
            // Nothing to open: the same line, without the chevron or a tap.
            HStack(spacing: 8) {
                finishedStatus
                Spacer(minLength: 0)
            }
        } else {
            Button { toggleWork() } label: {
                HStack(spacing: 8) {
                    finishedStatus
                    Spacer(minLength: 0)
                    ClaudeChevron(expanded: isExpanded)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(
                isExpanded ? "Collapses the work in this turn" : "Shows the work in this turn")
        }
    }

    /// A finished turn's status: what the work did and how long it took behind a clock (user
    /// directive), or the failure.
    @ViewBuilder private var finishedStatus: some View {
        switch turn.phase {
        case .running:
            ClaudeLiveStatusLine(turn: turn)
        case .completed:
            let summary = TurnSummary(turn: turn).overviewLabel
            TurnOutcomeLine(
                summary: summary.isEmpty ? nil : summary,
                duration: turn.duration, isCanceled: isCanceled)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.paseo(.callout))
                .foregroundStyle(Palette.failureInk)
                .lineLimit(2)
        }
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
