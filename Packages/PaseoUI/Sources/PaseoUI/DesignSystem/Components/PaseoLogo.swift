#if canImport(UIKit)
import SwiftUI

/// Paseo's butterfly, the app's brand mark. One 700 × 700 path, tinted with the foreground ink:
/// `PaseoLogo.imageset/butterfly.svg` is upstream's `butterfly-white.svg`, the same path as
/// `packages/app/src/components/icons/paseo-logo.tsx` and `butterfly-green.svg`
/// (Upstream: packages/app/src/components/icons/paseo-logo.tsx:14-19).
struct PaseoLogo: View {
    /// The drawn square, in points; upstream's prop is the same size.
    var size: CGFloat = 64

    var body: some View {
        Image("PaseoLogo", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Palette.ink)
            .accessibilityHidden(true)
    }
}
#endif
