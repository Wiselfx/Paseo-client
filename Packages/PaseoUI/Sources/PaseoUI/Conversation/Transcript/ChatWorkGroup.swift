#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - The work timeline

/// The work of a turn as one timeline: a hairline rail with a node per step.
///
/// Thinking is the model's own voice: the serif, no card, a node of its own. Settled, it is one line
/// ("Thought for 4s", then its first words); while it streams, its newest lines run under a live
/// "Thinking"; opened, it reads in full. A tool call is one precise line: what it did (the verb turns
/// from "Running" to "Ran" when it lands), what it did it to in mono, what came of it (the diff count,
/// a failed exit), and it opens onto its output.
///
/// Nothing here scrolls inside the transcript or measures itself to lay out twice: a step is as tall as
/// what it shows, output previews are bounded, and a long run shows its newest steps with the earlier
/// ones a tap away. Steps are equatable values, so a streamed token redraws the one step it changed.
struct ClaudeWorkTimeline: View {
    let group: Turn.WorkGroup
    let turnIsRunning: Bool
    /// The turn's newest segment while it runs: its last step is the one happening now.
    let isTail: Bool
    var highlightedSeq: Int?
    var findTarget: Int?
    var onOpenFile: ((String) -> Void)?

    /// Collapse-tool-calls mode: the run is one summary line until the reader opens it.
    @State private var userOpened: Bool?
    /// A long run shows its newest steps; the earlier ones open on a tap or for a find match.
    @State private var showsEarlier = false
    @State private var cache = WorkTimelineCache()
    @State private var liveSince = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ChatDisplayMode.storageKey) private var chatDisplay = ChatDisplayMode.full.rawValue

    /// Past this many steps the run folds its older ones away…
    static let foldThreshold = 8
    /// …and keeps this many of the newest.
    static let keptSteps = 5

    private var summarizes: Bool { ChatDisplayMode(rawValue: chatDisplay) == .collapseToolCalls }
    private var isOpen: Bool { userOpened ?? !summarizes }

    var body: some View {
        let derived = cache.derived(for: group)
        VStack(alignment: .leading, spacing: 0) {
            if summarizes {
                summaryRow(derived)
            }
            if isOpen {
                steps(derived)
                    .transition(.opacity.combined(with: .offset(y: -2)))
            }
        }
        .onChange(of: findTarget, initial: true) { _, target in reveal(target) }
    }

    // MARK: Steps

    @ViewBuilder private func steps(_ derived: WorkTimelineDerived) -> some View {
        let all = derived.steps
        let hidden = !showsEarlier && all.count > Self.foldThreshold ? all.count - Self.keptSteps : 0
        VStack(alignment: .leading, spacing: 0) {
            if hidden > 0 {
                WorkEarlierSteps(count: hidden) {
                    Haptics.selection()
                    withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                        showsEarlier = true
                    }
                }
            }
            ForEach(hidden..<all.count, id: \.self) { index in
                let step = all[index]
                WorkStepView(
                    step: step,
                    rail: WorkRailPosition(above: index > 0, below: index < all.count - 1),
                    isLive: isTail && index == all.count - 1,
                    duration: derived.durations[step.id],
                    highlighted: highlightedSeq.map { step.covers($0) } ?? false,
                    findHit: findTarget.map { step.covers($0) } ?? false,
                    onOpenFile: onOpenFile
                )
                .equatable()
                .id(step.id)
            }
        }
    }

    /// A find match inside the run opens the run and, when it sits among the folded steps, them too.
    private func reveal(_ target: Int?) {
        guard let target, group.rows.contains(where: { $0.seqStart <= target && target <= $0.seqEnd })
        else { return }
        let steps = cache.derived(for: group).steps
        let index = steps.firstIndex { $0.covers(target) } ?? steps.count
        let folded = steps.count > Self.foldThreshold && index < steps.count - Self.keptSteps
        guard (summarizes && userOpened != true) || (folded && !showsEarlier) else { return }
        withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
            if summarizes { userOpened = true }
            if folded { showsEarlier = true }
        }
    }

    // MARK: Summary (collapse-tool-calls mode)

    private func summaryRow(_ derived: WorkTimelineDerived) -> some View {
        Button {
            Haptics.selection()
            withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                userOpened = !isOpen
            }
        } label: {
            HStack(spacing: WorkTimelineMetrics.gutter - WorkTimelineMetrics.nodeSize) {
                ClaudeGlyph(kind: derived.seat, size: 14, color: Palette.tertiaryInk)
                    .frame(width: WorkTimelineMetrics.nodeSize, height: WorkTimelineMetrics.nodeSize)
                Group {
                    if isTail && group.isActive {
                        ClaudeSweepLabel(startedAt: liveSince, rest: Palette.tertiaryInk) { ink in
                            summaryLabel(derived.summary, ink)
                        }
                    } else {
                        summaryLabel(derived.summary, Palette.tertiaryInk)
                    }
                }
                Spacer(minLength: 4)
                ClaudeTurnChevron(expanded: isOpen)
            }
            .frame(minHeight: WorkTimelineMetrics.headerHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(derived.summary)
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
    }

    private func summaryLabel(_ text: String, _ ink: Color) -> some View {
        Text(text)
            .font(.paseo(.processTitle, weight: .medium))
            .foregroundStyle(ink)
            .lineLimit(1)
    }

    // MARK: Derived text

    /// One sentence of what the run did, such as "Edited 3 files and ran 2 commands".
    nonisolated static func summaryText(_ group: Turn.WorkGroup) -> String {
        var editedFiles = Set<String>()
        var readFiles = Set<String>()
        var commands = 0, searches = 0, otherTools = 0
        for row in group.rows {
            guard case .toolCall(let call) = row.item else { continue }
            switch call.detail {
            case .edit(let path, _, _, _), .write(let path, _): editedFiles.insert(path)
            case .read(let path, _): readFiles.insert(path)
            case .shell: commands += 1
            case .search: searches += 1
            default: otherTools += 1
            }
        }
        var parts: [String] = []
        if !editedFiles.isEmpty {
            parts.append("edited \(editedFiles.count) file\(editedFiles.count == 1 ? "" : "s")")
        }
        if commands > 0 { parts.append("ran \(commands) command\(commands == 1 ? "" : "s")") }
        if !readFiles.isEmpty {
            parts.append("read \(readFiles.count) file\(readFiles.count == 1 ? "" : "s")")
        }
        if searches > 0 { parts.append("searched \(searches) time\(searches == 1 ? "" : "s")") }
        if otherTools > 0 {
            parts.append("used \(otherTools) other tool\(otherTools == 1 ? "" : "s")")
        }
        if parts.isEmpty { return "Thought" }
        let joined: String
        switch parts.count {
        case 1: joined = parts[0]
        case 2: joined = parts.joined(separator: " and ")
        default: joined = parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
        guard let first = joined.first else { return "Thought" }
        return String(first).uppercased() + joined.dropFirst()
    }

    /// The summary line's glyph: the run's content decides it.
    nonisolated static func seatGlyph(_ group: Turn.WorkGroup) -> ClaudeGlyph.Kind {
        var hasShell = false
        var hasFile = false
        for row in group.rows {
            guard case .toolCall(let call) = row.item else { continue }
            switch call.detail {
            case .read, .edit, .write, .search, .fetch: hasFile = true
            default: hasShell = true
            }
        }
        if hasShell { return .api }
        if hasFile { return .browse }
        return .think
    }
}

/// What the timeline reads off its run.
struct WorkTimelineDerived {
    var steps: [WorkRow] = []
    var summary = ""
    var seat: ClaudeGlyph.Kind = .think
    /// A thought's length by row id, from its own timestamp to the next step's.
    var durations: [String: TimeInterval] = [:]
}

/// The run's steps and what is read off them, recomputed only when the run changes. A thought's
/// length is parsed once per thought.
final class WorkTimelineCache {
    private var group: Turn.WorkGroup?
    private var value = WorkTimelineDerived()
    private var knownDurations: [String: TimeInterval] = [:]

    @MainActor func derived(for group: Turn.WorkGroup) -> WorkTimelineDerived {
        if let cached = self.group, cached == group { return value }
        self.group = group
        var derived = WorkTimelineDerived()
        derived.steps = WorkRow.merging(group.rows)
        derived.summary = ClaudeWorkTimeline.summaryText(group)
        derived.seat = ClaudeWorkTimeline.seatGlyph(group)
        let rows = group.rows
        for index in rows.indices where index + 1 < rows.count {
            guard case .reasoning = rows[index].item else { continue }
            let id = rows[index].id
            if let known = knownDurations[id] {
                derived.durations[id] = known
                continue
            }
            guard let start = PaseoDate.parse(rows[index].timestamp),
                let end = PaseoDate.parse(rows[index + 1].timestamp)
            else { continue }
            let seconds = max(0, end.timeIntervalSince(start))
            knownDurations[id] = seconds
            derived.durations[id] = seconds
        }
        value = derived
        return derived
    }
}

// MARK: - Geometry

enum WorkTimelineMetrics {
    /// The rail's column: the nodes sit in it, the step's content starts after it.
    static let gutter: CGFloat = 28
    static let nodeSize: CGFloat = 18
    /// A step's first line: the node is centred on it.
    static let headerHeight: CGFloat = 32
    /// Air between the rail and a node.
    static let railGap: CGFloat = 3
}

/// Whether the rail runs into a step from above and on from it below.
struct WorkRailPosition: Equatable, Sendable {
    var above: Bool
    var below: Bool
}

/// The rail through one step: from the step's top to just above its node, and from just below the
/// node to the step's bottom (through whatever the step opened). Every step draws its own piece, so
/// no step needs to know where another one is.
struct WorkRail: View {
    let position: WorkRailPosition

    var body: some View {
        let center = WorkTimelineMetrics.headerHeight / 2
        let radius = WorkTimelineMetrics.nodeSize / 2 + WorkTimelineMetrics.railGap
        VStack(spacing: 0) {
            Rectangle()
                .fill(position.above ? Palette.divider : .clear)
                .frame(width: 1, height: max(center - radius, 0))
            Color.clear.frame(width: 1, height: radius * 2)
            Rectangle()
                .fill(position.below ? Palette.divider : .clear)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(width: WorkTimelineMetrics.nodeSize)
        .accessibilityHidden(true)
    }
}

/// What a step's node shows.
enum WorkNodeKind: Equatable, Sendable {
    case thought
    case shell
    case symbol(String)
    case more
}

/// A step's node: the thought's own glyph bare on the rail, a tool's symbol in a small disc, a
/// spinner while the tool runs, the failure ink when it failed.
struct WorkNode: View {
    let kind: WorkNodeKind
    var running = false
    var failed = false

    var body: some View {
        ZStack {
            switch kind {
            case .thought:
                ClaudeGlyph(kind: .think, size: 15, color: Palette.tertiaryInk)
            case .more:
                Circle().strokeBorder(Palette.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                Image(systemName: "ellipsis")
                    .font(.glyph(.small, weight: .semibold))
                    .imageScale(.small)
                    .foregroundStyle(Palette.tertiaryInk)
            case .shell:
                disc
                if running {
                    ProgressView().controlSize(.mini)
                } else {
                    ClaudeGlyph(kind: .api, size: 11, color: ink)
                }
            case .symbol(let name):
                disc
                if running {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: name)
                        .font(.glyph(.small, weight: .medium))
                        .imageScale(.small)
                        .foregroundStyle(ink)
                }
            }
        }
        .frame(width: WorkTimelineMetrics.nodeSize, height: WorkTimelineMetrics.nodeSize)
        .accessibilityHidden(true)
    }

    private var disc: some View {
        Circle().fill(failed ? Palette.failureInk.opacity(0.14) : Palette.chip)
    }

    private var ink: Color { failed ? Palette.failureInk : Palette.secondaryInk }
}

/// The frame every step shares: the node on the rail, the content beside it, the find flash behind.
struct WorkStepFrame<Content: View>: View {
    let node: WorkNode
    let rail: WorkRailPosition
    let highlighted: Bool
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: WorkTimelineMetrics.gutter - WorkTimelineMetrics.nodeSize) {
            node.frame(height: WorkTimelineMetrics.headerHeight)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2)
        .background(alignment: .topLeading) { WorkRail(position: rail) }
        .background {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Palette.warning.opacity(highlighted ? 0.18 : 0))
                .padding(.horizontal, -4)
                .animation(Motion.settle.resolved(reduceMotion: reduceMotion), value: highlighted)
        }
    }
}

