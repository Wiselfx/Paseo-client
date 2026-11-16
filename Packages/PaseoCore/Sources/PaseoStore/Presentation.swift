import Foundation
import PaseoProtocol

/// How a tool call reads in a collapsed row: `Bash · ls -la`, `Read · convert.py`.
/// Display decisions live here (testable on Linux), not in views.
public struct ToolCallPresentation: Sendable, Equatable {
    public enum Status: Sendable, Equatable { case running, succeeded, failed, canceled }

    public var title: String
    public var subtitle: String?
    /// SF Symbol name.
    public var symbol: String
    public var status: Status

    public init(_ call: ToolCall) {
        status = switch call.status {
        case .running: .running
        case .completed: .succeeded
        case .failed: .failed
        case .canceled: .canceled
        case .unknown: .succeeded
        }
        switch call.detail {
        case .shell(let command, _, _, _):
            title = "Shell"; subtitle = Self.firstLine(command); symbol = "terminal"
        case .read(let path, _):
            title = "Read"; subtitle = Self.fileName(path); symbol = "doc.text"
        case .edit(let path, _, _, _):
            title = "Edit"; subtitle = Self.fileName(path); symbol = "pencil"
        case .write(let path, _):
            title = "Write"; subtitle = Self.fileName(path); symbol = "square.and.pencil"
        case .search(let search):
            title = search.toolName == "web_search" ? "Web search" : "Search"
            subtitle = search.query; symbol = search.toolName == "web_search" ? "globe" : "magnifyingglass"
        case .fetch(let url, _, _):
            title = "Fetch"; subtitle = URL(string: url)?.host() ?? url; symbol = "network"
        case .subAgent(let type, let description, _):
            title = type.map { "Agent · \($0)" } ?? "Agent"; subtitle = description; symbol = "person.2"
        case .plainText(let label, let text, _):
            title = label ?? Self.humanize(call.name); subtitle = text.map(Self.firstLine); symbol = "text.alignleft"
        case .plan:
            title = "Plan"; subtitle = nil; symbol = "list.bullet.clipboard"
        case .worktreeSetup(_, let branch, _):
            title = "Worktree setup"; subtitle = branch; symbol = "arrow.triangle.branch"
        case .unknown:
            title = Self.humanize(call.name); subtitle = nil; symbol = "wrench.and.screwdriver"
        }
        if subtitle?.isEmpty == true { subtitle = nil }
    }

    static func firstLine(_ text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? text
        return line.trimmingCharacters(in: .whitespaces)
    }

    static func fileName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// `mcp__paseo__list_agents` → `List agents`; `Bash` stays `Bash`.
    static func humanize(_ name: String) -> String {
        let last = name.components(separatedBy: "__").last ?? name
        let spaced = last.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        guard let first = spaced.first else { return name }
        return first.uppercased() + spaced.dropFirst()
    }
}

extension Turn.WorkGroup {
    /// "2 thoughts, 1 tool call".
    public var summary: String {
        var parts: [String] = []
        if thoughtCount > 0 { parts.append(thoughtCount == 1 ? "1 thought" : "\(thoughtCount) thoughts") }
        if toolCallCount > 0 { parts.append(toolCallCount == 1 ? "1 tool call" : "\(toolCallCount) tool calls") }
        return parts.joined(separator: ", ")
    }
}
