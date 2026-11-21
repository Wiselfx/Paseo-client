#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → Host → Hosts: every daemon this device knows, in one list (audit C #3, #19).
/// Tap a row to switch to that host, swipe to remove it, and use the row's info button for its
/// detail page (rename, endpoint, remove). The last row adds a host through the app's existing
/// add-host route (`HostSwitchContext.addHost`). Data comes from the app-injected context; with
/// no context the page renders as empty.
struct HostsPage: View {
    let session: HostSession

    @Environment(\.hostSwitch) private var context

    @State private var removeTarget: HostSwitchEntry?
    @State private var switchTarget: HostSwitchEntry?

    private var hosts: [HostSwitchEntry] { context?.hosts ?? [] }

    var body: some View {
        PageList {
            Section {
                if hosts.isEmpty {
                    ListRow(title: "No saved hosts yet.")
                        .panelRow()
                } else {
                    ForEach(hosts) { host in
                        hostRow(host)
                    }
                }
                ListRow(title: "Add host", systemImage: "plus") {
                    context?.addHost()
                }
                .panelRow()
                .accessibilityIdentifier("settings.hosts.add")
            } header: {
                Text("Saved hosts")
            } footer: {
                Text(
                    "Passwords are stored per host in this device's Keychain, never in plain settings. Removing a host removes its password too."
                )
            }
        }
        .inlinePageTitle("Hosts")
        .confirmationDialog(
            "Remove host?",
            item: $removeTarget,
            titleVisibility: .visible
        ) { target in
            Button("Remove host", role: .destructive) { context?.forgetHost(target.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Removes this host and its saved connections from this device")
        }
        .confirmationDialog(
            "Switch host",
            item: $switchTarget,
            titleVisibility: .visible
        ) { target in
            Button("Switch host") { context?.switchTo(target.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            // The existing disconnect wording: switching closes this host's connection.
            Text("The connection to the host will be closed. Your settings are kept.")
        }
    }

    private func hostRow(_ host: HostSwitchEntry) -> some View {
        HStack(spacing: 0) {
            ListRow(
                title: host.label,
                subtitle: host.urlLine,
                accessory: ListRow.Accessory.checkmark(host.isCurrent),
                action: { requestSwitch(host) }
            )
            .accessibilityAddTraits(host.isCurrent ? .isSelected : [])
            .accessibilityIdentifier("settings.hosts.row.\(host.id.uuidString)")
            NavigationLink(value: SettingsRoute.hostDetail(host.id)) {
                Image(systemName: "info.circle")
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Details for \(host.label)")
            .accessibilityIdentifier("settings.hosts.details.\(host.id.uuidString)")
        }
        .panelRow()
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                removeTarget = host
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    /// Switching confirms first only while agents are running on this host.
    private func requestSwitch(_ host: HostSwitchEntry) {
        guard !host.isCurrent else { return }
        if session.runningAgentCount > 0 {
            switchTarget = host
        } else {
            context?.switchTo(host.id)
        }
    }
}
#endif
