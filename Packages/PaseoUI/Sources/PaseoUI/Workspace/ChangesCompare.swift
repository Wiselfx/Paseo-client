#if canImport(UIKit)
/// What the Changes page diffs: the working tree, or the branch against its base.
enum ChangesCompare {
    case uncommitted
    case base

    /// The review-draft scope's mode string.
    var mode: String {
        switch self {
        case .uncommitted: "uncommitted"
        case .base: "base"
        }
    }
}
#endif
