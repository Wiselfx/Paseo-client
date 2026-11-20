#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// DSH's landing line: a 2 pt ink rule over the turn a jump just landed on, fading in and out
/// over `TranscriptView.landingDuration` (`turn-nav.css:155-194`). UX-SPEC §0.1 forbids orange as
/// state, so it is ink. Reduce Motion shows it standing for the same time, without the fade.
struct LandingLine: View {
    let startedAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Rectangle().fill(Palette.ink).frame(height: 2)
            } else {
                TimelineView(.animation) { context in
                    let (opacity, scaleX) = phase(at: context.date)
                    Rectangle()
                        .fill(Palette.ink)
                        .frame(height: 2)
                        .scaleEffect(x: CGFloat(scaleX), y: 1, anchor: .center)
                        .opacity(opacity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// `0% opacity 0 scaleX .5 → 25% opacity 1 scaleX 1 → 70% opacity 1 → 100% opacity 0`.
    func phase(at date: Date) -> (opacity: Double, scaleX: Double) {
        let t = date.timeIntervalSince(startedAt) / TranscriptView.landingDuration
        if t <= 0 { return (0, 0.5) }
        if t < 0.25 {
            let k = t / 0.25
            return (k, 0.5 + 0.5 * k)
        }
        if t < 0.7 { return (1, 1) }
        if t < 1 { return (1 - (t - 0.7) / 0.3, 1) }
        return (0, 1)
    }
}
#endif
