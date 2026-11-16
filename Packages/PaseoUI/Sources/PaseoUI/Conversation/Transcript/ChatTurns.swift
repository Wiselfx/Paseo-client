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
    var isExpanded: Bool { userExpanded ?? isRunning }

    /// The answer stays visible even when the turn folds.
    var finalProse: TimelineRow? {
        guard !isRunning, case .prose(let row)? = turn.segments.last else { return nil }
        return row
    }

    /// The answer slot's prose: the last segment when it is prose, shown while the turn runs (work
    /// shown) and after it completes. It is one slot for both states on purpose (W1): while the
    /// turn ran the streaming message lived inside the work stack and, on completion, moved out to
    /// the answer position, which is a different place in the view tree, so every markdown piece,
    /// text view and code block of the answer was destroyed and rebuilt at the one moment the user
    /// looks at it (345 ms in the first measurement). Running with the work folded keeps the old
    /// behaviour: the streaming prose stays hidden.
    var answerProse: TimelineRow? {
        guard case .prose(let row)? = turn.segments.last else { return nil }
        return !isRunning || isExpanded ? row : nil
    }

    var bodySegments: [Turn.Segment] {
        answerProse == nil ? turn.segments : Array(turn.segments.dropLast())
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
                text, font: .paseo(.body),
                foreground: Palette.ink,
                linkColor: Palette.proseLink)
        }
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

    /// "Sent by {{name}}" above the bubble (upstream `user-message/index.tsx:95`, rendered
    /// from `message.tsx:481`), named by `agentTitle` (see `ClaudeSentByLine`).
    @ViewBuilder func sentByLine(_ sender: TimelineItem.AgentMessage.Sender) -> some View {
        ClaudeSentByLine(sender: sender)
    }

    var body: some View {
        let _ = PaseoPerf.body("TurnView")
        let _ = PaseoPerf.why(Self.self)
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
                // Upstream shows the rewind control only on an acknowledged message with text
                // (message.tsx:422 showTrailingRow, :514 hasText, :530 messageId).
                let rewindable = message.messageId != nil && !message.text.isEmpty
                    && !row.isPending && !rewindChoices.isEmpty
                ClaudeUserBubble(
                    text: message.text, isPending: row.isPending,
                    rewindChoices: rewindable ? rewindChoices : [],
                    onRewind: rewindable ? { scope in onRewind?(scope, message.messageId ?? "") } : nil,
                    attributed: bubbleAttributed(message.text),
                    rewindInFlight: rewindInFlight,
                    clientMessageId: message.clientMessageId,
                    sentAt: PaseoDate.parse(row.timestamp)
                )
                .id("row:\(row.seqEnd)")
                .background(findHighlight(row.seqEnd))
            }
            // Upstream TurnSummaryLine sits under the user message, above the final reply, and
            // opens the turn's work.
            Button {
                Haptics.selection()
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
            // Messages sent mid-turn and compaction markers stay visible while the work is folded.
            ForEach(visibleRows) { row in
                ClaudeVisibleRow(
                    row: row, highlightedSeq: highlightedSeq, attributed: bubbleAttributed)
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
                // The provider has to acknowledge the prompt before it can be rewound to.
                if let sender = message.sender { sentByLine(sender) }
                // Upstream shows the rewind control only on an acknowledged message with text
                // (message.tsx:422 showTrailingRow, :514 hasText, :530 messageId).
                let rewindable = message.messageId != nil && !message.text.isEmpty
                    && !row.isPending && !rewindChoices.isEmpty
                ClaudeUserBubble(
                    text: message.text, isPending: row.isPending,
                    rewindChoices: rewindable ? rewindChoices : [],
                    onRewind: rewindable ? { scope in onRewind?(scope, message.messageId ?? "") } : nil,
                    attributed: bubbleAttributed(message.text),
                    rewindInFlight: rewindInFlight,
                    clientMessageId: message.clientMessageId,
                    sentAt: PaseoDate.parse(row.timestamp)
                )
                .id("row:\(row.seqEnd)")
                .background(findHighlight(row.seqEnd))
            }
            if showsHeader { header }
            if isExpanded, !bodySegments.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(bodySegments) { segment in
                        ClaudeSegmentView(
                            segment: segment, turnIsRunning: isRunning,
                            onMarkdown: onMarkdown,
                            highlightedSeq: highlightedSeq, findTarget: findTarget,
                            onOpenFile: onOpenFile, bubbleAttributed: bubbleAttributed)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -2)))
            } else {
                // Work folded: the messages sent mid-turn and compaction markers still show, in
                // order, after the header.
                ForEach(visibleRows) { row in
                    ClaudeVisibleRow(
                        row: row, highlightedSeq: highlightedSeq, attributed: bubbleAttributed)
                }
            }
            if let answerProse, case .assistantMessage(let message) = answerProse.item {
                ClaudeProse(markdown: message.text, onAction: onMarkdown, isStreaming: isRunning)
                    .rowAnchor(answerProse.seqEnd)
                    .background(findHighlight(answerProse.seqEnd))
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
                    if !copyText.isEmpty {
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

    /// A brief wash on the matched row; `findHighlight` reads the view's flash parameter.
    func findHighlight(_ seqEnd: Int) -> some View {
        RoundedRectangle(cornerRadius: Radius.md)
            .fill(Palette.warning.opacity(highlightedSeq == seqEnd ? 0.18 : 0))
            .animation(Motion.settle.resolved(reduceMotion: reduceMotion), value: highlightedSeq)
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
        !copyText.isEmpty || (onFork != nil && finalProse != nil)
    }

    func toggleWork() {
        Haptics.selection()
        withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
            userExpanded = !isExpanded
        }
    }
}

