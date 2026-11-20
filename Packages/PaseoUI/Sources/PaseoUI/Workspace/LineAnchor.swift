#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

// MARK: - Line anchor

/// Where a diff line sits, for review comment anchoring. Context lines anchor on the `new` side.
struct LineAnchor: Hashable, Sendable {
    let side: WorkspaceReviewDraftComment.DiffSide
    let line: Int
}
#endif
