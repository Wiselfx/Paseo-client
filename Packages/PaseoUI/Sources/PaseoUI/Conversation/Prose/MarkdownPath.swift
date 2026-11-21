import Foundation

extension String {
    /// The document-unique path of a child block: the parent's path plus the child's position.
    ///
    /// A block's position restarts at 0 inside every quote and list item, so the position alone
    /// cannot tell two nested tables apart. A path ("2", "2.0", "2.1.0") can: the document is
    /// the empty path, a quote's children continue its path, and a list item's children continue
    /// the item's path (the block's path plus the item's position).
    func markdownChild(_ index: Int) -> String {
        isEmpty ? "\(index)" : "\(self).\(index)"
    }
}
