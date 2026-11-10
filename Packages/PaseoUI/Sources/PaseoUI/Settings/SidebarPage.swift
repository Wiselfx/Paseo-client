#if canImport(UIKit)
import SwiftUI

/// Settings → Sidebar: which header rows the sidebar shows, and whether the usage footer shows.
/// All keys are `@AppStorage`, so the sidebar re-reads them live.
struct SidebarPage: View {
    /// Shared with `Sidebar/PaseoSidebar.swift` (`navigation`). Default shown.
    @AppStorage("paseo.sidebar.showHistory") private var showHistory = true
    /// Shared with `Sidebar/PaseoSidebar.swift` (`navigation`). Default shown.
    @AppStorage("paseo.sidebar.showSchedules") private var showSchedules = true
    /// Shared with the sidebar usage footer. Hidden by default.
    @AppStorage("paseo.usage.showInSidebar") private var showUsage = false


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Header")
                RowGroup {
                    toggleRow(
                        "History",
                        subtitle: "Recent agents on this host",
                        symbol: "clock.arrow.2.circlepath",
                        isOn: $showHistory,
                        identifier: "settings.sidebar.showHistory")
                    rowDivider
                    toggleRow(
                        "Schedules",
                        subtitle: "Recurring agent runs on this host",
                        symbol: "clock",
                        isOn: $showSchedules,
                        identifier: "settings.sidebar.showSchedules")
                }
                Text("Rows that open the History and Schedules screens. Applies immediately.")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.leading, 16)
                sectionLabel("Footer")
                RowGroup {
                    toggleRow(
                        "Usage",
                        subtitle: "One line per account the host reports usage for, with its pinned-window meters",
                        symbol: "chart.bar",
                        isOn: $showUsage,
                        identifier: "settings.sidebar.showUsage")
                }
                Text("Hidden by default. Toggling this applies immediately.")
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.leading, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func toggleRow(
        _ title: String, subtitle: String, symbol: String,
        isOn: Binding<Bool>, identifier: String
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.glyph(.regular, weight: .light))
                    .frame(width: 24)
                    .foregroundStyle(Palette.ink.opacity(0.75))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.paseo(.body))
                    Text(subtitle)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Palette.toggleTint)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .accessibilityIdentifier(identifier)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 16).padding(.trailing, 16)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.paseo(.callout))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }
}
#endif