// MARK: - One step

/// One step of the timeline, compared by value so an unchanged step is skipped.
struct WorkStepView: View, Equatable {
    let step: WorkRow
    let rail: WorkRailPosition
    let isLive: Bool
    let duration: TimeInterval?
    let highlighted: Bool
    let findHit: Bool
    let onOpenFile: ((String) -> Void)?

    nonisolated static func == (lhs: WorkStepView, rhs: WorkStepView) -> Bool {
        lhs.step == rhs.step && lhs.rail == rhs.rail && lhs.isLive == rhs.isLive
            && lhs.duration == rhs.duration && lhs.highlighted == rhs.highlighted
            && lhs.findHit == rhs.findHit
    }

    var body: some View {
        switch step {
        case .thought(let row):
            if case .reasoning(let reasoning) = row.item {
                WorkThoughtStep(
                    text: reasoning.text, rail: rail, isLive: isLive, duration: duration,
                    highlighted: highlighted, findHit: findHit
                )
                .rowAnchor(row.seqEnd)
            }
        case .tool(let row):
            if case .toolCall(let call) = row.item {
                WorkToolStep(
                    call: call, rail: rail, isLive: isLive, highlighted: highlighted,
                    findHit: findHit
                )
                .rowAnchor(row.seqEnd)
            }
        case .fileCall(let call):
            WorkFileStep(
                call: call, rail: rail, highlighted: highlighted, findHit: findHit,
                onOpenFile: onOpenFile ?? { _ in }
            )
            .rowAnchors(call.rowSeqEnds)
        }
    }
}

