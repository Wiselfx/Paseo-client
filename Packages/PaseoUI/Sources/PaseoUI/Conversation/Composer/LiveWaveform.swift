#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The live level, the way Voice Memos draws it: the newest level on the right, older levels
/// scrolling left, 3 pt rounded bars with a 2 pt gap, centred vertically. Silence is a calm row
/// of 3 pt dots — that alone tells the user the mic is live.
///
/// The bars fill the width they are given: the bar count comes from the measured width in
/// `layoutSubviews`, never per frame. Every bar's position comes from its own capture time, so
/// the row slides left continuously between capture pushes: a new level appears at the right
/// edge and never knocks the bars already on screen sideways.
///
/// **Why this is a `UIView` and not a `Canvas`.** The level lives in a non-observable reference
/// box (`LiveWaveformBuffer`); the bars change every frame and nothing else does. Drawing it in
/// SwiftUI meant the redraw depended on `TimelineView`'s tick invalidating a `Canvas` closure,
/// which is not a contract anyone can verify from here — and three rounds shipped on exactly
/// that hope. A `CADisplayLink` ticking a `CAShapeLayer` is the documented UIKit way to draw
/// per-frame content (D1/R-3: per-frame drawing belongs to UIKit), it cannot be paused by an
/// unrelated parent, and it writes no SwiftUI state at all: no body re-evaluation per tick.
struct LiveWaveform: View {
    let buffer: LiveWaveformBuffer
    /// The mic is live. A dead waveform stops its display link instead of redrawing 30 times a
    /// second.
    var isActive: Bool
    /// Bars to draw; nil fills the width it is given.
    var barCount: Int? = nil
    var barWidth: CGFloat = ComposerMetrics.waveformBarWidth
    var barGap: CGFloat = ComposerMetrics.waveformBarGap
    var maxBarHeight: CGFloat = ComposerMetrics.waveformHeight
    var tint: Color = Palette.ink.opacity(0.85)
    /// VoiceOver label; nil hides the meter (it is decoration when the level has no meaning).
    var accessibilityText: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WaveformMeter(
            buffer: buffer,
            isActive: isActive,
            rowBarCount: barCount,
            barWidth: barWidth,
            barGap: barGap,
            maxBarHeight: maxBarHeight,
            tint: tint,
            reduceMotion: reduceMotion,
            accessibilityText: accessibilityText
        )
        .frame(width: explicitWidth, height: maxBarHeight)
        .frame(maxWidth: explicitWidth == nil ? CGFloat.infinity : nil)
        .accessibilityHidden(accessibilityText == nil)
    }

    /// A fixed width when the caller pinned a bar count; nil means "fill the row".
    private var explicitWidth: CGFloat? {
        guard let barCount else { return nil }
        let bars = CGFloat(max(barCount, 1))
        return bars * barWidth + (bars - 1) * barGap
    }
}
#endif