/// A segment of a turn.

struct ClaudeSegmentView: View {
    let segment: Turn.Segment
    let turnIsRunning: Bool
    let onMarkdown: (MarkdownAction) -> Void
    var highlightedSeq: Int?
    var findTarget: Int?
    var onOpenFile: ((String) -> Void)?
    /// The turn's file-link builder for your bubbles (`ClaudeTurnView.bubbleAttributed`). Nil
    /// renders a mid-turn message as plain text.
    var bubbleAttributed: ((String) -> AttributedString)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch segment {
        case .work(let group):
            ClaudeWorkGroupCell(
                group: group, turnIsRunning: turnIsRunning,
                highlightedSeq: highlightedSeq, findTarget: findTarget, onOpenFile: onOpenFile)
        case .prose(let row):
            if case .assistantMessage(let message) = row.item {
                ClaudeProse(markdown: message.text, onAction: onMarkdown, isStreaming: turnIsRunning)
                    .rowAnchor(row.seqEnd)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(Palette.warning.opacity(highlightedSeq == row.seqEnd ? 0.18 : 0))
                            .animation(Motion.settle.resolved(reduceMotion: reduceMotion), value: highlightedSeq)
                    }
            }
        case .todo:
            // The per-turn card above owns todos now: a row here would duplicate it.
            EmptyView()
        case .notice(let row):
            // A message sent mid-turn is a notice row in the model (Turn.swift TurnDraft.add).
            if case .userMessage = row.item {
                ClaudeMidTurnBubble(
                    row: row, highlightedSeq: highlightedSeq, attributed: bubbleAttributed)
            } else {
                ClaudeNoticeRow(item: row.item)
            }
        }
    }
}