extension WorkRow {
    /// Whether this step stands for the row with `seq`.
    func covers(_ seq: Int) -> Bool {
        switch self {
        case .thought(let row), .tool(let row): row.seqStart <= seq && seq <= row.seqEnd
        case .fileCall(let call): call.rowSeqEnds.contains(seq)
        }
    }
}

// MARK: - Thinking

/// A thought. Settled: one line, "Thought for 4s" and its first words. Streaming: a live "Thinking"
/// over its newest lines, which run up and fade at the top. Opened: the whole thought, selectable.
struct WorkThoughtStep: View {
    let text: String
    let rail: WorkRailPosition
    let isLive: Bool
    let duration: TimeInterval?
    let highlighted: Bool
    let findHit: Bool

    @State private var userExpanded: Bool?
    @State private var liveSince = Date()
    @AppStorage("paseo.reasoning.alwaysExpand") private var alwaysExpand = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { userExpanded ?? (findHit || alwaysExpand) }

    private var title: String {
        if let duration, duration >= 1 { return "Thought for \(DurationText.short(duration))" }
        return "Thought"
    }

    var body: some View {
        WorkStepFrame(node: WorkNode(kind: .thought), rail: rail, highlighted: highlighted) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    Haptics.selection()
                    withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                        userExpanded = !isExpanded
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if isLive && !isExpanded {
                            liveTail
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isLive ? "Thinking" : title)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                if isExpanded {
                    WorkThoughtText(text: text)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .offset(y: -2)))
                }
            }
        }
    }

    @ViewBuilder private var lead: some View {
        if isLive {
            ClaudeSweepLabel(startedAt: liveSince, rest: Palette.tertiaryInk) { ink in
                Text("Thinking")
                    .font(.paseo(.processTitle, weight: .medium))
                    .foregroundStyle(ink)
            }
        } else if isExpanded {
            Text(title)
                .font(.paseo(.processTitle, weight: .medium))
                .foregroundStyle(Palette.tertiaryInk)
        } else {
            let label = Text(title).font(.paseo(.processTitle, weight: .medium))
            let words = Text(WorkThoughtText.excerpt(text)).font(.paseo(.processTitle))
            Text("\(label)  \(words)")
                .foregroundStyle(Palette.tertiaryInk)
                .lineLimit(1)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            lead
            Spacer(minLength: 4)
            ClaudeTurnChevron(expanded: isExpanded)
        }
        .frame(minHeight: WorkTimelineMetrics.headerHeight)
    }

    /// The newest three lines of the thought, the oldest of them fading: the text grows at the
    /// bottom and leaves at the top. Bounded, so a long thought costs what three lines cost.
    private var liveTail: some View {
        Text(WorkThoughtText.tail(text))
            .font(.paseo(.processTitle))
            .lineSpacing(4)
            .foregroundStyle(Palette.secondaryInk)
            .lineLimit(3)
            .truncationMode(.head)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.25), location: 0),
                        .init(color: .black, location: 0.5),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .padding(.bottom, 10)
            .accessibilityHidden(true)
    }
}

