#if canImport(UIKit)
import Foundation
import Observation
import PaseoProtocol
import UIKit

/// Builds the `review` attachment for the comments anchored to `file`. Comments whose anchor
/// no longer exists in the parsed diff are skipped, matching upstream ("Saved comments no
/// longer match this diff" surfaces when none survive).
public enum WorkspaceReviewAttachmentBuilder {
    /// Matches `comments` (all files) against the parsed diff, returning the attachment and the
    /// drafts that made it in (for the clear-after-send step). Drafts whose anchor no longer
    /// exists in the diff are skipped — upstream shows "Saved comments no longer match this
    /// diff" when nothing survives.
    public static func buildAll(
        comments: [WorkspaceReviewDraftComment], files: [ParsedDiffFile], cwd: String,
        mode: String, baseRef: String?
    ) -> (AgentAttachment.ReviewAttachment, [WorkspaceReviewDraftComment])? {
        var out: [AgentAttachment.ReviewAttachment.Comment] = []
        var sent: [WorkspaceReviewDraftComment] = []
        var seen = Set<UUID>()
        for file in files {
            for (comment, context) in match(comments: comments, file: file) {
                out.append(
                    AgentAttachment.ReviewAttachment.Comment(
                        filePath: comment.filePath,
                        side: AgentAttachment.ReviewAttachment.Comment.Side(
                            rawValue: comment.side.rawValue),
                        lineNumber: comment.endLine,
                        body: comment.body,
                        context: context))
                if seen.insert(comment.id).inserted { sent.append(comment) }
            }
        }
        guard !out.isEmpty else { return nil }
        let wireMode = AgentAttachment.ReviewAttachment.Mode(rawValue: mode)
        let trimmedBase = baseRef?.trimmingCharacters(in: .whitespaces)
        let attachment = AgentAttachment.ReviewAttachment(
            cwd: cwd, mode: wireMode,
            baseRef: (trimmedBase?.isEmpty == false) ? trimmedBase : nil,
            comments: out)
        return (attachment, sent)
    }

    private static func match(
        comments: [WorkspaceReviewDraftComment], file: ParsedDiffFile
    ) -> [(WorkspaceReviewDraftComment, AgentAttachment.ReviewAttachment.Context)] {
        var out: [(WorkspaceReviewDraftComment, AgentAttachment.ReviewAttachment.Context)] = []
        for comment in comments where comment.filePath == file.path {
            guard let target = findTarget(comment, file: file) else { continue }
            out.append(
                (
                    comment,
                    AgentAttachment.ReviewAttachment.Context(
                        hunkHeader: target.hunkHeader,
                        targetLine: target.targetLine,
                        lines: target.lines
                    )
                ))
        }
        return out
    }

    private struct IndexedLine {
        let type: ReviewAttachmentLineType
        let content: String
        let oldLine: Int?
        let newLine: Int?
    }

    private enum ReviewAttachmentLineType {
        case add, remove, context
    }

    private static func findTarget(
        _ comment: WorkspaceReviewDraftComment, file: ParsedDiffFile
    ) -> (hunkHeader: String, targetLine: AgentAttachment.ReviewAttachment.Line, lines: [AgentAttachment.ReviewAttachment.Line])? {
        for hunk in file.hunks {
            var oldLine = hunk.oldStart
            var newLine = hunk.newStart
            var indexed: [IndexedLine] = []
            var hunkHeader: String?
            for line in hunk.lines {
                switch line.type {
                case .header:
                    hunkHeader = line.content
                case .add:
                    indexed.append(
                        IndexedLine(type: .add, content: line.content, oldLine: nil, newLine: newLine))
                    newLine += 1
                case .remove:
                    indexed.append(
                        IndexedLine(type: .remove, content: line.content, oldLine: oldLine, newLine: nil))
                    oldLine += 1
                case .context, .unknown:
                    indexed.append(
                        IndexedLine(
                            type: .context, content: line.content, oldLine: oldLine, newLine: newLine))
                    oldLine += 1
                    newLine += 1
                }
            }
            let matchIndex = indexed.firstIndex { line in
                switch comment.side {
                case .new: return line.newLine == comment.endLine
                case .old: return line.oldLine == comment.endLine
                }
            }
            guard let matchIndex else { continue }
            let start = max(0, matchIndex - reviewContextRadius)
            let end = min(indexed.count, matchIndex + reviewContextRadius + 1)
            let toLine: (IndexedLine) -> AgentAttachment.ReviewAttachment.Line = { line in
                let type: AgentAttachment.ReviewAttachment.Line.LineType
                switch line.type {
                case .add: type = .add
                case .remove: type = .remove
                case .context: type = .context
                }
                return AgentAttachment.ReviewAttachment.Line(
                    oldLineNumber: line.oldLine, newLineNumber: line.newLine, type: type,
                    content: line.content)
            }
            let targetLine = toLine(indexed[matchIndex])
            let lines = indexed[start ..< end].map(toLine)
            let header = hunkHeader ?? "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@"
            return (header, targetLine, lines)
        }
        return nil
    }
}
#endif
