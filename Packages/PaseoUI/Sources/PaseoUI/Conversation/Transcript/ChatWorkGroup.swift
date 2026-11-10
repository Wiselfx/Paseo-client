#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

struct ClaudeWorkGroupCell: View {
    let group: Turn.WorkGroup
    let turnIsRunning: Bool
    var highlightedSeq: Int?
    var findTarget: Int?
    var onOpenFile: ((String) -> Void)?

    @State private var userExpanded: Bool?
    @State private var contentHeight: CGFloat = 0
    @State private var sweepStart = Date()
    /// The group's derived summary and seat glyph, cached per row identity (finding #15).
    @State private var derivedCache = WorkGroupDerivedCache()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.claudeProcessCap) private var processCap
    @AppStorage(ChatDisplayMode.storageKey) private var chatDisplay = ChatDisplayMode.full.rawValue

    /// The masked sweep's rate: display rate was an offscreen pass per frame (findings #11, #24).
    static let sweepTick: TimeInterval = 1.0 / 30.0

    var opensByDefault: Bool {
        turnIsRunning && group.isActive
            && ChatDisplayMode(rawValue: chatDisplay) != .collapseToolCalls
    }
    var isExpanded: Bool { userExpanded ?? opensByDefault }

    /// The find target lives in one of this group's rows: expand so it becomes visible.
    func checkFindTarget() {
        guard let seq = findTarget else { return }
        if group.rows.contains(where: { $0.seqEnd == seq }) {
            withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) { userExpanded = true }
        }
    }

    /// The leading seat's activity icon (doc 08 §1.2): the group's content decides the glyph.
    nonisolated static func computeSeatGlyph(_ group: Turn.WorkGroup) -> ClaudeGlyph.Kind {
        var hasShell = false
        var hasFile = false
        for row in group.rows {
            if case .toolCall(let call) = row.item {
                switch call.detail {
                case .read, .edit, .write, .search, .fetch:
                    hasFile = true
                default:
                    hasShell = true
                }
            }
        }
        if hasShell { return .api }
        if hasFile { return .browse }
        return .think
    }

    var body: some View {
        let derived = derivedCache.derived(for: group)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.selection()
                withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                    userExpanded = !isExpanded
                }
            } label: {
                HStack(spacing: 6) {
                    ClaudeLeadingSeat(glyph: derived.seat, expanded: isExpanded)
                    summary(derived.summary)
                    Spacer(minLength: 4)
                }
                .frame(minHeight: 17.5) // the counted line: 14 pt × 1.25
                .contentShape(.rect)
            }
            .buttonStyle(ClaudePressButtonStyle())
            .id("group:\(group.rows.first?.seqEnd ?? 0)")
            .onAppear { checkFindTarget() }
            .onChange(of: findTarget) { _, _ in checkFindTarget() }
            .accessibilityLabel(derived.summary)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                card
                    .transition(.opacity.combined(with: .offset(y: -2)))
            }
        }
    }

    /// One sentence of what the group did, such as "Edited 3 files and ran 2 commands". Keeps
    /// DSH's wording; the headline counts folds and tool kinds into verbs. Revised from raw counts.
    nonisolated static func computeSummaryText(_ group: Turn.WorkGroup) -> String {
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
        if commands > 0 {
            parts.append("ran \(commands) command\(commands == 1 ? "" : "s")")
        }
        if !readFiles.isEmpty {
            parts.append("read \(readFiles.count) file\(readFiles.count == 1 ? "" : "s")")
        }
        if searches > 0 {
            parts.append("searched \(searches) time\(searches == 1 ? "" : "s")")
        }
        if otherTools > 0 {
            parts.append("used \(otherTools) other tool\(otherTools == 1 ? "" : "s")")
        }
        if parts.isEmpty { return "Thought" }
        let joined: String
        switch parts.count {
        case 1: joined = parts[0]
        case 2: joined = parts.joined(separator: " and ")
        default:
            joined = parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
        guard let first = joined.first else { return "Thought" }
        return String(first).uppercased() + joined.dropFirst()
    }

    func summaryRuns(_ text: String, _ ink: Color) -> some View {
        Text(text)
            .font(.paseo(.processTitle, weight: .medium))
            .tracking(-0.14)
            .foregroundStyle(ink)
    }

    func summary(_ text: String) -> some View {
        Group {
            if turnIsRunning && group.isActive && !reduceMotion {
                // A capped rate, not display rate: the masked sweep is an offscreen pass
                // (findings #11, #24). The band's 48 steps don't need more than this.
                TimelineView(.animation(minimumInterval: Self.sweepTick)) { context in
                    summaryRuns(text, Palette.tertiaryInk).overlay(alignment: .leading) {
                        if let phase = ClaudeSweep.phase(startedAt: sweepStart, at: context.date) {
                            summaryRuns(text, Palette.ink)
                                .mask(ClaudeSweep.windowGradient(phase: phase))
                                .allowsHitTesting(false)
                        }
                    }
                }
            } else {
                summaryRuns(text, Palette.tertiaryInk)
            }
        }
    }

    func findHighlight(_ seqEnd: Int) -> some View {
        RoundedRectangle(cornerRadius: Radius.md)
            .fill(Palette.warning.opacity(highlightedSeq == seqEnd ? 0.18 : 0))
            .animation(Motion.settle.resolved(reduceMotion: reduceMotion), value: highlightedSeq)
    }

    var card: some View {
        ScrollView(.vertical) {
            rows
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // Measure and clamp: once the rows pass the cap the frame stops changing, so
                    // a growing group no longer re-lays-out the card every token (finding #23).
                    let clamped = min(max(height, 1), processCap)
                    guard clamped != contentHeight else { return }
                    contentHeight = clamped
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        // Hugs its rows until they reach the host's cap, then scrolls inside the card.
        .frame(height: min(max(contentHeight, 1), processCap), alignment: .top)
        // The process card is transparent — the canvas shows through.
        .clipShape(.rect(cornerRadius: Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.cardBorder, lineWidth: 1)
        }
    }

    var rows: some View {
        let merged = WorkRow.merging(group.rows)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(merged.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Color.clear.frame(height: 4) // the gap above the hairline
                    ClaudeDivider()
                }
                rowView(item, isLive: turnIsRunning && index == merged.count - 1)
            }
        }
    }

    @ViewBuilder private func rowView(_ item: WorkRow, isLive: Bool) -> some View {
        switch item {
        case .thought(let row):
            ClaudeStepRow(row: row, isLive: isLive)
                .id("row:\(row.seqEnd)")
                .background(findHighlight(row.seqEnd))
        case .tool(let row):
            ClaudeStepRow(row: row, isLive: isLive)
                .id("row:\(row.seqEnd)")
                .background(findHighlight(row.seqEnd))
        case .fileCall(let call):
            ClaudeMergedFileRow(
                call: call, isLive: isLive,
                onOpenFile: onOpenFile ?? { _ in },
                highlightedSeq: highlightedSeq, findTarget: findTarget)
                .id(call.id)
        }
    }
}

