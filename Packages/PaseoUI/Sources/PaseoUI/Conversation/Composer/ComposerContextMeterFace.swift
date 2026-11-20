#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The control's face: ring, number, hit area, wording. A value type so SwiftUI skips it when the
/// reading has not changed; `onTap` is deliberately not part of `==` (it is replaced on every
/// composer body pass, and a skipped face keeps the action it was built with).
struct ComposerContextMeterFace: View, Equatable {
    let reading: ComposerContextReading
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Compared off the main actor, like `TurnRow`'s: everything compared is a plain value, so the
    /// conformance never crosses the isolated store it was read from.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.reading == rhs.reading
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                ClaudeMeterRing(
                    percent: Double(reading.percent ?? 0),
                    size: ComposerMetrics.meterRingSize,
                    lineWidth: ComposerMetrics.meterRingLineWidth,
                    tint: tint,
                    drawsArc: reading.percent != nil)
            }
            .frame(width: ComposerMetrics.controlSize, height: ComposerMetrics.controlSize)
            .frame(width: ComposerMetrics.hitSize, height: ComposerMetrics.hitSize)
            .contentShape(.rect)
        }
        .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("composer.contextMeter")
    }

    /// Emphasis tiers, one reading each (H3 §1): quiet below 70 %, ink from 70 %, and inside the
    /// ring the stroke thickens at 90 % (`ClaudeMeterRing`). No new colours: `secondaryInk` and
    /// `ink` only.
    private var tint: Color {
        guard let percent = reading.percent, percent >= 70 else { return Palette.secondaryInk }
        return Palette.ink
    }

    /// Upstream `en.ts`, verbatim: `contextWindow.accessibility` (“Context window {{percentage}}%
    /// used”, :2197) and `contextWindow.accessibilityNoData` (:2192).
    private var accessibilityLabel: String {
        guard let percent = reading.percent else { return "Context window: No context data" }
        return "Context window \(percent)% used"
    }
}
#endif
