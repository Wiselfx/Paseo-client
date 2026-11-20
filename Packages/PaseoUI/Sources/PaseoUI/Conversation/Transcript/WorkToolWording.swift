#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

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
#endif
