#if canImport(UIKit)
import SwiftUI
import UIKit

/// The one mic-level mapping (D2 §4, E1 §2.2). The band depends on the recording mode, because
/// the modes do not produce the same signal:
///
/// - Dictation runs `.measurement` with AGC **off**, so speech RMS sits around 0.005–0.03.
/// - Voice mode runs `.voiceChat` with AGC **on**, so the system normalises speech; the same
///   words arrive hotter and with far less spread.
///
/// The level is converted to dB, clamped to the mode's band, normalised, and eased with
/// `pow(x, 0.7)` so ordinary speech fills 40–80 % of the height and a shout reaches the top.
enum AudioLevel {
    /// A mode's real signal range, in dBFS.
    struct Band: Sendable, Equatable {
        var floor: Float
        var ceiling: Float

        /// `.measurement` mode, AGC off (D2 §4): keep this band.
        static let dictation = Band(floor: -55, ceiling: -10)
        /// `.voiceChat` mode, AGC on: start at −50…−15 and check it against the `level` debug
        /// log (category `voice`) on the next device run.
        static let voiceChat = Band(floor: -50, ceiling: -15)
    }

    /// `20·log10(max(rms, 1e-5))`, clamped to the band, mapped to 0…1, then `pow(_, 0.7)`.
    static func normalized(rms: Float, band: Band) -> Float {
        let db = 20 * log10(Double(max(rms, 1e-5)))
        let clamped = min(max(db, Double(band.floor)), Double(band.ceiling))
        let linear = Float((clamped - Double(band.floor)) / Double(band.ceiling - band.floor))
        return Float(pow(Double(linear), 0.7))
    }

    /// Attack 0.6, release 0.15: bars jump to a syllable and fall away calmly.
    static func smoothed(_ previous: Float, towards target: Float) -> Float {
        let factor: Float = target >= previous ? 0.6 : 0.15
        return previous + (target - previous) * factor
    }
}

/// The last 28 levels, **newest last**. Pushed from the audio tap at up to 30 Hz and read by the
/// renderer at up to 30 Hz.
///
/// A reference type on purpose (D2 §4): the levels change on every audio buffer, and a `@State`
/// array would re-render the whole composer with each one. Nothing here invalidates SwiftUI —
/// `TimelineView` asks for the newest window when it draws.
final class LiveWaveformBuffer {
    static let capacity = 28

    private var levels = [Float](repeating: 0, count: LiveWaveformBuffer.capacity)
    /// Where the next level goes; the element before it is the newest.
    private var next = 0
    private var lastPush: TimeInterval = 0

    /// Records one 0…1 level, at most every 1/30 s.
    func push(_ level: Float, now: TimeInterval = Date().timeIntervalSince1970) {
        guard now - lastPush >= 1.0 / 30.0 else { return }
        lastPush = now
        levels[next] = min(max(level, 0), 1)
        next = (next + 1) % levels.count
    }

    /// The newest `count` levels, oldest first, so the newest draws on the right.
    func recent(_ count: Int) -> [Float] {
        let wanted = min(max(count, 0), levels.count)
        var window = [Float]()
        window.reserveCapacity(wanted)
        for offset in stride(from: wanted, to: 0, by: -1) {
            window.append(levels[(next + levels.count - offset) % levels.count])
        }
        return window
    }

    /// The level the mic heard last; silence when nothing has arrived yet.
    var latest: Float {
        levels[(next + levels.count - 1) % levels.count]
    }

    /// How far, 0…1, the newest level has aged over one 30 Hz slot. The renderer blends the
    /// newest bar from the sample before it, so a capture source that publishes slower than the
    /// display (voice mode publishes one level per input buffer) still moves between pushes.
    func slotProgress(at date: Date, slot: TimeInterval = 1.0 / 30.0) -> Float {
        guard slot > 0 else { return 1 }
        let age = date.timeIntervalSince1970 - lastPush
        return Float(min(max(age / slot, 0), 1))
    }

    /// The newest level, blended with the one before it by its age in slots: the only value
    /// that changes between pushes, so the right-hand bar never steps.
    func blendedLatest(at date: Date) -> Float {
        let last = latest
        let previous = levels[(next + levels.count - 2) % levels.count]
        return previous + (last - previous) * slotProgress(at: date)
    }

    /// A new recording starts from silence, so the old speech isn't drawn as if it just happened.
    func reset() {
        levels = [Float](repeating: 0, count: levels.count)
        next = 0
        lastPush = 0
    }
}

