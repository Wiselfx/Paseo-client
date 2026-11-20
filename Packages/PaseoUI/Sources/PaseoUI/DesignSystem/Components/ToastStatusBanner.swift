#if canImport(UIKit)
import SwiftUI
import UIKit

/// A standing status: the same glass capsule, with a spinner while something is in progress.
struct ToastStatusBanner: View {
    let status: ToastCenter.Status

    var body: some View {
        HStack(spacing: Space.sm) {
            if status.showsProgress {
                ProgressView().controlSize(.mini)
            } else if let systemImage = status.systemImage {
                Image(systemName: systemImage).font(.glyph(.small, weight: .medium))
            }
            Text(status.message)
                .font(.paseo(.footnote, weight: .medium))
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, 10)
        .glassEffect(in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
#endif
