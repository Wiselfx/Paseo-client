#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The detail page's header: the clock glyph, the title, the cadence in words, and the state pill
/// (or the next run while the schedule is active).
struct ScheduleHero: View {
    let summary: ScheduleSummary
    let title: String
    let state: ScheduleState?

    @Environment(\.timeZone) private var timeZone

    var body: some View {
        // Each cadence read runs the next-occurrence calendar math, so it happens once per body.
        let now = Date.now
        let cadenceWords = summary.cadence.detailWords(now: now, timeZone: timeZone)
        let rawExpression = summary.cadence.detailRawExpression(now: now, timeZone: timeZone)
        VStack(spacing: Space.sm) {
            Image(systemName: "clock")
                .font(.glyph(.large, weight: .light))
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 48, height: 48)
                .background(Palette.panel, in: .circle)
                .accessibilityHidden(true)
            Text(title)
                .font(.paseo(.title, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(cadenceWords)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
            if let rawExpression {
                Text(rawExpression)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.captionInk)
                    .multilineTextAlignment(.center)
            }
            if let state, state != .active {
                ScheduleStatePill(state: state)
            } else {
                Text(scheduleNextRun(summary.nextRunAt))
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.captionInk)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.lg)
    }
}
#endif
