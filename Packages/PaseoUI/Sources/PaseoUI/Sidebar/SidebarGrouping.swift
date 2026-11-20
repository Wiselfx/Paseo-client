#if canImport(UIKit)
import SwiftUI

/// Sidebar grouping: project buckets (default) or date buckets by last activity. Persisted per device.
enum SidebarGrouping: String, CaseIterable, Identifiable {
    case project, date

    var id: String { rawValue }
    var title: String {
        switch self {
        case .project: "Project"
        case .date: "Date"
        }
    }
}
#endif