/// A message you sent while the turn was running, shown as the same bubble as the turn's first
/// message. Upstream shows a user message as a normal row wherever it falls in the stream
/// (`packages/app/src/agent-stream/layout.ts:330-331`). Drawn in two places, never both at once:
/// in place among the work when the work is shown, after the summary when it is folded.
struct ClaudeMidTurnBubble: View {
    let row: TimelineRow
    var highlightedSeq: Int?
    var attributed: ((String) -> AttributedString)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if case .userMessage(let message) = row.item {
            VStack(alignment: .leading, spacing: 14) {
                if let sender = message.sender {
                    ClaudeSentByLine(sender: sender)
                }
                // No rewind on a steered message: it is not a rewind point here.
                ClaudeUserBubble(
                    text: message.text, isPending: row.isPending,
                    rewindChoices: [], onRewind: nil,
                    attributed: attributed?(message.text),
                    clientMessageId: message.clientMessageId,
                    sentAt: PaseoDate.parse(row.timestamp)
                )
                .id("row:\(row.seqEnd)")
                .background {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(Palette.warning.opacity(highlightedSeq == row.seqEnd ? 0.18 : 0))
                        .animation(Motion.settle.resolved(reduceMotion: reduceMotion), value: highlightedSeq)
                }
            }
        }
    }
}

/// A row that stays in the chat while the work is folded: a message you sent mid-turn
/// (`ClaudeMidTurnBubble`) or a compaction marker (`ClaudeCompactionMarker`, the same marker
/// `ClaudeNoticeRow` draws in place). Upstream keeps both visible (`turn-collapse/model.ts:102`).
struct ClaudeVisibleRow: View {
    let row: TimelineRow
    var highlightedSeq: Int?
    var attributed: ((String) -> AttributedString)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if case .compaction(let status, let trigger, let preTokens) = row.item {
            ClaudeCompactionMarker(status: status, trigger: trigger, preTokens: preTokens)
                .id("row:\(row.seqEnd)")
                .background {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(Palette.warning.opacity(highlightedSeq == row.seqEnd ? 0.18 : 0))
                        .animation(Motion.settle.resolved(reduceMotion: reduceMotion), value: highlightedSeq)
                }
        } else {
            ClaudeMidTurnBubble(
                row: row, highlightedSeq: highlightedSeq, attributed: attributed)
        }
    }
}

/// "Sent by {{name}}" above a message you sent (upstream `user-message/index.tsx:95`). The name
/// is the sending agent's live title, then the sender's own title, then its id
/// (`TurnSummary.senderName`). Copy: `turnSummary.sentBy` (`en.ts:2151`).
struct ClaudeSentByLine: View {
    let sender: TimelineItem.AgentMessage.Sender
    @Environment(\.chatActions) private var actions

    /// A sender with no title anywhere falls back to its id (upstream does the same). A full
    /// UUID is noise on a chat row, so the view shows its first eight characters.
    private var name: String {
        let resolved = TurnSummary.senderName(
            agentTitle: actions?.agentTitle(sender.id), senderTitle: sender.title,
            senderID: sender.id)
        guard resolved == sender.id, UUID(uuidString: resolved) != nil else { return resolved }
        return String(resolved.prefix(8))
    }

