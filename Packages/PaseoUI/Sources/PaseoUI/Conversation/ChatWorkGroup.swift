#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

struct ClaudeWorkGroupCell: View {
    let group: Turn.WorkGroup
    let turnIsRunning: Bool
    let typography: ClaudeTypography
    var highlightedSeq: Int?
    var findTarget: Int?
    var onOpenFile: ((String) -> Void)?

    @State private var userExpanded: Bool?
    @State private var contentHeight: CGFloat = 0
    @State private var sweepStart = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.claudeProcessCap) private var processCap
    @AppStorage(ChatDisplayMode.storageKey) private var chatDisplay = ChatDisplayMode.full.rawValue

    var opensByDefault: Bool {
        turnIsRunning && group.isActive
            && ChatDisplayMode(rawValue: chatDisplay) != .collapseToolCalls
    }
    var isExpanded: Bool { userExpanded ?? opensByDefault }

    /// The find target lives in one of this group's rows: expand so it becomes visible.
    func checkFindTarget() {
        guard let seq = findTarget else { return }
        if group.rows.contains(where: { $0.seqEnd == seq }) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) { userExpanded = true }
        }
    }

    /// The leading seat's activity icon (doc 08 §1.2): the group's content decides the glyph.
    var seatGlyph: ClaudeGlyph.Kind {
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
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
                    userExpanded = !isExpanded
                }
            } label: {
                HStack(spacing: 6) {
                    ClaudeLeadingSeat(glyph: seatGlyph, expanded: isExpanded)
                    summary
                    Spacer(minLength: 4)
                }
                .frame(minHeight: 17.5) // the counted line: 14 pt × 1.25
                .contentShape(.rect)
            }
            .buttonStyle(ClaudePressButtonStyle())
            .id("group:\(group.rows.first?.seqEnd ?? 0)")
            .onAppear { checkFindTarget() }
            .onChange(of: findTarget) { _, _ in checkFindTarget() }
            .accessibilityLabel(summaryText)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                card
                    .transition(.opacity.combined(with: .offset(y: -2)))
            }
        }
    }

    /// One sentence of what the group did, such as "Edited 3 files and ran 2 commands". Keeps
    /// DSH's wording; the headline counts folds and tool kinds into verbs. Revised from raw counts.
    var summaryText: String {
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

    func summaryRuns(_ ink: Color) -> some View {
        Text(summaryText)
            .font(typography.serif(14, weight: .medium))
            .tracking(-0.14)
            .foregroundStyle(ink)
    }

    var summary: some View {
        Group {
            if turnIsRunning && group.isActive && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    summaryRuns(ClaudePalette.tertiaryInk).overlay(alignment: .leading) {
                        if let phase = ClaudeSweep.phase(startedAt: sweepStart, at: context.date) {
                            summaryRuns(ClaudePalette.shimmerInk)
                                .mask(ClaudeSweep.windowGradient(phase: phase))
                                .allowsHitTesting(false)
                        }
                    }
                }
            } else {
                summaryRuns(ClaudePalette.tertiaryInk)
            }
        }
    }

    func findHighlight(_ seqEnd: Int) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(ClaudePalette.warning.opacity(highlightedSeq == seqEnd ? 0.18 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: highlightedSeq)
    }

    var card: some View {
        ScrollView(.vertical) {
            rows
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ClaudeGroupHeightKey.self, value: proxy.size.height)
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        // Hugs its rows until they reach the host's cap, then scrolls inside the card.
        .frame(height: min(max(contentHeight, 1), processCap), alignment: .top)
        .onPreferenceChange(ClaudeGroupHeightKey.self) { height in contentHeight = height }
        // The process card is transparent — the canvas shows through.
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
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
            ClaudeStepRow(row: row, isLive: isLive, typography: typography)
                .id("row:\(row.seqEnd)")
                .background(findHighlight(row.seqEnd))
        case .tool(let row):
            ClaudeStepRow(row: row, isLive: isLive, typography: typography)
                .id("row:\(row.seqEnd)")
                .background(findHighlight(row.seqEnd))
        case .fileCall(let call):
            ClaudeMergedFileRow(
                call: call, isLive: isLive, typography: typography,
                onOpenFile: onOpenFile ?? { _ in },
                highlightedSeq: highlightedSeq, findTarget: findTarget)
                .id(call.id)
        }
    }
}


struct ClaudeGroupHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// One thought or tool call inside the process card: one line — 36 pt for thought rows,
/// 24 pt for shell/tool rows — a trailing chevron on the disclosure rows, detail below when open.

struct ClaudeStepRow: View {
    let row: TimelineRow
    /// The newest step of a running turn opens by default so you can watch it.
    let isLive: Bool
    let typography: ClaudeTypography

    @State private var userExpanded: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // File calls never reach this row: they merge into `ClaudeMergedFileRow` (see ClaudeFileCalls).
    enum RowKind { case thought, tool }

    var kind: RowKind {
        if case .reasoning = row.item { return .thought }
        return .tool
    }

    var isExpanded: Bool { userExpanded ?? isLive }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
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
                    .font(typography.serif(13, weight: .medium))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            } else {
                Text(reasoning.text.replacingOccurrences(of: "\n", with: " "))
                    .font(typography.sans(13))
                    .lineSpacing(7) // 13 / 20
                    .foregroundStyle(ClaudePalette.tertiaryInk)
                    .lineLimit(1)
            }
        case .toolCall(let call):
            let presentation = ToolCallPresentation(call)
            HStack(spacing: 6) {
                ClaudeToolSeat(call: call, symbol: presentation.symbol)
                Text(presentation.title)
                    .font(typography.serif(13, weight: .medium))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
                if let subtitle = presentation.subtitle {
                    Circle().fill(ClaudePalette.captionInk).frame(width: 2, height: 2)
                    Text(subtitle)
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
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
                        .font(typography.serif(13))
                        .lineSpacing(10) // 13 / 23
                        .foregroundStyle(ClaudePalette.tertiaryInk)
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
                ClaudeGlyph(kind: .api, size: 14, color: ClaudePalette.tertiaryInk)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
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
                ClaudeGlyph(kind: .chevronUp, size: 14, color: ClaudePalette.tertiaryInk)
            } else if pressed {
                ClaudeGlyph(kind: .chevronDown, size: 14, color: ClaudePalette.tertiaryInk)
            } else {
                ClaudeGlyph(kind: glyph, size: 14, color: ClaudePalette.tertiaryInk)
            }
        }
        .frame(width: 16, height: 16)
    }
}
#endif
