#if canImport(UIKit)
import SwiftUI

/// A running clock in the turn's short duration format, redrawn once a second.
struct ClaudeElapsedClock: View {
    let since: Date?
    var font: Font = .paseo(.footnote).monospacedDigit()
    var ink: Color = Palette.captionInk

    var body: some View {
        if let since {
            TimelineView(.periodic(from: since, by: 1)) { context in
                text(max(1, context.date.timeIntervalSince(since)))
            }
        } else {
            text(1)
        }
    }

    private func text(_ seconds: TimeInterval) -> some View {
        Text(DurationText.short(seconds)).font(font).foregroundStyle(ink)
    }
}
#endif
