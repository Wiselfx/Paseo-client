#if canImport(UIKit)
import SwiftUI

/// Words with the running band swept across them: the label is drawn once in its resting ink, and
/// only the masked copy above it follows the band's clock. `label` draws the glyphs in the ink it is
/// given, so both copies set the same.
struct ClaudeSweepLabel<Label: View>: View {
    var startedAt: Date
    var rest: Color
    var band: Color = Palette.ink
    @ViewBuilder var label: (Color) -> Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSurfaceObscured) private var isSurfaceObscured
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        label(rest).overlay(alignment: .leading) {
            if !reduceMotion {
                TimelineView(
                    ClaudeSweepSchedule(
                        start: startedAt, paused: isSurfaceObscured || scenePhase == .background)
                ) { context in
                    // A hair past the entry, so a step boundary never rounds back into the last step.
                    if let phase = ClaudeSweep.phase(
                        startedAt: startedAt, at: context.date.addingTimeInterval(0.001))
                    {
                        label(band).mask { ClaudeSweep.windowGradient(phase: phase) }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
#endif
