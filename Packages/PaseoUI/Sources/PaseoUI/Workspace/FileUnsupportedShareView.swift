#if canImport(UIKit)
import SwiftUI

/// Binary, non-image files: a calm message and a share action.
struct FileUnsupportedShareView: View {
    let icon: String
    let title: String
    let detail: String
    let isSharing: Bool
    let onShare: () -> Void

    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: icon)
                .font(.glyph(.hero, weight: .light))
                .foregroundStyle(Palette.tertiaryInk)
            Text(title)
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text(detail)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
            Button(action: onShare) {
                if isSharing {
                    ProgressView().controlSize(.small)
                        .frame(height: 36)
                        .padding(.horizontal, Space.xl)
                } else {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(minHeight: 44)
                        .padding(.horizontal, Space.lg)
                        .background(Palette.chip, in: .capsule)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSharing)
            .accessibilityLabel("Share file")
        }
        .padding(.horizontal, Space.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
