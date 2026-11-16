import Foundation
import PaseoProtocol

/// What a collapsed turn did, in one sentence.
///
/// Port of upstream's `tool-calls/detail-level/overview/model.ts` (`summarizeToolCalls`) and
/// `tool-calls/detail-level/overview/label.ts` (`useOverviewSummaryLabel`), with copy from
/// `i18n/resources/en.ts:2143-2175`. Upstream counts Paseo MCP actions separately
/// (`paseoActions`, via `getPaseoToolActionLabel`); our `ToolCall` carries no input/output and
/// has no action catalog, so this summary has no `paseoActions` — Paseo actions fall into
/// `otherToolCount` whenever they appear as ordinary calls.
public struct TurnSummary: Sendable, Equatable, Hashable {
    public var thoughtCount: Int
    public var editedFileCount: Int
    public var commandCount: Int
    public var readFileCount: Int
    public var searchCount: Int
    public var otherToolCount: Int

    public init(thoughtCount: Int = 0, editedFileCount: Int = 0, commandCount: Int = 0,
                readFileCount: Int = 0, searchCount: Int = 0, otherToolCount: Int = 0) {
        self.thoughtCount = thoughtCount
        self.editedFileCount = editedFileCount
        self.commandCount = commandCount
        self.readFileCount = readFileCount
        self.searchCount = searchCount
        self.otherToolCount = otherToolCount
    }

    /// Counts the work in a turn's work groups, in row order, across all segments.
    public init(turn: Turn) {
        var editedFiles = Set<String>()
        var readFiles = Set<String>()
        var thoughts = 0
        var commands = 0
        var searches = 0
        var otherTools = 0

        for segment in turn.segments {
            guard case .work(let group) = segment else { continue }
            for row in group.rows {
                switch row.item {
                case .reasoning:
                    thoughts += 1
                case .toolCall(let call):
                    switch call.detail {
                    case .edit(let filePath, _, _, _), .write(let filePath, _):
                        editedFiles.insert(filePath)
                    case .shell:
                        commands += 1
                    case .read(let filePath, _):
                        readFiles.insert(filePath)
                    case .search:
                        searches += 1
                    default:
                        if Self.isSearchCall(call.name) {
                            searches += 1
                        } else {
                            otherTools += 1
                        }
                    }
                default:
                    continue
                }
            }
        }

        self.init(thoughtCount: thoughts, editedFileCount: editedFiles.count,
                  commandCount: commands, readFileCount: readFiles.count,
                  searchCount: searches, otherToolCount: otherTools)
    }

    /// `/(?:^|[_.:/])(?:web_search|llm_context)$/` — upstream `model.ts:23-27`.
    private static func isSearchCall(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered == "web_search" || lowered == "llm_context"
            || lowered.hasSuffix("_web_search") || lowered.hasSuffix(".web_search")
            || lowered.hasSuffix(":web_search") || lowered.hasSuffix("/web_search")
            || lowered.hasSuffix("_llm_context") || lowered.hasSuffix(".llm_context")
            || lowered.hasSuffix(":llm_context") || lowered.hasSuffix("/llm_context")
    }

    /// `t("turnSummary.details")` — the fallback when there is nothing to count.
    public static var viewTurnDetails: String { "View turn details" }

    /// One sentence of what the work did, e.g. "Edited 2 files and ran 3 commands"; "" when
    /// there is nothing to count. Reasoning-only work reads "Thought" (`toolCallGroup.thought`).
    public var overviewLabel: String {
        var parts: [String] = []
        if editedFileCount > 0 {
            parts.append("edited \(editedFileCount) file\(editedFileCount == 1 ? "" : "s")")
        }
        if commandCount > 0 {
            parts.append("ran \(commandCount) command\(commandCount == 1 ? "" : "s")")
        }
        if readFileCount > 0 {
            parts.append("read \(readFileCount) file\(readFileCount == 1 ? "" : "s")")
        }
        if searchCount > 0 {
            parts.append("searched \(searchCount) time\(searchCount == 1 ? "" : "s")")
        }
        if otherToolCount > 0 {
            parts.append("used \(otherToolCount) other tool\(otherToolCount == 1 ? "" : "s")")
        }
        if parts.isEmpty {
            return thoughtCount > 0 ? "Thought" : ""
        }
        let joined: String
        switch parts.count {
        case 1:
            joined = parts[0]
        case 2:
            joined = parts.joined(separator: " and ")
        default:
            joined = parts.dropLast().joined(separator: ", ") + ", and " + parts[parts.count - 1]
        }
        guard let first = joined.first else { return "" }
        return String(first).uppercased() + joined.dropFirst()
    }

    /// The row text, matching upstream `summary-line.tsx:18`:
    /// `useOverviewSummaryLabel(item.tools) || t("turnSummary.details")`.
    public var detailsLabel: String {
        overviewLabel.isEmpty ? Self.viewTurnDetails : overviewLabel
    }

    /// The displayed sender name. Upstream `components/user-message/index.tsx:95`:
    /// `agent?.title ?? sender.title ?? sender.id`. Kept pure so a caller holding the sender
    /// (which our timeline model does not carry yet) can format it without guessing.
    public static func senderName(agentTitle: String?, senderTitle: String?, senderID: String) -> String {
        agentTitle ?? senderTitle ?? senderID
    }

    /// `t("turnSummary.sentBy", { name })` — `Sent by {{name}}`.
    public static func sentByLabel(name: String) -> String {
        "Sent by \(name)"
    }
}
