#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

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

    /// Upstream: packages/app/src/git/diff-pane.tsx:842-847 (the "Hide whitespace" option). A
    /// removed line and the added line right after it are dropped when they match once whitespace
    /// is trimmed and collapsed. One pass over the lines, O(lines).
    static func hidingWhitespaceOnly(_ lines: [ClaudeDiffLine]) -> [ClaudeDiffLine] {
        var kept: [ClaudeDiffLine] = []
        kept.reserveCapacity(lines.count)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.kind == .removed, index + 1 < lines.count, lines[index + 1].kind == .added,
                normalized(line.text) == normalized(lines[index + 1].text)
            {
                index += 2
                continue
            }
            kept.append(line)
            index += 1
        }
        return kept
    }

    /// The line's content without its sign, whitespace runs collapsed to one space.
    private static func normalized(_ text: String) -> String {
        text.dropFirst().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
#endif
