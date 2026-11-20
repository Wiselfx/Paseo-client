#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

// MARK: - Diff line model

/// Flattens a file's hunks into renderable sections with old/new line numbers and measures the
/// content width once. Built off the main actor for large files; the result is plain values.
enum DiffModel {
    enum RowKind: Sendable {
        case hunkHeader
        case context
        case add
        case remove
    }

    /// The whitespace filter: a hunk whose changed lines all match on trimmed content carries
    /// no real change (indent moves). Mixed hunks stay.
    static func skipHunkForWhitespace(_ hunk: DiffHunk) -> Bool {
        let adds = hunk.lines.compactMap { $0.type == .add ? $0.content : nil }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let removes = hunk.lines.compactMap { $0.type == .remove ? $0.content : nil }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return !adds.isEmpty && adds.count == removes.count && adds.sorted() == removes.sorted()
    }

    struct Row: Identifiable, Sendable {
        let id: Int
        let old: String
        let new: String
        let sign: String
        let kind: RowKind
        let text: String
        /// Where a review comment would anchor; nil for hunk header rows.
        var anchor: LineAnchor? = nil
    }

    /// Builds the sections and the width once. Non-isolated: large files call it from a
    /// detached task.
    nonisolated static func render(
        file: ParsedDiffFile, hideWhitespace: Bool, unitWidth: CGFloat
    ) -> DiffRender {
        var sections: [DiffSection] = []
        var nextId = 0
        var maxLine = 0
        var longest = 0

        for (hunkIndex, hunk) in file.hunks.enumerated() {
            // Client-side whitespace filter: skip hunks whose changed lines all match on
            // trimmed content (indent moves). Mixed hunks stay.
            if hideWhitespace, skipHunkForWhitespace(hunk) {
                continue
            }
            var oldLine = hunk.oldStart
            var newLine = hunk.newStart
            var rows: [Row] = []
            var headerText = "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@"
            var skippedFirstHeader = false

            for line in hunk.lines {
                switch line.type {
                case .header:
                    // The first embedded header is the pinned section header; anything after it
                    // stays as a row so no diff text is lost.
                    if !skippedFirstHeader {
                        headerText = line.content
                        skippedFirstHeader = true
                    } else {
                        rows.append(
                            Row(
                                id: nextId, old: "", new: "", sign: "", kind: .hunkHeader,
                                text: line.content))
                        nextId += 1
                    }
                case .context, .unknown:
                    rows.append(
                        Row(
                            id: nextId, old: "\(oldLine)", new: "\(newLine)", sign: " ",
                            kind: .context, text: line.content,
                            anchor: LineAnchor(side: .new, line: newLine)))
                    nextId += 1
                    maxLine = max(maxLine, oldLine, newLine)
                    longest = max(longest, line.content.count)
                    oldLine += 1
                    newLine += 1
                case .add:
                    rows.append(
                        Row(
                            id: nextId, old: "", new: "\(newLine)", sign: "+",
                            kind: .add, text: line.content,
                            anchor: LineAnchor(side: .new, line: newLine)))
                    nextId += 1
                    maxLine = max(maxLine, newLine)
                    longest = max(longest, line.content.count)
                    newLine += 1
                case .remove:
                    rows.append(
                        Row(
                            id: nextId, old: "\(oldLine)", new: "", sign: "-",
                            kind: .remove, text: line.content,
                            anchor: LineAnchor(side: .old, line: oldLine)))
                    nextId += 1
                    maxLine = max(maxLine, oldLine)
                    longest = max(longest, line.content.count)
                    oldLine += 1
                }
            }
            sections.append(DiffSection(hunk: hunkIndex, header: headerText, rows: rows))
        }

        let digits = max(2, String(max(maxLine, 1)).count)
        let gutter = CGFloat(digits) * 8 + 4
        let gutters: CGFloat = gutter * 2 + 10 + 13 + Space.lg * 2
        let totalWidth = max(280, gutters + unitWidth * CGFloat(longest))
        return DiffRender(sections: sections, totalWidth: totalWidth, gutterWidth: gutter)
    }
}
#endif