    var body: some View {
        Text(TurnSummary.sentByLabel(name: name))
            .font(.paseo(.code))
            .foregroundStyle(Palette.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .trailing)
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
    /// False hides the workspace target: this host cannot create one, so offering it would only
    /// fail after the tap (E3 §2). Declared before `onFork` so the trailing closure still binds
    /// to it.
    var allowsWorkspace = true
    var onFork: (ClaudeForkTarget) async -> Void
    @State private var pending: ClaudeForkTarget?

    var body: some View {
        Menu {
            Button("Fork in a new tab", systemImage: "arrow.branch") { run(.tab) }
                .disabled(pending != nil)
            if allowsWorkspace {
                Button("Fork in a new workspace", systemImage: "square.on.square.dashed") {
                    run(.workspace)
                }
                .disabled(pending != nil)
            }
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
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(.rect)
    }
}

/// "2 thoughts, 1 tool call": the counted header, then a transparent card of rows, each opening on
/// its own. The card is capped at `min(400 pt, 50% of height)` and scrolls inside.

#endif

// MARK: - TurnRow (R6 §4)

/// One turn in the timeline: a narrow, **equatable** value so a streamed token re-evaluates only
/// the row it changed (`.equatable()` on the `ForEach` row).
///
/// The verbs come from `@Environment(\.chatActions)`-adjacent input — the same `ChatActions`
/// instance for the screen's life, so it is not part of `==`. `ClaudeTurnView` carries the layout
/// and its subviews; this row only decides what the row is told.
extension View {
    /// Used for rows whose `seqEnd` moves while they stream (assistant prose, reasoning and tool
    /// rows); your own bubbles and compaction markers keep the content `.id`, exactly as before.
    ///
    /// The scroll and find anchor of one timeline row (`row:<seqEnd>`), drawn as an invisible overlay
    /// of the row's own size so `scrollTo(_, anchor: .center)` still centres the whole row.
    ///
    /// W1: `.id` on the content itself makes the id part of the content's identity, and a streaming
    /// row's `seqEnd` moves with every delta, so the whole prose subtree (every markdown piece, text
    /// view and code block) was destroyed and rebuilt per token: 12 to 25 markdown views per update,
    /// each one re-measured and re-highlighted. The anchor now changes identity; the content does not.
    func rowAnchor(_ seqEnd: Int) -> some View {
        overlay { Color.clear.allowsHitTesting(false).accessibilityHidden(true).id("row:\(seqEnd)") }
    }
}

struct TurnRow: View, Equatable {
    let turn: Turn
    /// The agent/host capability value rows draw; part of `==` so a capability change re-renders
    /// the row even though its content did not change (E3 §2).
    let availability: TurnActionAvailability
    let isLatest: Bool
    /// The seqEnd of the current find match, non-nil only when it is inside this turn.
    let findSeq: Int?
    /// The seqEnd whose row flashes after a find step, same rule.
    let flashSeq: Int?
    let isLanding: Bool
    let actions: ChatActions
    /// The user stopped this turn; the parent reads `ConversationStore.canceledTurnIds` (N5 A).
    /// Part of `==`: a stopped turn must redraw without its content changing.
    var isCanceled: Bool = false

    @State private var landingStartedAt = Date()

    /// Compared off the main actor, so the conformance does not cross isolation: every compared
    /// input is a plain value (`Turn` is `Sendable`), and `actions` is not part of `==`.
    nonisolated static func == (lhs: TurnRow, rhs: TurnRow) -> Bool {
        lhs.turn == rhs.turn && lhs.availability == rhs.availability
            && lhs.isLatest == rhs.isLatest && lhs.findSeq == rhs.findSeq
            && lhs.flashSeq == rhs.flashSeq && lhs.isLanding == rhs.isLanding
            && lhs.isCanceled == rhs.isCanceled
    }

    var body: some View {
        let _ = PaseoPerf.body("TurnRow")
        let _ = PaseoPerf.why(Self.self)
        ClaudeTurnView(
            turn: turn,
            onMarkdown: actions.markdown,
            highlightedSeq: flashSeq,
            findTarget: findSeq,
            onOpenFile: actions.openFile,
            rewindChoices: availability.rewindChoices,
            onRewind: availability.rewindChoices.isEmpty ? nil : actions.rewind,
            onFork: availability.canForkAtBoundary ? actions.fork : nil,
            onForkInFlight: availability.canForkInFlight ? actions.forkInFlight : nil,
            rewindInFlight: availability.rewindInFlight,
            canForkWorkspace: availability.canForkWorkspace,
            isLatestTurn: isLatest,
            isCanceled: isCanceled
        )
        .overlay(alignment: .top) {
            if isLanding {
                LandingLine(startedAt: landingStartedAt)
                    .offset(y: -8)
            }
        }
        .onChange(of: isLanding) { _, landed in
            if landed { landingStartedAt = Date() }
        }
    }
}

extension Turn {
    /// Does this turn own the row with `seqEnd`? O(rows of this turn), and only ever asked while
    /// find is open.
    func containsRow(seqEnd: Int) -> Bool {
        if let row = userMessage, row.seqEnd == seqEnd { return true }
        for segment in segments {
            switch segment {
            case .work(let group):
                if group.rows.contains(where: { $0.seqEnd == seqEnd }) { return true }
            case .prose(let row), .todo(let row), .notice(let row):
                if row.seqEnd == seqEnd { return true }
            }
        }
        return false
    }
}
