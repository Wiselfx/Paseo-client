#if canImport(UIKit)
import SwiftUI

/// What the project page shows when `paseo.json` could not be read at all.
struct ProjectLoadFailure: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Space.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.glyph(.xlarge, weight: .light))
                .foregroundStyle(Palette.warning)
            Text("Couldn't read paseo.json")
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .buttonStyle(.paseoPrimary())
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.xxxl)
    }
}
#endif
