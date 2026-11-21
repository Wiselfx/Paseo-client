#if canImport(UIKit)
import SwiftUI

/// The editor's Cadence rows: a read-only line for a cadence that is not cron, or the preset
/// grid, the custom cron field (outlined when invalid) and the optional timezone.
struct ScheduleCadenceSection: View {
    @Binding var cron: String
    @Binding var timezone: String
    @Binding var usePreset: Int?
    /// A cadence that is `.every` or otherwise not one we can edit as cron: shown read-only.
    let readOnlyCadence: String?
    let cronIsInvalid: Bool

    var body: some View {
        if let readOnlyCadence {
            ListRow(title: readOnlyCadence, systemImage: "clock")
                .panelRow()
            Text("Interval cadences can't be edited here yet.")
                .font(.paseo(.caption))
                .foregroundStyle(Palette.secondaryInk)
                .padding(.horizontal, Space.lg)
                .panelRow(Palette.background)
        } else {
            CadencePresetGrid(usePreset: $usePreset, cron: $cron)
                .padding(Space.lg)
                .panelRow()
            TextField("Custom cron expression", text: $cron)
                .font(.paseo(.code))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, Space.lg)
                .frame(minHeight: 44)
                .panelRow()
                .overlay {
                    if cronIsInvalid, !cron.isEmpty {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(Palette.failureInk, lineWidth: 0.5)
                    }
                }
                .onChange(of: cron) { _, expression in
                    if let index = CadencePreset.all.firstIndex(where: { $0.expression == expression }) {
                        usePreset = index
                    } else {
                        usePreset = nil
                    }
                }
                .accessibilityIdentifier("schedule.cron")
            if cronIsInvalid, !cron.isEmpty {
                Text("Five fields: minute hour day-of-month month day-of-week.")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.failureInk)
                    .padding(.horizontal, Space.lg)
                    .panelRow(Palette.background)
            }
            TextField("Timezone (optional)", text: $timezone)
                .font(.paseo(.code))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, Space.lg)
                .frame(minHeight: 44)
                .panelRow()
                .accessibilityIdentifier("schedule.timezone")
        }
    }
}
#endif
