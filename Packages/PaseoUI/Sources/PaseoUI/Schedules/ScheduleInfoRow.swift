#if canImport(UIKit)
import SwiftUI

/// A read-only detail row: a title, an optional second line and the value on the trailing side.
struct ScheduleInfoRow: View {
    let title: String
    let value: String
    var detail: String?

    init(_ title: String, value: String, detail: String? = nil) {
        self.title = title
        self.value = value
        self.detail = detail
    }

    var body: some View {
        ListRow(title: title, subtitle: detail, accessory: ListRow.Accessory.value(value))
            .panelRow()
    }
}
#endif
