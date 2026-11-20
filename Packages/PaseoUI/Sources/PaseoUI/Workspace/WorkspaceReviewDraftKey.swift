#if canImport(UIKit)
import Foundation
import Observation
import PaseoProtocol
import UIKit

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
#endif
