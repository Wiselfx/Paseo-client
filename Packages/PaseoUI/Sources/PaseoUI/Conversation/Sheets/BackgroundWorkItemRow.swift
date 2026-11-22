#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One item in the background work sheet: icon, command or label, kind and start time, and a
/// Stop button when the daemon allows stopping it. The tap is reported through `onStop`; the sheet
/// decides whether it needs confirmation.
struct BackgroundWorkItemRow: View {
    let item: BackgroundWorkItem
    let canStop: Bool
    let onStop: () -> Void

    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack(spacing: Space.md) {
            WorkIcon(kind: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.kind)
                        .font(.paseo(.codeCaption))
                    Text("·")
                    startedText
                }
                .font(.paseo(.codeCaption))
                .foregroundStyle(Palette.tertiaryInk)
            }
            Spacer(minLength: Space.sm)
            if canStop && item.canStop == true, item.stopToken != nil {
                Button("Stop", action: onStop)
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.failureInk)
                    .padding(.horizontal, Space.lg)
                    .frame(minHeight: 36)
                    .background(Palette.adaptive(light: 0.96, dark: 0.18), in: .capsule)
                    .padding(.vertical, Space.xs)
                    .contentShape(.rect)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.lg)
        // `minHeight`, not `height`: two lines of scaled text and the Stop button outgrow a
        // fixed 56 at large Dynamic Type sizes.
        .frame(minHeight: 56)
    }

    private var title: String {
        item.command ?? item.description ?? item.kind
    }

    private var icon: WorkIcon.Kind {
        switch item.kind {
        case "monitor": .symbol("waveform.path.ecg")
        default: .shell
        }
    }

    /// Under an hour the age is a live relative counter (it keeps ticking while the sheet is
    /// open); after that, the time today or the date.
    private var startedText: Text {
        guard let date = PaseoDate.parse(item.startedAt) else {
            return Text(verbatim: item.startedAt.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if Date.now.timeIntervalSince(date) < 3600 {
            return Text("started \(Text(min(date, .now), style: .relative)) ago")
        }
        if calendar.isDateInToday(date) {
            return Text("started \(PaseoFormat.time(date))")
        }
        return Text("started \(PaseoFormat.dateTime(date))")
    }
}
#endif
