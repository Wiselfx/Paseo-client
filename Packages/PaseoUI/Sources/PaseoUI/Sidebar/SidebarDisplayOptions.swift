#if canImport(UIKit)
import SwiftUI

/// Row sort: last activity (default), creation date or name. Persisted per device.
enum SidebarSort: String, CaseIterable, Identifiable {
    case activity, created, name

    var id: String { rawValue }
    var title: String {
        switch self {
        case .activity: "Last activity"
        case .created: "Created"
        case .name: "Name"
        }
    }
}

extension PaseoSidebar {
    /// The "…" menu in the sidebar header: sort, row metadata and grouping; persisted in
    /// `@AppStorage("paseo.sidebar.*")`.
    var displayOptionsMenu: some View {
        Menu {
            Picker(
                "Sort",
                selection: Binding(
                    get: { sidebarSort },
                    set: { sortRaw = $0.rawValue })
            ) {
                ForEach(SidebarSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            Divider()
            Toggle("Show branch", isOn: $showBranch)
            Toggle("Show diff stats", isOn: $showDiffStats)
            Toggle("Show PR badge", isOn: $showPRBadge)
            Toggle("Group by project", isOn: $groupByProject)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(ClaudePalette.tertiaryInk)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Sidebar options")
    }

    
}
#endif
