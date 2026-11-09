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

extension PaseoSidebar {
    /// The grouping mode persisted by `paseo.sidebar.groupBy`; unknown values fall back to project.
    var sidebarGrouping: SidebarGrouping {
        SidebarGrouping(rawValue: groupByRaw) ?? .project
    }

    /// The rows inside the "Labels" submenu of the display options: "All", then one row per
    /// known label (one at a time), then a way into the manage sheet.
    @ViewBuilder var labelsFilterContent: some View {
        Button {
            Haptics.selection()
            labelFilter = ""
        } label: {
            HStack(spacing: 8) {
                Text("All")
                Spacer(minLength: 12)
                if labelFilterName == nil {
                    Image(systemName: "checkmark")
                }
            }
        }
        ForEach(labelCatalog, id: \.name) { label in
            Button {
                Haptics.selection()
                toggleLabelFilter(label.name)
            } label: {
                HStack(spacing: 8) {
                    WorkspaceLabelDot(color: label.color)
                    Text(label.name)
                    Spacer(minLength: 12)
                    if labelFilter.trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(label.name) == .orderedSame
                    {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        Divider()
        Button("Manage labels…", systemImage: "slider.horizontal.3") {
            sheet = .labelsManager
        }
    }

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
            Toggle("Show branch", isOn: $showBranch).tint(.blue)
            Toggle("Show diff stats", isOn: $showDiffStats).tint(.blue)
            Toggle("Show PR badge", isOn: $showPRBadge).tint(.blue)
            Picker(
                "Group by",
                selection: Binding(
                    get: { sidebarGrouping },
                    set: { groupByRaw = $0.rawValue })
            ) {
                ForEach(SidebarGrouping.allCases) { grouping in
                    Text(grouping.title).tag(grouping)
                }
            }
            Toggle("Active first", isOn: $activeFirst).tint(.blue)
            if session.labels.supportsLabels
                && (!labelCatalog.isEmpty || !labelFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            {
                Divider()
                Menu("Labels", systemImage: "tag") {
                    labelsFilterContent
                }
            }
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
