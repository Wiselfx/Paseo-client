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

/// The splash shimmer: a 120 pt white band, transparent → white at 40 % → transparent, sweeping
/// left → right across the mark from fully out to its left to fully out to its right in 1.8 s,
/// linear and repeating (Upstream: packages/app/src/screens/startup-splash-screen.tsx:128-186,
/// `NativeLogoShimmer`; `LOGO_SIZE` 96, `SHIMMER_PEAK_WIDTH` 120, `SHIMMER_DURATION_MS` 1800).
/// Reduce Motion draws the mark alone: no band, nothing to settle.
struct PaseoLogoShimmer: View {
    /// Upstream's `LOGO_SIZE`.
    var size: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    /// Upstream's `SHIMMER_PEAK_WIDTH`.
    private static let peakWidth: CGFloat = 120
    /// Upstream's `SHIMMER_DURATION_MS`, in seconds.
    private static let duration: Double = 1.8

    var body: some View {
        PaseoLogo(size: size)
            .overlay {
                if !reduceMotion {
                    band
                }
            }
            // The band is drawn across the whole square; the mark's own alpha clips it, exactly
            // as upstream masks the peak with the logo.
            .mask {
                PaseoLogo(size: size)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: Self.duration).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
    }

    /// The sweep's peak, centred in the mark's square and offset from out-of-frame to
    /// out-of-frame on both sides.
    private var band: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.4), location: 0.5),
                .init(color: .white.opacity(0), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(width: Self.peakWidth, height: size)
        .offset(x: sweep ? (size + Self.peakWidth) / 2 : -(Self.peakWidth / 2))
        .allowsHitTesting(false)
    }
}
#endif
