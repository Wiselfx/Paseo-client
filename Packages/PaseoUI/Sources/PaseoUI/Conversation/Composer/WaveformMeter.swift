#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Hosts the meter and keeps its inputs in step. Nothing here is per frame: the tick runs inside
/// the view.
struct WaveformMeter: UIViewRepresentable {
    let buffer: LiveWaveformBuffer
    let isActive: Bool
    let rowBarCount: Int?
    let barWidth: CGFloat
    let barGap: CGFloat
    let maxBarHeight: CGFloat
    let tint: Color
    let reduceMotion: Bool
    let accessibilityText: String?

    func makeUIView(context: Context) -> WaveformMeterView {
        WaveformMeterView(frame: .zero)
    }

    func updateUIView(_ view: WaveformMeterView, context: Context) {
        view.apply(
            buffer: buffer,
            isActive: isActive,
            barCount: rowBarCount,
            barWidth: barWidth,
            barGap: barGap,
            maxBarHeight: maxBarHeight,
            tint: UIColor(tint),
            reduceMotion: reduceMotion,
            accessibilityText: accessibilityText)
    }

    static func dismantleUIView(_ view: WaveformMeterView, coordinator: ()) {
        // SwiftUI dismantles on the main thread; `stop()` is main-actor isolated.
        MainActor.assumeIsolated {
            view.stop()
        }
    }
}
#endif
