#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The quiet context ring: a thin monochrome arc, ink on a `tertiaryInk` track.
/// No numbers in the ring itself; the reading lives beside it (or, in the composer, inside it).
/// Reduce Motion renders the final arc without interpolating.
struct ClaudeMeterRing: View {
    /// 0…100, already clamped by the caller.
    let percent: Double
    var size: CGFloat = 16
    var lineWidth: CGFloat = 1.5
    /// The arc's ink. Monochrome either way (UX-SPEC §0.1): the composer's meter draws it in
    /// `secondaryInk` while the reading is quiet and in `ink` from 70 % (H3 §1).
    var tint: Color = Palette.ink
    /// `false` draws the track alone: the provider has not reported a window yet (H3 §1). The
    /// control keeps its slot, so nothing in the row appears or disappears.
    var drawsArc: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(percent, 0), 100) }

    /// At ≥ 90% the arc gets thicker; no colour change (UX-SPEC §4.1b).
    private var effectiveLineWidth: CGFloat { clamped >= 90 ? lineWidth + 1 : lineWidth }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.tertiaryInk.opacity(0.35), lineWidth: lineWidth)
            // Nothing at 0 %: a zero-length trim with a round cap is a dot at twelve o'clock, which
            // reads as a tick or a stray pixel instead of "empty".
            if drawsArc, clamped > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(clamped / 100))
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: effectiveLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        // A new reading is a trim change, not a new control: `Motion.feedback`, nothing sweeping.
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: clamped)
        .accessibilityHidden(true)
    }

    /// Monochrome by percent (UX-SPEC §0.1): ink at every level.
    static var meterColor: Color { Palette.ink }
}
#endif