/// The whole thought: paragraphs in the serif, the model's own emphasis kept (its section titles
/// arrive in bold), selectable.
struct WorkThoughtText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.paragraphs(text).enumerated()), id: \.offset) { _, paragraph in
                Text(Self.styled(paragraph))
                    .font(.paseo(.processTitle))
                    .lineSpacing(5)
                    .foregroundStyle(Palette.secondaryInk)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    static func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// A paragraph's inline Markdown (the model's `**titles**`), parsed once per paragraph.
    static func styled(_ paragraph: String) -> AttributedString {
        if let cached = styledCache.value(for: paragraph) { return cached }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        let styled =
            (try? AttributedString(markdown: paragraph, options: options)) ?? AttributedString(paragraph)
        styledCache.setValue(styled, for: paragraph)
        return styled
    }

    private static let styledCache = ProseCache<String, AttributedString>(
        budget: 2 * 1024 * 1024, countLimit: 512, cost: { key, _ in key.utf8.count * 3 })

    /// The thought's first words on one line: no line breaks, no Markdown marks. Reads a bounded
    /// prefix, never the whole thought.
    static func excerpt(_ text: String) -> String {
        flattened(text.prefix(240))
    }

    /// The thought's newest words, bounded.
    static func tail(_ text: String) -> String {
        flattened(text.suffix(360))
    }

