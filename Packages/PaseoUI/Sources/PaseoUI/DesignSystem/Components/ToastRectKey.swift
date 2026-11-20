#if canImport(UIKit)
import SwiftUI
import UIKit

struct ToastRectKey: PreferenceKey {
    static let defaultValue = CGRect.null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull { value = next }
    }
}
#endif
