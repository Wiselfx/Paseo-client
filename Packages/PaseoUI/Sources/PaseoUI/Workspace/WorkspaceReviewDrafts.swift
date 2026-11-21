#if canImport(UIKit)
import Foundation
import Observation
import PaseoProtocol
import UIKit

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
#endif
