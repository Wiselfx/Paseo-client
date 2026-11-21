#if canImport(UIKit)
import Foundation

/// One figure in the context sheet's "Session" group. The label is the identity: the labels are
/// unique ("Used" and "Window" are mutually exclusive), so a figure arriving mid-session does not
/// recreate the rows after it.
struct ContextDetail: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}
#endif
