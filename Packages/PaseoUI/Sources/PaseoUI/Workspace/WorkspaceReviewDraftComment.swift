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
#endif
