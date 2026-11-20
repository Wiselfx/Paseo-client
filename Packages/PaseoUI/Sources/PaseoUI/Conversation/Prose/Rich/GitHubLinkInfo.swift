#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - RichGitHubCard (G9 C7, C13)

// NOTE: RemoteImagePipeline/G9: the most common links a coding agent prints. A
// `github.com` URL parses to owner/repo/kind; the card then resolves, in order:
// a checkout PR with the same number becomes the live PR card (bound to the
// checkout's PR status, updating live); a same-repo sibling resolves its title and
// state through forge search; anything else degrades to the plain link card.

/// What forge search found for a same-repo sibling link.
struct GitHubLinkInfo: Sendable, Equatable {
    var title: String
    var state: String
    var labels: [String] = []
}
#endif