/// Memoizes the group card's derived summary and seat glyph per row identity: appending a row
/// invalidates, a reasoning row's text growing does not (finding #15).
private final class WorkGroupDerivedCache {
    private var key: [Int] = []
    private var summary = ""
    private var seat: ClaudeGlyph.Kind = .think

    func derived(for group: Turn.WorkGroup) -> (summary: String, seat: ClaudeGlyph.Kind) {
        let key = group.rows.map(\.seqEnd)
        guard key != self.key else { return (summary, seat) }
        self.key = key
        self.summary = ClaudeWorkGroupCell.computeSummaryText(group)
        self.seat = ClaudeWorkGroupCell.computeSeatGlyph(group)
        return (self.summary, self.seat)
    }
}

/// One thought or tool call inside the process card: one line — 36 pt for thought rows,
/// 24 pt for shell/tool rows — a trailing chevron on the disclosure rows, detail below when open.

struct ClaudeStepRow: View {
    let row: TimelineRow
    /// The newest step of a running turn opens by default so you can watch it.
    let isLive: Bool

    @State private var userExpanded: Bool?
    @AppStorage("paseo.reasoning.alwaysExpand") private var alwaysExpandReasoning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // File calls never reach this row: they merge into `ClaudeMergedFileRow` (see ClaudeFileCalls).
    enum RowKind { case thought, tool }

