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
        // The mark rests dim and a full-strength band sweeps across it. A white highlight on the
        // mark's own near-white ink (dark mode) would be invisible, so the contrast comes from the
        // dimmed base instead (upstream's web splash does the same: the mark dips and the peak
        // returns it to full colour, `startup-splash-screen.tsx:94-116`).
        PaseoLogo(size: size)
            .opacity(reduceMotion ? 1 : Self.restingOpacity)
            .overlay {
                if !reduceMotion {
                    PaseoLogo(size: size)
                        .mask {
                            ZStack { band }.frame(width: size, height: size)
                        }
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: Self.duration).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
    }

    /// Upstream's web gradient dips to `88` (53 %) around the peak.
    private static let restingOpacity: Double = 0.5

    /// The peak: transparent, full, transparent, from out of frame on the left to out of frame on
    /// the right.
    private var band: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black, location: 0.5),
                .init(color: .black.opacity(0), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(width: Self.peakWidth, height: size)
        .offset(x: sweep ? (size + Self.peakWidth) / 2 : -(size + Self.peakWidth) / 2)
    }
}
#endif
