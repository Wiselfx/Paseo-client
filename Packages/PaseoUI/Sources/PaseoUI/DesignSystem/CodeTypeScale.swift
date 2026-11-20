#if canImport(UIKit)
import SwiftUI
import Synchronization
import UIKit

struct CodeTypeScale: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.codeSizeStep) private var codeSizeStep

    func body(content: Content) -> some View {
        content.dynamicTypeSize(dynamicTypeSize.shifted(by: codeSizeStep))
    }
}
#endif
