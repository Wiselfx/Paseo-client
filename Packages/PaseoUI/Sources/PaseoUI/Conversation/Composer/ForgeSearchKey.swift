#if canImport(UIKit)
import SwiftUI

/// What `ForgeSearchPicker`'s search task is keyed by: `task(id:)` needs one `Equatable` value, and
/// a change to either the query or the kind filter must restart (and cancel) the search.
struct ForgeSearchKey: Equatable {
    let query: String
    let kind: ForgeSearchPicker.KindFilter
}
#endif
