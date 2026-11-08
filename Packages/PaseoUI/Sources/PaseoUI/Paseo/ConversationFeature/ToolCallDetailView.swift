import Foundation
import PaseoStore
import SwiftUI

/// The opened body of a tool call, chosen by its detail type.
struct ToolCallDetailView: View {
    let call: ToolCall

    private var status: OutputBlock.Status { ToolCallPresentation(call).status.codeBlockStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if case .failed = call.status, let error = call.error {
                Text(Self.describe(error))
                    .font(Typeset.monoSmall)
                    .foregroundStyle(Palette.failure)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch call.detail {
        case .shell(let command, let cwd, let output, _):
            OutputBlock(title: cwd.map(Self.lastPathComponent), command: command, output: output, status: status)
        case .read(let path, let content):
            OutputBlock(title: path, output: content)
        case .write(let path, let content):
            OutputBlock(title: path, output: content)
        case .edit(let path, let oldString, let newString, let unifiedDiff):
            DiffView(path: path, lines: DiffLine.parse(unifiedDiff: unifiedDiff, old: oldString, new: newString))
        case .search(let search):
            SearchResultsView(search: search)
        case .fetch(let url, let result, _):
            VStack(alignment: .leading, spacing: 8) {
                if let link = URL(string: url) {
                    Link(url, destination: link).font(Typeset.caption).lineLimit(1)
                }
                if let result, !result.isEmpty { OutputBlock(output: result) }
            }
        case .subAgent(_, let description, _):
            if let description { Text(description).font(Typeset.chrome).foregroundStyle(Palette.secondaryInk) }
        case .plainText(_, let text, _):
            if let text { Text(text).font(Typeset.chrome).foregroundStyle(Palette.secondaryInk).textSelection(.enabled) }
        case .plan(let text):
            Text(text).font(Typeset.proseSecondary).foregroundStyle(Palette.ink).textSelection(.enabled)
        case .worktreeSetup(_, _, let log):
            OutputBlock(output: log)
        case .unknown(_, let raw):
            OutputBlock(output: Self.describe(raw))
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

/// One line of a diff, classified for coloring.
struct DiffLine: Identifiable, Equatable {
    enum Kind { case added, removed, context, header }
    let id: Int
    let kind: Kind
    let text: String

    static func parse(unifiedDiff: String?, old: String?, new: String?) -> [DiffLine] {
        let raw: [String]
        if let unifiedDiff, !unifiedDiff.isEmpty {
            raw = unifiedDiff.components(separatedBy: "\n")
        } else {
            raw = (old ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }.map { "-" + $0 }
                + (new ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }.map { "+" + $0 }
        }
        return raw.enumerated().map { index, line in
            let kind: Kind =
                if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") { .header }
                else if line.hasPrefix("+") { .added }
                else if line.hasPrefix("-") { .removed }
                else { .context }
            return DiffLine(id: index, kind: kind, text: line)
        }
    }
}

struct DiffView: View {
    let path: String
    let lines: [DiffLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(path)
                .font(Typeset.mono)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider().overlay(Palette.hairline)
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(Typeset.monoSmall)
                            .foregroundStyle(line.kind == .header ? Palette.tertiaryInk : Palette.ink)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(background(for: line.kind))
                    }
                }
                .padding(.vertical, 8)
                .textSelection(.enabled)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(Palette.codeBackground, in: RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private func background(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: Palette.diffAdded
        case .removed: Palette.diffRemoved
        case .context, .header: .clear
        }
    }
}

struct SearchResultsView: View {
    let search: ToolCallDetail.Search

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let results = search.webResults, !results.isEmpty {
                ForEach(results, id: \.url) { result in
                    if let url = URL(string: result.url) {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title).font(Typeset.chromeEmphasis).foregroundStyle(Palette.ink).lineLimit(2)
                                Text(url.host() ?? result.url).font(Typeset.caption).foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    }
                }
            } else if let files = search.filePaths, !files.isEmpty {
                OutputBlock(output: files.joined(separator: "\n"))
            } else if let content = search.content, !content.isEmpty {
                OutputBlock(output: content)
            } else {
                Text("No results").font(Typeset.caption).foregroundStyle(Palette.tertiaryInk)
            }
        }
    }
}

struct TodoCard: View {
    let list: TimelineItem.TodoList

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(list.items.enumerated()), id: \.offset) { _, todo in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: symbol(for: todo))
                            .foregroundStyle(todo.completed ? Palette.success : Palette.secondaryInk)
                        Text(todo.status == "in_progress" ? (todo.activeForm ?? todo.text) : todo.text)
                            .font(Typeset.chrome)
                            .foregroundStyle(todo.completed ? Palette.secondaryInk : Palette.ink)
                            .strikethrough(todo.completed, color: Palette.tertiaryInk)
                    }
                }
            }
            .padding(14)
        }
    }

    private func symbol(for todo: TimelineItem.TodoList.Todo) -> String {
        if todo.completed { return "checkmark.circle.fill" }
        return todo.status == "in_progress" ? "circle.dotted" : "circle"
    }
}

struct NoticeRow: View {
    let item: TimelineItem

    var body: some View {
        switch item {
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Typeset.chrome).foregroundStyle(Palette.failure)
        case .notification(let level, let message):
            Label(message, systemImage: level == "warning" ? "exclamationmark.circle" : "info.circle")
                .font(Typeset.chrome).foregroundStyle(level == "error" ? Palette.failure : Palette.secondaryInk)
        case .compaction(let status):
            Label(status == "loading" ? "Compacting conversation…" : "Conversation compacted", systemImage: "rectangle.compress.vertical")
                .font(Typeset.caption).foregroundStyle(Palette.tertiaryInk)
        case .userMessage(let message):
            UserBubble(text: message.text)
        case .unknown(let type, _):
            Text("Unsupported item: \(type)").font(Typeset.caption).foregroundStyle(Palette.tertiaryInk)
        default:
            EmptyView()
        }
    }
}