/// The live level, the way Voice Memos draws it (D2 §4): the newest level on the right, older
/// levels scrolling left, 3 pt rounded bars with a 2 pt gap, centred vertically. Silence is a calm
/// row of 3 pt dots — that alone tells the user the mic is live.
///
/// The bars fill the width they are given (§2.3): the bar count is derived from the measured
/// width once at layout, never per frame. One `Canvas`, no per-bar views.
///
/// Under Reduce Motion it is one bar whose height follows the level, no scrolling.
struct LiveWaveform: View {
    let buffer: LiveWaveformBuffer
    /// The mic is live. A dead waveform pauses its timeline instead of redrawing 30 times a second.
    var isActive: Bool
    /// Bars to draw; nil fills the width it is given.
    var barCount: Int? = nil
    var barWidth: CGFloat = ComposerMetrics.waveformBarWidth
    var barGap: CGFloat = ComposerMetrics.waveformBarGap
    var maxBarHeight: CGFloat = ComposerMetrics.waveformHeight
    var tint: Color = Palette.ink.opacity(0.85)
    /// VoiceOver text; nil hides the meter (it is decoration when the level has no meaning).
    var accessibilityText: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// As many bars as the layout width fits. Written once per layout change, never per tick.
    @State private var fillBarCount = LiveWaveformBuffer.capacity

    private static let tickInterval = 1.0 / 30.0

    var body: some View {
        content
            .frame(width: explicitWidth, height: maxBarHeight)
            .frame(maxWidth: explicitWidth == nil ? CGFloat.infinity : nil)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { width in
                let count = Self.barCount(for: width, barWidth: barWidth, barGap: barGap)
                if count != fillBarCount { fillBarCount = count }
            }
            .modifier(WaveformAccessibility(text: accessibilityText))
    }

    /// The window the renderer draws: an explicit count, or as many 3 + 2 pt slots as fit.
    private var resolvedBarCount: Int { barCount ?? fillBarCount }

    /// A fixed width when the caller pinned a bar count; nil means "fill the row".
    private var explicitWidth: CGFloat? {
        guard let barCount else { return nil }
        return width(for: barCount)
    }

    /// Slots that fit in `width`, computed when the width changes — never per frame.
    private static func barCount(for width: CGFloat, barWidth: CGFloat, barGap: CGFloat) -> Int {
        let step = barWidth + barGap
        guard step > 0, width > 0 else { return LiveWaveformBuffer.capacity }
        return max(1, Int((width + barGap) / step))
    }

    private func width(for count: Int) -> CGFloat {
        let bars = CGFloat(max(count, 1))
        return bars * barWidth + (bars - 1) * barGap
    }

    @ViewBuilder
    private var content: some View {
        TimelineView(.animation(minimumInterval: Self.tickInterval, paused: !isActive)) { timeline in
            if reduceMotion {
                singleBar(at: timeline.date)
            } else {
                bars(at: timeline.date, count: resolvedBarCount)
            }
        }
    }

    /// The scrolling row.
    ///
    /// `timeline.date` is read **inside** the renderer (E1 §2.1). That is what makes the
    /// drawing depend on the tick: the renderer's captured state changes on every timeline
    /// entry, so SwiftUI cannot reuse the previous raster — before this, only an unrelated
    /// composer invalidation redrew the bars. The date is not decoration: it is the age of the
    /// newest sample, which blends that bar in instead of stepping at the push rate.
    private func bars(at date: Date, count: Int) -> some View {
        Canvas { context, size in
            let levels = buffer.recent(count)
            guard !levels.isEmpty else { return }
            let newest = buffer.blendedLatest(at: date)
            let middle = size.height / 2
            for (index, level) in levels.enumerated() {
                let height = barHeight(index == levels.count - 1 ? newest : level)
                let rect = CGRect(
                    x: CGFloat(index) * (barWidth + barGap), y: middle - height / 2,
                    width: barWidth, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(tint))
            }
        }
    }

    /// Reduce Motion: the same signal, no lateral movement. Still reads the tick, so it moves
    /// like the row does.
    private func singleBar(at date: Date) -> some View {
        Capsule()
            .fill(tint)
            .frame(width: barWidth, height: barHeight(buffer.blendedLatest(at: date)))
    }

    /// 3 pt is the floor: a silent row is a row of dots, never nothing.
    private func barHeight(_ level: Float) -> CGFloat {
        max(barWidth, CGFloat(level) * maxBarHeight)
    }

    private struct WaveformAccessibility: ViewModifier {
        let text: String?

        func body(content: Content) -> some View {
            if let text {
                content.accessibilityElement().accessibilityLabel(Text(text))
            } else {
                content.accessibilityHidden(true)
            }
        }
    }
}
#endif
