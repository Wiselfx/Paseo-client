#if canImport(UIKit)
import Foundation

/// A value plus its stable `ForEach` identity and its position among its siblings.
struct MarkdownIdentifiedValue<Value>: Identifiable {
    let id: MarkdownStableID
    let index: Int
    let value: Value
}
#endif