    private static func flattened(_ text: Substring) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Tool calls

/// The words a tool step says: a verb that tracks the call ("Running" → "Ran"), what it acted on.
struct WorkToolWording: Equatable {
    var verb: String
    var target: String?
    var node: WorkNodeKind

    init(_ call: ToolCall) {
        let running = call.status == .running
        func tense(_ now: String, _ done: String) -> String { running ? now : done }
        switch call.detail {
        case .shell(let command, _, _, _):
            verb = tense("Running", "Ran")
            let line = ClaudeActivity.firstLine(command)
            target = line.isEmpty ? nil : line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            node = .shell
        case .read(let path, _):
            verb = tense("Reading", "Read")
            target = ClaudeActivity.fileName(path)
            node = .symbol("doc.text")
        case .edit(let path, _, _, _):
            verb = tense("Editing", "Edited")
            target = ClaudeActivity.fileName(path)
            node = .symbol("pencil")
        case .write(let path, _):
            verb = tense("Writing", "Wrote")
            target = ClaudeActivity.fileName(path)
            node = .symbol("square.and.pencil")
        case .search(let search):
            let web = search.toolName == "web_search"
            verb = web ? tense("Searching the web", "Searched the web") : tense("Searching", "Searched")
            target = search.query
            node = .symbol(web ? "globe" : "magnifyingglass")
        case .fetch(let url, _, _):
            verb = tense("Fetching", "Fetched")
            target = URL(string: url)?.host() ?? url
            node = .symbol("network")
        default:
            let presentation = ToolCallPresentation(call)
            verb = presentation.title
            target = presentation.subtitle
            node = .symbol(presentation.symbol)
        }
        if target?.isEmpty == true { target = nil }
    }
}

/// The verb, then the target in mono, middle-truncated so both ends of a path or command show.
struct WorkToolLine: View {
    let verb: String
    let target: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(verb)
                .font(.paseo(.processTitle, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .fixedSize()
            if let target {
                Text(target)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

/// What came of a call, at the line's end: a failed exit, a failure, a stop.
struct WorkOutcome: View {
    let call: ToolCall

    private var words: (text: String, failed: Bool)? {
        var exit: Int?
        if case .shell(_, _, _, let code?) = call.detail, code.isFinite, abs(code) < 1e9 {
            exit = Int(code)
        }
        if let exit, exit != 0 { return ("Exit \(exit)", true) }
        switch call.status {
        case .failed: return ("Failed", true)
        case .canceled: return ("Stopped", false)
        default: return nil
        }
    }

    var body: some View {
        if let words {
            Text(words.text)
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(words.failed ? Palette.failureInk : Palette.tertiaryInk)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// One tool call: the line, and its output when opened. A live shell call opens on its own so its
/// output can be watched; it folds again when it lands unless the reader opened it.
struct WorkToolStep: View {
    let call: ToolCall
    let rail: WorkRailPosition
    let isLive: Bool
    let highlighted: Bool
    let findHit: Bool

    @State private var userExpanded: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var opensLive: Bool {
        guard isLive, call.status == .running else { return false }
        if case .shell = call.detail { return true }
        return false
    }

    private var isExpanded: Bool { userExpanded ?? (findHit || opensLive) }

    var body: some View {
        let wording = WorkToolWording(call)
        WorkStepFrame(
            node: WorkNode(
                kind: wording.node, running: call.status == .running,
                failed: call.status == .failed),
            rail: rail, highlighted: highlighted
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    Haptics.selection()
                    withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                        userExpanded = !isExpanded
                    }
                } label: {
                    HStack(spacing: 8) {
                        WorkToolLine(verb: wording.verb, target: wording.target)
                        Spacer(minLength: 4)
                        WorkOutcome(call: call)
                        if let stat = WorkDiffStat.of(call) {
                            DiffStat(added: stat.added, removed: stat.removed)
                        }
                        ClaudeTurnChevron(expanded: isExpanded)
                    }
                    .frame(minHeight: WorkTimelineMetrics.headerHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    [wording.verb, wording.target].compactMap { $0 }.joined(separator: " "))
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                if isExpanded {
                    ClaudeToolCallDetail(call: call)
                        .padding(.top, 2)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .offset(y: -2)))
                }
            }
        }
    }
}

/// A run of calls on one file: "Edited ChatTurns.swift ×3 +12 −3". The file name opens the file;
/// the rest of the line opens the calls.
struct WorkFileStep: View {
    let call: ClaudeMergedFileCall
    let rail: WorkRailPosition
    let highlighted: Bool
    let findHit: Bool
    let onOpenFile: (String) -> Void

    @State private var userExpanded: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { userExpanded ?? findHit }
    private var last: ToolCall? { call.calls.last }
    private var running: Bool { last?.status == .running }
    private var failed: Bool { last?.status == .failed }

    private var verb: String {
        switch call.kind {
        case .read: running ? "Reading" : "Read"
        case .edit: running ? "Editing" : "Edited"
        case .write: running ? "Writing" : "Wrote"
        }
    }

    private var symbol: String {
        switch call.kind {
        case .read: "doc.text"
        case .edit: "pencil"
        case .write: "square.and.pencil"
        }
    }

    var body: some View {
        WorkStepFrame(
            node: WorkNode(kind: .symbol(symbol), running: running, failed: failed),
            rail: rail, highlighted: highlighted
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 7) {
                    toggle {
                        Text(verb)
                            .font(.paseo(.processTitle, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minHeight: WorkTimelineMetrics.headerHeight)
                            .contentShape(.rect)
                    }
                    Button {
                        onOpenFile(call.path)
                    } label: {
                        HStack(spacing: 5) {
                            Text(call.fileName)
                                .font(.paseo(.codeSmall))
                                .foregroundStyle(Palette.tertiaryInk)
                                .underline(true, pattern: .dot, color: Palette.captionInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if call.count > 1 {
                                Text("×\(PaseoFormat.integer(call.count))")
                                    .font(.paseo(.codeCaption))
                                    .foregroundStyle(Palette.captionInk)
                            }
                        }
                        .frame(minHeight: WorkTimelineMetrics.headerHeight)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(call.fileName)")
                    toggle {
                        HStack(spacing: 8) {
                            Spacer(minLength: 4)
                            if let last, last.status == .failed { WorkOutcome(call: last) }
                            if let stat = call.diffStat {
                                DiffStat(added: stat.added, removed: stat.removed)
                            }
                            ClaudeTurnChevron(expanded: isExpanded)
                        }
                        .frame(minHeight: WorkTimelineMetrics.headerHeight)
                        .contentShape(.rect)
                    }
                }
                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(call.calls, id: \.callId) { toolCall in
                            ClaudeToolCallDetail(call: toolCall)
                        }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .offset(y: -2)))
                }
            }
        }
    }

    private func toggle<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Button {
            Haptics.selection()
            withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                userExpanded = !isExpanded
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(verb) \(call.fileName)")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

/// One edit's `+N −M`, through the merged call's cached parse. Nil for anything but an edit.
enum WorkDiffStat {
    @MainActor static func of(_ call: ToolCall) -> (added: Int, removed: Int)? {
        guard case .edit(let path, _, _, _) = call.detail else { return nil }
        let merged = ClaudeMergedFileCall(
            kind: .edit, path: path, firstRowId: call.callId, calls: [call], rowSeqEnds: [])
        return merged.diffStat
    }
}

/// The fold over a long run's older steps: "12 earlier steps", on the rail, opening them.
struct WorkEarlierSteps: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            WorkStepFrame(
                node: WorkNode(kind: .more), rail: WorkRailPosition(above: false, below: true),
                highlighted: false
            ) {
                HStack(spacing: 6) {
                    Text("\(PaseoFormat.integer(count)) earlier steps")
                        .font(.paseo(.processTitle, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                    Image(systemName: "chevron.up")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.captionInk)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: WorkTimelineMetrics.headerHeight)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(PaseoFormat.integer(count)) earlier steps")
    }
}
#endif
