#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// The opened body of a tool call, chosen by its detail type. Ported from the old
/// `Paseo/ConversationFeature/ToolCallDetailView.swift` and restyled to ClaudeUI's tokens.
struct ClaudeToolCallDetail: View {
    let call: ToolCall

    private let typography = ClaudeTypography()

    private var status: ToolCallPresentation.Status { ToolCallPresentation(call).status }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if status == .failed, let error = call.error {
                Text(Self.describe(error))
                    .font(typography.mono(12.5))
                    .foregroundStyle(ClaudePalette.failureInk)
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
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.orange)
                        .lineLimit(1)
                }
                if let result, !result.isEmpty { ClaudeCodeBlock(output: result) }
            }
        case .subAgent(_, let description, _):
            if let description {
                Text(description).font(typography.sans(14)).foregroundStyle(ClaudePalette.secondaryInk)
            }
        case .plainText(_, let text, _):
            if let text {
                Text(text).font(typography.sans(14)).foregroundStyle(ClaudePalette.secondaryInk)
                    .textSelection(.enabled)
            }
        case .plan(let text):
            Text(text).font(typography.serif(16)).foregroundStyle(ClaudePalette.primaryInk).textSelection(.enabled)
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

    private let typography = ClaudeTypography()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(path)
                .font(typography.mono(12.5))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            ClaudeDivider()
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(typography.mono(12.5))
                            .foregroundStyle(line.kind == .header ? ClaudePalette.tertiaryInk : ClaudePalette.primaryInk)
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
        .background(ClaudePalette.codeBackground, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
        }
    }

    private func background(for kind: ClaudeDiffLine.Kind) -> Color {
        switch kind {
        case .added: ClaudePalette.successInk.opacity(0.14)
        case .removed: ClaudePalette.failureInk.opacity(0.12)
        case .context, .header: .clear
        }
    }
}

struct ClaudeSearchResults: View {
    let search: ToolCallDetail.Search

    private let typography = ClaudeTypography()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let results = search.webResults, !results.isEmpty {
                ForEach(results, id: \.url) { result in
                    if let url = URL(string: result.url) {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(typography.sans(14, weight: .medium))
                                    .foregroundStyle(ClaudePalette.primaryInk)
                                    .lineLimit(2)
                                Text(url.host() ?? result.url)
                                    .font(typography.sans(13))
                                    .foregroundStyle(ClaudePalette.secondaryInk)
                            }
                        }
                    }
                }
            } else if let files = search.filePaths, !files.isEmpty {
                ClaudeCodeBlock(output: files.joined(separator: "\n"))
            } else if let content = search.content, !content.isEmpty {
                ClaudeCodeBlock(output: content)
            } else {
                Text("No results").font(typography.sans(13)).foregroundStyle(ClaudePalette.tertiaryInk)
            }
        }
    }
}

/// The Tasks track: "Tasks", "{{completed}}/{{total}} tasks", then the rows.
struct ClaudeTodoCard: View {
    let list: TimelineItem.TodoList

    private let typography = ClaudeTypography()

    private var completed: Int { list.items.count { $0.completed } }

    var body: some View {
        ClaudeCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Tasks").font(typography.sans(14, weight: .medium)).foregroundStyle(ClaudePalette.primaryInk)
                    Spacer(minLength: 8)
                    Text("\(completed)/\(list.items.count) tasks")
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                }
                ClaudeDivider()
                ForEach(Array(list.items.enumerated()), id: \.offset) { _, todo in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: symbol(for: todo))
                            .font(.system(size: 13))
                            .foregroundStyle(todo.completed ? ClaudePalette.successInk : ClaudePalette.secondaryInk)
                        Text(todo.status == "in_progress" ? (todo.activeForm ?? todo.text) : todo.text)
                            .font(typography.sans(14))
                            .foregroundStyle(todo.completed ? ClaudePalette.secondaryInk : ClaudePalette.primaryInk)
                            .strikethrough(todo.completed, color: ClaudePalette.tertiaryInk)
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

/// Error, notification, compaction, and the daemon's newer item types, as light chips.
struct ClaudeNoticeRow: View {
    let item: TimelineItem

    private let typography = ClaudeTypography()

    var body: some View {
        switch item {
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(typography.sans(14))
                .foregroundStyle(ClaudePalette.failureInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .notification(let level, let message):
            Label(message, systemImage: level == "warning" ? "exclamationmark.circle" : "info.circle")
                .font(typography.sans(14))
                .foregroundStyle(level == "error" ? ClaudePalette.failureInk : ClaudePalette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .compaction(let status):
            Text(status == "loading" ? "Compacting conversation…" : "Conversation compacted")
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.tertiaryInk)
                .frame(maxWidth: .infinity, alignment: .center)
        case .unknown(let type, _):
            Text("Unsupported item: \(type)")
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.tertiaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }
    }
}
#endif
