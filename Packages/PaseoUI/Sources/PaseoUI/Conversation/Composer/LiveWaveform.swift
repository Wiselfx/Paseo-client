#if canImport(UIKit)
import SwiftUI
import UIKit

/// The one mic-level mapping (D2 §4). Under `.measurement` mode AGC is off, so speech RMS sits
/// around 0.005–0.03 and a linear scale leaves every bar near the floor. The level is converted
/// to dB, clamped to the speech band and eased, so the meters actually move.
enum AudioLevel {
    static let floor: Float = -55
    static let ceiling: Float = -10

    /// `20·log10(max(rms, 1e-5))`, clamped to −55…−10 dB and mapped to 0…1.
    static func normalized(rms: Float) -> Float {
        let db = 20 * log10(Double(max(rms, 1e-5)))
        let clamped = min(max(db, Double(floor)), Double(ceiling))
        return Float((clamped - Double(floor)) / Double(ceiling - floor))
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
/// Under Reduce Motion it is one bar whose height follows the level, no scrolling.
struct LiveWaveform: View {
    let buffer: LiveWaveformBuffer
    /// The mic is live. A dead waveform pauses its timeline instead of redrawing 30 times a second.
    var isActive: Bool
    var barCount = LiveWaveformBuffer.capacity
    var barWidth: CGFloat = 3
    var barGap: CGFloat = 2
    var maxBarHeight: CGFloat = 22
    var tint: Color = Palette.ink.opacity(0.85)
    /// VoiceOver text; nil hides the meter (it is decoration when the level has no meaning).
    var accessibilityText: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var width: CGFloat {
        let count = CGFloat(max(barCount, 1))
        return count * barWidth + (count - 1) * barGap
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { _ in
            if reduceMotion { singleBar } else { bars }
        }
        .frame(width: width, height: maxBarHeight)
        .modifier(WaveformAccessibility(text: accessibilityText))
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

    private var bars: some View {
        Canvas { context, size in
            let levels = buffer.recent(barCount)
            let middle = size.height / 2
            for (index, level) in levels.enumerated() {
                let height = barHeight(level)
                let rect = CGRect(
                    x: CGFloat(index) * (barWidth + barGap), y: middle - height / 2,
                    width: barWidth, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(tint))
            }
        }
    }

    /// Reduce Motion: the same signal, no lateral movement.
    private var singleBar: some View {
        Capsule()
            .fill(tint)
            .frame(width: barWidth, height: barHeight(buffer.latest))
    }

    /// 3 pt is the floor: a silent row is a row of dots, never nothing.
    private func barHeight(_ level: Float) -> CGFloat {
        max(3, CGFloat(level) * maxBarHeight)
    }
}
#endif
