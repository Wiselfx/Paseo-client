#if canImport(UIKit)
import Foundation

/// The `ForEach` identity of one markdown block, list item or table row; see
/// `Array.identifiedValues(hashing:)`.
struct MarkdownStableID: Hashable {
    let open: Bool
    let value: Int
    let occurrence: Int
}
#endif
