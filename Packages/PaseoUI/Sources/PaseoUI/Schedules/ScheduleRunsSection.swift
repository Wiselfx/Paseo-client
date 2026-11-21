#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The detail page's Recent runs rows: the runs, a loading row until the first inspect returns,
/// or "No runs yet.".
struct ScheduleRunsSection: View {
    let runs: [ScheduleRun]
    let hasInspected: Bool

    var body: some View {
        if !runs.isEmpty {
            ForEach(runs) { run in
                ScheduleRunRow(run: run)
            }
        } else if !hasInspected {
            HStack {
                InlineProgress()
                Text("Loading…")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.lg)
            .panelRow()
        } else {
            Text("No runs yet.")
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.md)
                .panelRow()
        }
    }
}
#endif
