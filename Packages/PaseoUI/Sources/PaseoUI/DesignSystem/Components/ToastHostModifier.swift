#if canImport(UIKit)
import SwiftUI
import UIKit

struct ToastHostModifier: ViewModifier {
    let center: ToastCenter

    func body(content: Content) -> some View {
        content
            .environment(\.toast, center)
            .background {
                ToastWindowHost(center: center)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
    }
}
#endif
