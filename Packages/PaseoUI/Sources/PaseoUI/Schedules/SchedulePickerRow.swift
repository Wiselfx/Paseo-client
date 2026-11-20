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
#endif
