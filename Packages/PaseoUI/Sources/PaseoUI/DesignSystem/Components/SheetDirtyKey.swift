#if canImport(UIKit)
import SwiftUI

/// Set by `.sheetDirty(_:)` and read by `SheetScaffold` so the close button can ask before
/// throwing edits away.
struct SheetDirtyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}
#endif
