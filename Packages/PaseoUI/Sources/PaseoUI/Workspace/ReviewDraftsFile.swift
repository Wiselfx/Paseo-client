#if canImport(UIKit)
import Foundation
import Observation
import PaseoProtocol
import UIKit

struct ReviewDraftsFile: Codable {
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
#endif
