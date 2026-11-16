#if canImport(UIKit)
import Foundation
import Observation
import PaseoProtocol
import UIKit

// M3k: draft review comments for the Changes page, per workspace × diff mode.
// Persisted to Application Support/Paseo/review-drafts.json (upstream persists drafts in
// AsyncStorage the same way); corrupted or missing files start empty rather than crash.

/// One draft anchored to a file and a line (or a line range) in a specific diff.
public struct WorkspaceReviewDraftComment: Codable, Hashable, Identifiable {
    public var id: UUID
    public var filePath: String
    /// The side the line belongs to: `old` (removed side) or `new`.
    public var side: DiffSide
    public var startLine: Int
    public var endLine: Int
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), filePath: String, side: DiffSide, startLine: Int, endLine: Int,
        body: String, createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id
        self.filePath = filePath
        self.side = side
        self.startLine = startLine
        self.endLine = endLine
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public enum DiffSide: String, Codable, Hashable, Sendable {
        case old
        case new
    }
}

/// The scope a draft belongs to: workspace, diff mode, base ref and whitespace filter —
/// the same axes upstream keys on (`buildReviewDraftKey`).
public struct WorkspaceReviewDraftKey: Hashable, Codable, Sendable {
    public var workspaceId: String
    /// `uncommitted` | `base` | `all`.
    public var mode: String
    public var baseRef: String
    public var ignoreWhitespace: Bool

    public init(workspaceId: String, mode: String, baseRef: String, ignoreWhitespace: Bool) {
        self.workspaceId = workspaceId
        self.mode = mode
        self.baseRef = baseRef.trimmingCharacters(in: .whitespaces)
        self.ignoreWhitespace = ignoreWhitespace
    }
}

private struct ReviewDraftsFile: Codable {
    var sections: [Section]

    struct Section: Codable {
        var key: WorkspaceReviewDraftKey
        var comments: [WorkspaceReviewDraftComment]
    }

    init(drafts: [WorkspaceReviewDraftKey: [WorkspaceReviewDraftComment]]) {
        sections = drafts.map { Section(key: $0.key, comments: $0.value) }
    }

    var drafts: [WorkspaceReviewDraftKey: [WorkspaceReviewDraftComment]] {
        Dictionary(sections.map { ($0.key, $0.comments) }, uniquingKeysWith: { first, _ in first })
    }
}

/// The drafts store: in memory for the current session, written through to disk on every
/// mutation. Shared process-wide (`shared`) so the Changes page and its navigation
/// destinations see the same drafts without threading a store through constructors.
@MainActor @Observable
public final class WorkspaceReviewDrafts {
    public static let shared = WorkspaceReviewDrafts()

    /// Keyed by scope; only scopes with at least one comment appear.
    public private(set) var drafts: [WorkspaceReviewDraftKey: [WorkspaceReviewDraftComment]] = [:]

    private let fileURL: URL?

    public init(fileURL: URL? = ReviewDraftsStore.defaultFileURL) {
        self.fileURL = fileURL
        self.drafts = Self.read(from: fileURL) ?? [:]
    }

    /// The comments for one scope, oldest first.
    public func comments(for key: WorkspaceReviewDraftKey) -> [WorkspaceReviewDraftComment] {
        drafts[key] ?? []
    }

    public func count(for key: WorkspaceReviewDraftKey) -> Int {
        drafts[key]?.count ?? 0
    }

    @discardableResult
    public func add(
        key: WorkspaceReviewDraftKey, filePath: String, side: WorkspaceReviewDraftComment.DiffSide,
        startLine: Int, endLine: Int, body: String
    ) -> WorkspaceReviewDraftComment {
        let comment = WorkspaceReviewDraftComment(
            filePath: filePath, side: side,
            startLine: min(startLine, endLine), endLine: max(startLine, endLine), body: body)
        var scoped = drafts[key] ?? []
        scoped.append(comment)
        drafts[key] = scoped
        persist()
        return comment
    }

    public func updateBody(key: WorkspaceReviewDraftKey, id: UUID, body: String) {
        guard var scoped = drafts[key],
            let index = scoped.firstIndex(where: { $0.id == id })
        else { return }
        scoped[index].body = body
        scoped[index].updatedAt = Date()
        drafts[key] = scoped
        persist()
    }

    public func delete(key: WorkspaceReviewDraftKey, id: UUID) {
        guard var scoped = drafts[key] else { return }
        scoped.removeAll { $0.id == id }
        drafts[key] = scoped.isEmpty ? nil : scoped
        persist()
    }

    /// Acknowledged set: removes only the versions included in the submission (id + updatedAt
    /// + body), so an edit made while the send was in flight is kept. Upstream semantic.
    public func clearSent(key: WorkspaceReviewDraftKey, comments: [WorkspaceReviewDraftComment]) {
        guard var scoped = drafts[key] else { return }
        let sent = Dictionary(uniqueKeysWithValues: comments.map { ($0.id, $0) })
        scoped.removeAll { comment in
            guard let match = sent[comment.id] else { return false }
            return match.updatedAt == comment.updatedAt && match.body == comment.body
        }
        drafts[key] = scoped.isEmpty ? nil : scoped
        persist()
    }

    // MARK: Persistence

    private func persist() {
        guard let fileURL else { return }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(ReviewDraftsFile(drafts: drafts))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence must never break the drafting flow; the drafts stay live in memory.
        }
    }

    private static func read(from fileURL: URL?) -> [WorkspaceReviewDraftKey: [WorkspaceReviewDraftComment]]? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return (try? JSONDecoder().decode(ReviewDraftsFile.self, from: data))?.drafts
    }
}

public enum ReviewDraftsStore {
    public static var defaultFileURL: URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("Paseo/review-drafts.json")
    }
}

// MARK: - Attachment building (upstream's buildReviewAttachmentSnapshot)

/// The context radius around the target line, in lines.
private let reviewContextRadius = 3

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

// Small conveniences so the raw wire enums read naturally at call sites.
private extension AgentAttachment.ReviewAttachment.Comment.Side {
    init(rawValue: String) {
        self = rawValue == "old" ? .old : .new
    }
}

private extension AgentAttachment.ReviewAttachment.Mode {
    init(rawValue: String) {
        switch rawValue {
        case "uncommitted": self = .uncommitted
        case "base": self = .base
        case "all": self = .all
        case let other: self = .unknown(other)
        }
    }
}
#endif
