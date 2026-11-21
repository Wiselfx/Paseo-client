#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One run in the detail page's history: its outcome glyph, start time, error or first output
/// line, and duration. VoiceOver reads the row as one element, led by the outcome.
struct ScheduleRunRow: View {
    let run: ScheduleRun

    var body: some View {
        HStack(spacing: Space.md) {
            Group {
                switch run.status {
                case .succeeded:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.successInk)
                        .accessibilityLabel("Succeeded")
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Palette.failureInk)
                        .accessibilityLabel("Failed")
                case .running, .unknown:
                    InlineProgress()
                        .accessibilityLabel("Running")
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(scheduleTimestamp(run.startedAt))
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.ink)
                if let error = run.error, !error.isEmpty {
                    Text(error)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.failureInk)
                        .lineLimit(2)
                } else if let output = run.output, !output.isEmpty {
                    Text(
                        output.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
                            .first.map(String.init) ?? output
                    )
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
                }
            }
            Spacer(minLength: Space.xs)
            Text(scheduleDuration(run.startedAt, run.endedAt))
                .font(.paseo(.codeCaption))
                .foregroundStyle(Palette.captionInk)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .panelRow()
    }
}
#endif
