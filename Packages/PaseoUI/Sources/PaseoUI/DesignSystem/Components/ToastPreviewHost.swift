#if canImport(UIKit)
import SwiftUI
import UIKit

struct ToastPreviewHost: View {
    @State private var center = ToastCenter()

    var body: some View {
        VStack(spacing: Space.md) {
            Button("Plain toast") { center.show("Copied") }
                .buttonStyle(.paseoPrimary())
            Button("Undo toast") {
                center.show("Agent archived", undo: {})
            }
            .buttonStyle(.paseoSecondary)
            if let item = center.current {
                Text(item.message).font(.paseo(.footnote)).foregroundStyle(Palette.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}
#endif
