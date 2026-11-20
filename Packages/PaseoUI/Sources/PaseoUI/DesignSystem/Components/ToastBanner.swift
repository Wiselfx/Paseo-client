#if canImport(UIKit)
import SwiftUI
import UIKit

/// The toast itself: a glass capsule at the top, below the safe area and the 48 pt header.
struct ToastBanner: View {
    let item: ToastCenter.Item
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage).font(.glyph(.small, weight: .medium))
            }
            Text(item.message)
                .font(.paseo(.footnote, weight: .medium))
                .lineLimit(2)
            if item.undo != nil {
                Button("Undo", action: onUndo)
                    .font(.paseo(.footnote, weight: .semibold))
                    .buttonStyle(.plain)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ToastRectKey.self, value: proxy.frame(in: .global))
                        }
                    }
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, 10)
        .glassEffect(in: .capsule)
        .accessibilityElement(children: .contain)
    }
}
#endif
