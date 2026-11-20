#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

// MARK: - Comment sheet target

enum CommentSheetTarget: Identifiable, Hashable {
    case new(LineAnchor)
    case edit(WorkspaceReviewDraftComment)

    var id: String {
        switch self {
        case .new(let anchor): "new:\(anchor.side.rawValue):\(anchor.line)"
        case .edit(let draft): "edit:\(draft.id.uuidString)"
        }
    }
}
#endif
