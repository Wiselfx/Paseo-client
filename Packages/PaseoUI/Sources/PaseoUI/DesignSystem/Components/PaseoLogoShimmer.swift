#if canImport(UIKit)
import SwiftUI

/// The splash shimmer: a 120 pt white band, transparent → white at 40 % → transparent, sweeping
/// left → right across the mark from fully out to its left to fully out to its right in 1.8 s,
/// linear and repeating (Upstream: packages/app/src/screens/startup-splash-screen.tsx:128-186,
/// `NativeLogoShimmer`; `LOGO_SIZE` 96, `SHIMMER_PEAK_WIDTH` 120, `SHIMMER_DURATION_MS` 1800).
/// Reduce Motion draws the mark alone: no band, nothing to settle.
struct PaseoLogoShimmer: View {
    /// Upstream's `LOGO_SIZE`.
    var size: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Upstream's `SHIMMER_PEAK_WIDTH`.
    private static let peakWidth: CGFloat = 120
    /// Upstream's `SHIMMER_DURATION_MS`, in seconds.
    private static let duration: Double = 1.8
    /// Upstream's web gradient dips to `88` (53 %) around the peak.
    private static let restingOpacity: Double = 0.5

    /// The band's centre travels from out of frame on the left to out of frame on the right.
    private var travel: CGFloat { (size + Self.peakWidth) / 2 }

    var body: some View {
        // The mark rests dim and a full-strength band sweeps across it. A white highlight on the
        // mark's own near-white ink (dark mode) would be invisible, so the contrast comes from the
        // dimmed base instead (upstream's web splash does the same: the mark dips and the peak
        // returns it to full colour, `startup-splash-screen.tsx:94-116`).
        //
        // The loop is a repeating keyframe animator, not `withAnimation(.repeatForever)`: a
        // repeating transaction started in `onAppear` leaks into whatever transition removes
        // the hero, and the draft → chat swap then fades the hero in and out forever.
        PaseoLogo(size: size)
            .opacity(reduceMotion ? 1 : Self.restingOpacity)
            .overlay {
                if !reduceMotion {
                    PaseoLogo(size: size)
                        .keyframeAnimator(initialValue: -travel, repeating: true) { content, x in
                            content.mask {
                                Self.band(height: size)
                                    .offset(x: x)
                                    .frame(width: size, height: size)
                            }
                        } keyframes: { _ in
                            LinearKeyframe(travel, duration: Self.duration)
                        }
                }
            }
    }

    /// The peak: transparent, full, transparent.
    private static func band(height: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black, location: 0.5),
                .init(color: .black.opacity(0), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(width: peakWidth, height: height)
    }
}
#endif