    var kind: RowKind {
        if case .reasoning = row.item { return .thought }
        return .tool
    }

    var isExpanded: Bool { userExpanded ?? (isLive || (alwaysExpandReasoning && kind == .thought)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                    userExpanded = !isExpanded
                }
            } label: {
                HStack(spacing: 6) {
                    label
                    Spacer(minLength: 4)
                    if kind != .tool {
                        ClaudeTurnChevron(expanded: isExpanded)
                    }
                }
                .frame(minHeight: kind == .tool ? 24 : 36)
                .padding(.horizontal, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded {
                detail
                    .transition(.opacity.combined(with: .offset(y: -2)))
            }
        }
    }

    @ViewBuilder private var label: some View {
        switch row.item {
        case .reasoning(let reasoning):
            if isExpanded {
                Text("Think")
                    .font(.paseo(.process, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
            } else {
                Text(reasoning.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.paseo(.footnote))
                    .lineSpacing(7) // 13 / 20
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
            }
        case .toolCall(let call):
            let presentation = ToolCallPresentation(call)
            HStack(spacing: 6) {
                ClaudeToolSeat(call: call, symbol: presentation.symbol)
                Text(presentation.title)
                    .font(.paseo(.process, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
                if let subtitle = presentation.subtitle {
                    Circle().fill(Palette.captionInk).frame(width: 2, height: 2)
                    Text(subtitle)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var detail: some View {
        switch row.item {
        case .reasoning(let reasoning):
            // The opened thought scrolls with the group and holds no scrollbar of its own.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(reasoningParagraphs(reasoning.text), id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.paseo(.process))
                        .lineSpacing(10) // 13 / 23
                        .foregroundStyle(Palette.tertiaryInk)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 4)
            .padding(.leading, 22)
            .padding(.trailing, 12)
            .padding(.bottom, 10)
        case .toolCall(let call):
            ClaudeToolCallDetail(call: call)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        default:
            EmptyView()
        }
    }

    func reasoningParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// The leading seat a shell/tool row keeps (doc 08 §1.3(d)): the tool's glyph — the `>-` prompt
/// for a shell call — inside a 16 × 16 box, swapped for a chevron on hover on DSH. Touch has no
/// hover, so the glyph is static here.

struct ClaudeToolSeat: View {
    let call: ToolCall
    let symbol: String

    var body: some View {
        Group {
            if case .shell = call.detail {
                ClaudeGlyph(kind: .api, size: 14, color: Palette.tertiaryInk)
            } else {
                Image(systemName: symbol)
                    .font(.glyph(.small))
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// The leading seat on the summary row (doc 08 §1.2): 16 × 16, the 14 × 14 activity icon at rest;
/// touch has no hover, so the chevron — up while open, down while a finger is down — shows only
/// then. There is no trailing chevron; the chevron lives in the seat.

struct ClaudeLeadingSeat: View {
    let glyph: ClaudeGlyph.Kind
    let expanded: Bool
    @Environment(\.claudeRowPressed) private var pressed

    var body: some View {
        Group {
            if expanded {
                ClaudeGlyph(kind: .chevronUp, size: 14, color: Palette.tertiaryInk)
            } else if pressed {
                ClaudeGlyph(kind: .chevronDown, size: 14, color: Palette.tertiaryInk)
            } else {
                ClaudeGlyph(kind: glyph, size: 14, color: Palette.tertiaryInk)
            }
        }
        .frame(width: 16, height: 16)
    }
}
#endif
