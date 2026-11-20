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
        case .shell(let command, let cwd, let output, let exitCode):
            ClaudeCodeBlock(
                title: cwd.map(Self.lastPathComponent), command: command, output: output,
                status: status, terminal: true, exitCode: exitCode)
        case .read(let path, let content):
            ClaudeCodeBlock(title: path, output: content)
        case .write(let path, let content):
            ClaudeCodeBlock(title: path, output: content)
        case .edit(let path, let oldString, let newString, let unifiedDiff):
            ClaudeDiffView(
                path: path, unifiedDiff: unifiedDiff, old: oldString, new: newString)
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
        case .subAgent:
            ClaudeSubagentRow(call: call)
        case .plainText(_, let text, _):
            if let text {
                Text(text).font(.paseo(.callout)).foregroundStyle(Palette.secondaryInk)
                    .textSelection(.enabled)
            }
        case .plan(let text):
            Text(text).font(.paseo(.callout)).foregroundStyle(Palette.ink).textSelection(.enabled)
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
#endif
