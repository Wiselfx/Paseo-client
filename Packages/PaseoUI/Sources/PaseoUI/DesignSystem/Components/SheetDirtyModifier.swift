#if canImport(UIKit)
import SwiftUI

struct SheetDirtyModifier: ViewModifier {
    let isDirty: Bool

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(isDirty)
            .preference(key: SheetDirtyKey.self, value: isDirty)
    }
}
#endif
