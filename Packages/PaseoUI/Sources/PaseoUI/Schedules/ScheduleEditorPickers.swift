#if canImport(UIKit)
import PaseoStore
import SwiftUI

// MARK: - Pickers

/// One row in a schedule picker: the id it writes back, the label and the optional detail line.
struct SchedulePickerRow: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String?
    let badge: String?

    var subtitle: String? { detail }
}

/// A pushed picker page: the editor's provider, model, mode and thinking lists all use it. A tap
/// writes the chosen id back through the binding and pops to the editor.
struct SchedulePickerPage: View {
    private let title: String
    private let rows: [SchedulePickerRow]
    private let selected: Binding<String>
    private let onPick: () -> Void

    init(
        title: String, rows: [SchedulePickerRow], selected: Binding<String>,
        onPick: @escaping () -> Void = {}
    ) {
        self.title = title
        self.rows = rows
        self.selected = selected
        self.onPick = onPick
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PageList {
            Section {
                if rows.isEmpty {
                    Text("This list is empty until a provider is ready.")
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(Space.lg)
                        .panelRow()
                } else {
                    ForEach(rows) { row in
                        ListRow(
                            title: row.title,
                            subtitle: row.subtitle,
                            accessory: accessory(for: row),
                            action: {
                                Haptics.selection()
                                selected.wrappedValue = row.id
                                onPick()
                                dismiss()
                            }
                        )
                        .panelRow()
                        .accessibilityAddTraits(
                            selected.wrappedValue == row.id ? .isSelected : [])
                    }
                }
            } header: {
                Text(title)
            }
        }
        .inlinePageTitle(title)
    }

    private func accessory(for row: SchedulePickerRow) -> ListRow.Accessory {
        if selected.wrappedValue == row.id { return ListRow.Accessory.checkmark(true) }
        if let badge = row.badge { return ListRow.Accessory.badge(badge) }
        return ListRow.Accessory.none
    }
}
#endif
