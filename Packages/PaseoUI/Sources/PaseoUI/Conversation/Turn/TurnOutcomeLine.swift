#if canImport(UIKit)
import SwiftUI

/// A finished turn's header: what the work did, then how long it took, as one line, e.g.
/// "Edited 2 files and ran 3 commands · 12s". It is also the turn's only fold control, so the
/// sentence that says what is folded is the thing that opens it.
///
/// Without countable work it reads "Completed in 12s"; a stopped turn says "Stopped" with its
/// time, so the header never shows a lone chevron.
struct TurnOutcomeLine: View {
    /// `TurnSummary.overviewLabel`, nil when there is nothing to count.
    let summary: String?
    let duration: TimeInterval?
    let isCanceled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isCanceled ? "stop.circle" : "clock")
                .accessibilityHidden(true)
            if let summary {
                // The summary gives way to the time when the line runs out of room.
                Text(summary)
                    .lineLimit(2)
                if let timing {
                    Text("·").accessibilityHidden(true)
                    Text(timing).lineLimit(1).layoutPriority(1)
                }
            } else {
                Text(timing ?? "Completed").lineLimit(1)
            }
        }
        .font(.paseo(.callout))
        .foregroundStyle(Palette.secondaryInk)
    }

    /// The time part: short after a summary ("12s"), a sentence on its own ("Completed in 12s").
    private var timing: String? {
        let short = duration.map(DurationText.short)
        if isCanceled { return short.map { "Stopped after \($0)" } ?? "Stopped" }
        if summary != nil { return short }
        return duration.map(DurationText.completed)
    }
}
#endif
