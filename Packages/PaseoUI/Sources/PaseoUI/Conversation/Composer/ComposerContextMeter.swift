#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The composer's context-window control: the ring with its number, sitting left of the mic.
///
/// It is **the only view that reads `ConversationStore.contextUsage`** (H3 §1, R-1). `ComposerView`
/// used to read it in its own body: the ring's whole conditional, and its 70 % threshold, lived
/// there, so a usage event re-decided the card's layout. Now the reading, the ring and the
/// threshold are one control wide, and the card's body never mentions the usage at all.
///
/// In a conversation the control always occupies its slot. The number inside it changes; the row
/// never reflows, because nothing in it appears or disappears at a threshold any more. While the
/// provider has not reported a window the ring is an empty track with no number — still the same
/// size, still tappable — so the first usage the daemon sends is a change *inside* the ring.
///
/// The drawing half (`ComposerContextMeterFace`) compares on `ComposerContextReading` alone, so a
/// usage event that does not change the integer percent redraws nothing.
///
/// **Reads:** `store.contextUsage`.
struct ComposerContextMeter: View {
    let store: ConversationStore
    /// Opens the context sheet. Outside the face's `==`: one composer, one stable action.
    let onTap: () -> Void

    var body: some View {
        // The one read of the live usage, and O(1): the agent snapshot's last usage figures.
        ComposerContextMeterFace(
            reading: ComposerContextReading(store.contextUsage), onTap: onTap
        )
        .equatable()
    }
}

/// One reading of the window as a plain value: what the ring draws and what it compares on.
struct ComposerContextReading: Equatable {
    /// 0…100, rounded — the number inside the ring. `nil` while the provider has reported no
    /// window, or only one of the two figures: a half-known window gets the empty track, never a
    /// fabricated percentage.
    let percent: Int?

    init(_ usage: ContextUsage?) {
        guard let usage, let percent = usage.percentUsed, usage.usedTokens != nil,
            usage.maxTokens != nil
        else {
            self.percent = nil
            return
        }
        self.percent = min(100, max(0, Int(percent.rounded())))
    }
}

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
                if let percent = reading.percent {
                    Text(PaseoFormat.integer(percent))
                        .font(.paseo(.caption2, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
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
