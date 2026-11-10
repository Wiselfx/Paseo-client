#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// The opened body of a tool call, chosen by its detail type. Ported from the old
/// `Paseo/ConversationFeature/ToolCallDetailView.swift` and restyled to ClaudeUI's tokens.
struct ClaudeToolCallDetail: View {
    let call: ToolCall


    private var status: ToolCallPresentation.Status { ToolCallPresentation(call).status }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if status == .failed, let error = call.error {
                Text(Self.describe(error))
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.failureInk)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch call.detail {
        case .shell(let command, let cwd, let output, _):
            ClaudeCodeBlock(
                title: cwd.map(Self.lastPathComponent), command: command, output: output, status: status)
        case .read(let path, let content):
            ClaudeCodeBlock(title: path, output: content)
        case .write(let path, let content):
            ClaudeCodeBlock(title: path, output: content)
        case .edit(let path, let oldString, let newString, let unifiedDiff):
            ClaudeDiffView(
                path: path,
                lines: ClaudeDiffLine.parse(unifiedDiff: unifiedDiff, old: oldString, new: newString))
        case .search(let search):
            ClaudeSearchResults(search: search)
        case .fetch(let url, let result, _):
            VStack(alignment: .leading, spacing: 8) {
                if let link = URL(string: url) {
                    Link(url, destination: link)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.orange)
                        .lineLimit(1)
                }
                if let result, !result.isEmpty { ClaudeCodeBlock(output: result) }
            }
        case .subAgent(_, let description, _):
            if let description {
                Text(description).font(.paseo(.callout)).foregroundStyle(Palette.secondaryInk)
            }
        case .plainText(_, let text, _):
            if let text {
                Text(text).font(.paseo(.callout)).foregroundStyle(Palette.secondaryInk)
                    .textSelection(.enabled)
            }
        case .plan(let text):
            Text(text).font(.paseo(.title)).foregroundStyle(Palette.ink).textSelection(.enabled)
        case .worktreeSetup(_, _, let log):
            ClaudeCodeBlock(output: log)
        case .unknown(_, let raw):
            ClaudeCodeBlock(output: Self.describe(raw))
        }
    }

    static func lastPathComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    static func describe(_ value: JSONValue) -> String {
        if case .string(let string) = value { return string }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}

/// One line of a diff, classified for colouring.
struct ClaudeDiffLine: Identifiable, Equatable {
    enum Kind { case added, removed, context, header }
    let id: Int
    let kind: Kind
    let text: String

    static func parse(unifiedDiff: String?, old: String?, new: String?) -> [ClaudeDiffLine] {
        let raw: [String]
        if let unifiedDiff, !unifiedDiff.isEmpty {
            raw = unifiedDiff.components(separatedBy: "\n")
        } else {
            raw =
                (old ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }.map { "-" + $0 }
                + (new ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }.map { "+" + $0 }
        }
        return raw.enumerated().map { index, line in
            let kind: Kind =
                if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") { .header }
                else if line.hasPrefix("+") { .added }
                else if line.hasPrefix("-") { .removed }
                else { .context }
            return ClaudeDiffLine(id: index, kind: kind, text: line)
        }
    }
}

struct ClaudeDiffView: View {
    let path: String
    let lines: [ClaudeDiffLine]


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(path)
                .font(.paseo(.codeSmall))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            ClaudeDivider()
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.paseo(.codeSmall))
                            .foregroundStyle(line.kind == .header ? Palette.tertiaryInk : Palette.ink)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(background(for: line.kind))
                    }
                }
                .padding(.vertical, 6)
                .textSelection(.enabled)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(Palette.codeSurface, in: .rect(cornerRadius: Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.cardBorder, lineWidth: 1)
        }
        .codeTypeScale()
    }

    private func background(for kind: ClaudeDiffLine.Kind) -> Color {
        switch kind {
        case .added: Palette.diffAdded
        case .removed: Palette.diffRemoved
        case .context, .header: .clear
        }
    }
}

