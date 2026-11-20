#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Geometry

enum WorkTimelineMetrics {
    /// The rail's column: the nodes sit in it, the step's content starts after it.
    static let gutter: CGFloat = 28
    static let nodeSize: CGFloat = 20
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

/// The frame every step shares: the icon on the rail, the content beside it, the find wash behind.
struct WorkStepFrame<Content: View>: View {
    let icon: WorkIcon
    let rail: WorkRailPosition
    let highlighted: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: WorkTimelineMetrics.gutter - WorkTimelineMetrics.nodeSize) {
            icon.frame(height: WorkTimelineMetrics.headerHeight)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2)
        .background(alignment: .topLeading) { WorkRail(position: rail) }
        .background { WorkFindWash(highlighted: highlighted) }
    }
}

// MARK: - One step

/// One tool step of the opened tools section, compared by value so an unchanged step is skipped.
/// Thoughts are not steps: the thought section reads them as one text.
struct WorkStepView: View, Equatable {
    let step: WorkRow
    let rail: WorkRailPosition
    let isLive: Bool
    let highlighted: Bool
    let findHit: Bool
    let onOpenFile: ((String) -> Void)?

    nonisolated static func == (lhs: WorkStepView, rhs: WorkStepView) -> Bool {
        lhs.step == rhs.step && lhs.rail == rhs.rail && lhs.isLive == rhs.isLive
            && lhs.highlighted == rhs.highlighted && lhs.findHit == rhs.findHit
    }

    var body: some View {
        switch step {
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
        case .thought:
            EmptyView()
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

    /// Every timeline row this step stands for, as find and jump anchors.
    var seqEnds: [Int] {
        switch self {
        case .thought(let row), .tool(let row): [row.seqEnd]
        case .fileCall(let call): call.rowSeqEnds
        }
    }
}

// MARK: - Thinking

/// The whole thought: paragraphs in the serif, the model's own emphasis kept (its section titles
/// arrive in bold), selectable.
struct WorkThoughtText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.paragraphs(text).enumerated(), id: \.offset) { _, paragraph in
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
}

// MARK: - Tool calls

/// The words a tool step says: a verb that tracks the call ("Running" → "Ran"), what it acted on.
struct WorkToolWording: Equatable {
    var verb: String
    var target: String?
    var icon: WorkIcon.Kind

    init(_ call: ToolCall) {
        let running = call.status == .running
        func tense(_ now: String, _ done: String) -> String { running ? now : done }
        switch call.detail {
        case .shell(let command, _, _, _):
            verb = tense("Running", "Ran")
            let line = ClaudeActivity.firstLine(command)
            target = line.isEmpty ? nil : line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            icon = .shell
        case .read(let path, _):
            verb = tense("Reading", "Read")
            target = ClaudeActivity.fileName(path)
            icon = .read
        case .edit(let path, _, _, _):
            verb = tense("Editing", "Edited")
            target = ClaudeActivity.fileName(path)
            icon = .edit
        case .write(let path, _):
            verb = tense("Writing", "Wrote")
            target = ClaudeActivity.fileName(path)
            icon = .write
        case .search(let search):
            let web = search.toolName == "web_search"
            verb = web ? tense("Searching the web", "Searched the web") : tense("Searching", "Searched")
            target = search.query
            icon = web ? .webSearch : .search
        case .fetch(let url, _, _):
            verb = tense("Fetching", "Fetched")
            target = URL(string: url)?.host() ?? url
            icon = .fetch
        default:
            let presentation = ToolCallPresentation(call)
            verb = presentation.title
            target = presentation.subtitle
            icon = .symbol(presentation.symbol)
        }
        if target?.isEmpty == true { target = nil }
    }
}

/// The verb, then the target in mono, middle-truncated so both ends of a path or command show.
struct WorkToolLine: View {
    let verb: String
    let target: String?
    var ink: Color = Palette.secondaryInk

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(verb)
                .font(.paseo(.processTitle, weight: .medium))
                .foregroundStyle(ink)
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
            icon: WorkIcon(
                kind: wording.icon, running: call.status == .running,
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

    private var icon: WorkIcon.Kind {
        switch call.kind {
        case .read: .read
        case .edit: .edit
        case .write: .write
        }
    }

    var body: some View {
        WorkStepFrame(
            icon: WorkIcon(kind: icon, running: running, failed: failed),
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
                icon: WorkIcon(kind: .more), rail: WorkRailPosition(above: false, below: true),
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
