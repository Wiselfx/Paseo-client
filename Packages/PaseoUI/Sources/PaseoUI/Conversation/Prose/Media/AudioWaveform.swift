#if canImport(UIKit)
import SwiftUI

/// The audio row's waveform: one bar per RMS bucket across the whole file, the played part in
/// full ink. Tap seeks (a tap never steals the transcript's vertical scroll; a drag would —
/// R-3), and VoiceOver adjusts in 10 s steps. Values and callbacks only, so the row's other
/// state never re-runs the canvas.
struct AudioWaveform: View {
    let bars: [CGFloat]
    /// Played fraction, 0...1.
    let progress: Double
    /// The spoken value, e.g. "0:12 / 1:30".
    let valueText: String
    /// A tap's horizontal position as a fraction of the width, 0...1.
    let onSeek: (Double) -> Void
    /// A VoiceOver adjustment, in seconds.
    let onScrub: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let count = max(bars.count, 1)
            let step = max(proxy.size.width / CGFloat(count), 1)
            Canvas { context, size in
                for (index, level) in bars.enumerated() {
                    let x = CGFloat(index) * step + 1
                    let height = max(2, level * size.height)
                    let y = (size.height - height) / 2
                    let playedBar = Double(index) / Double(count) <= progress
                    context.fill(
                        Path(CGRect(x: x, y: y, width: max(step - 2, 1), height: height)),
                        with: .color(playedBar ? Palette.ink : Palette.tertiaryInk))
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                guard proxy.size.width > 0 else { return }
                onSeek(Double(min(max(value.location.x / proxy.size.width, 0), 1)))
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Audio waveform")
            .accessibilityAdjustableAction { direction in
                onScrub(direction == .increment ? 10 : -10)
            }
            .accessibilityValue(valueText)
        }
        .frame(height: Metrics.audioWaveformHeight)
        .frame(maxWidth: .infinity)
    }
}
#endif