struct ClaudeSearchResults: View {
    let search: ToolCallDetail.Search


    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let results = search.webResults, !results.isEmpty {
                ForEach(results, id: \.url) { result in
                    if let url = URL(string: result.url) {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.paseo(.callout, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(2)
                                Text(url.host() ?? result.url)
                                    .font(.paseo(.footnote))
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    }
                }
            } else if let files = search.filePaths, !files.isEmpty {
                ClaudeCodeBlock(output: files.joined(separator: "\n"))
            } else if let content = search.content, !content.isEmpty {
                ClaudeCodeBlock(output: content)
            } else {
                Text("No results").font(.paseo(.footnote)).foregroundStyle(Palette.tertiaryInk)
            }
        }
    }
}

/// The Tasks track: "Tasks", "{{completed}}/{{total}} tasks", then the rows.
struct ClaudeTodoCard: View {
    let list: TimelineItem.TodoList


    private var completed: Int { list.items.count { $0.completed } }

    var body: some View {
        ClaudeCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Tasks").font(.paseo(.callout, weight: .medium)).foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Text("\(PaseoFormat.integer(completed))/\(PaseoFormat.integer(list.items.count)) tasks")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                }
                ClaudeDivider()
                ForEach(Array(list.items.enumerated()), id: \.offset) { _, todo in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: symbol(for: todo))
                            .font(.glyph(.small))
                            .foregroundStyle(todo.completed ? Palette.successInk : Palette.secondaryInk)
                        Text(todo.status == "in_progress" ? (todo.activeForm ?? todo.text) : todo.text)
                            .font(.paseo(.callout))
                            .foregroundStyle(todo.completed ? Palette.secondaryInk : Palette.ink)
                            .strikethrough(todo.completed, color: Palette.tertiaryInk)
                    }
                }
            }
            .padding(12)
        }
    }

    private func symbol(for todo: TimelineItem.TodoList.Todo) -> String {
        if todo.completed { return "checkmark.circle.fill" }
        return todo.status == "in_progress" ? "circle.dotted" : "circle"
    }
}

/// A compaction in the timeline: a hairline on each side, a spinner while it runs (a scissors
/// glyph once it is done), and the label. Upstream `message.tsx:1426-1470`; the words are
/// `message-compaction-label.ts:10-27` (`en.ts:411-417`).
struct ClaudeCompactionMarker: View {
    let status: String
    /// `auto` / `manual`; absent on old daemons and on the loading row.
    let trigger: String?
    let preTokens: Int?


    var body: some View {
        HStack(spacing: 8) {
            ClaudeDivider()
            HStack(spacing: 8) {
                if status == "loading" {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "scissors").font(.glyph(.small, weight: .regular))
                }
                Text(Self.label(status: status, trigger: trigger, preTokens: preTokens))
                    .font(.paseo(.footnote))
                    .multilineTextAlignment(.center)
                    .layoutPriority(1)
            }
            .foregroundStyle(Palette.tertiaryInk)
            ClaudeDivider()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    /// Upstream's order, exactly: loading wins, then the trigger, then the token count, then the
    /// bare "completed" line. The count is `Math.round(preTokens / 1000)` followed by "K"
    /// (`message-compaction-label.ts:21-25`); UX-SPEC §0.2 groups the digits.
    static func label(status: String, trigger: String?, preTokens: Int?) -> String {
        if status == "loading" { return "Compacting..." }
        if trigger == "auto" { return "Context automatically compacted" }
        if trigger == "manual" { return "Context manually compacted" }
        if let preTokens, preTokens != 0 {
            let thousands = Int((Double(preTokens) / 1000).rounded())
            return "Context compacted (\(PaseoFormat.integer(thousands))K tokens)"
        }
        return "Context compacted"
    }
}

/// Error, notification, compaction, and the daemon's newer item types, as light chips.
struct ClaudeNoticeRow: View {
    let item: TimelineItem


    var body: some View {
        switch item {
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.paseo(.callout))
                .foregroundStyle(Palette.failureInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .notification(let level, let message):
            Label(message, systemImage: level == "warning" ? "exclamationmark.circle" : "info.circle")
                .font(.paseo(.callout))
                .foregroundStyle(level == "error" ? Palette.failureInk : Palette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .compaction(let status, let trigger, let preTokens):
            ClaudeCompactionMarker(status: status, trigger: trigger, preTokens: preTokens)
        case .unknown(let type, _):
            Text("Unsupported item: \(type)")
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.tertiaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }
    }
}
#endif
