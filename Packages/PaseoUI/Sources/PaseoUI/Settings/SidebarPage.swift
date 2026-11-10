#if canImport(UIKit)
import SwiftUI

/// Settings → Sidebar: which header rows the sidebar shows, and whether the usage footer shows.
/// All keys are `@AppStorage`, so the sidebar re-reads them live. These toggles only hide sidebar
/// rows: Search always lists History, Schedules and Usage (PLAN §RI 9).
struct SidebarPage: View {
    /// Shared with `Sidebar/PaseoSidebar.swift` (`navigation`). Default shown.
    @AppStorage("paseo.sidebar.showHistory") private var showHistory = true
    /// Shared with `Sidebar/PaseoSidebar.swift` (`navigation`). Default shown.
    @AppStorage("paseo.sidebar.showSchedules") private var showSchedules = true
    /// Shared with the sidebar usage footer. Hidden by default.
    @AppStorage("paseo.usage.showInSidebar") private var showUsage = false

    var body: some View {
        SettingsList {
            Section {
                ListRow(
                    title: "History",
                    subtitle: "Recent agents on this host",
                    systemImage: "clock.arrow.2.circlepath",
                    accessory: ListRow.Accessory.toggle($showHistory)
                )
                .settingsListRow()
                .accessibilityIdentifier("settings.sidebar.showHistory")
                ListRow(
                    title: "Schedules",
                    subtitle: "Recurring agent runs on this host",
                    systemImage: "clock",
                    accessory: ListRow.Accessory.toggle($showSchedules)
                )
                .settingsListRow()
                .accessibilityIdentifier("settings.sidebar.showSchedules")
            } header: {
                Text("Header")
            } footer: {
                Text("Rows that open the History and Schedules screens. Applies immediately.")
            }
            Section {
                ListRow(
                    title: "Usage",
                    subtitle:
                        "One line per account the host reports usage for, with its pinned-window meters",
                    systemImage: "chart.bar",
                    accessory: ListRow.Accessory.toggle($showUsage)
                )
                .settingsListRow()
                .accessibilityIdentifier("settings.sidebar.showUsage")
            } header: {
                Text("Footer")
            } footer: {
                Text("Hidden by default. Toggling this applies immediately.")
            }
        }
        .settingsPage("Sidebar")
    }
}
#endif
