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
                    Haptics.selection()
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
            isPresented: Binding(
                get: { removeTarget != nil },
                set: { if !$0 { removeTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove host", role: .destructive) {
                if let id = removeTarget?.id { context?.forgetHost(id) }
                removeTarget = nil
            }
            Button("Cancel", role: .cancel) { removeTarget = nil }
        } message: {
            Text("Removes this host and its saved connections from this device")
        }
        .confirmationDialog(
            "Switch host",
            isPresented: Binding(
                get: { switchTarget != nil },
                set: { if !$0 { switchTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Switch host") {
                if let id = switchTarget?.id { context?.switchTo(id) }
                switchTarget = nil
            }
            Button("Cancel", role: .cancel) { switchTarget = nil }
        } message: {
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
        Haptics.selection()
        guard !host.isCurrent else { return }
        if session.runningAgentCount > 0 {
            switchTarget = host
        } else {
            context?.switchTo(host.id)
        }
    }
}

/// One saved host: rename, the endpoint details and remove. `Back` returns to the list.
struct HostDetailPage: View {
    let hostID: UUID

    @Environment(\.hostSwitch) private var context

    @State private var renameText = ""
    @State private var renaming = false
    @State private var confirmRemove = false

    private var host: HostSwitchEntry? {
        context?.hosts.first { $0.id == hostID }
    }

    var body: some View {
        PageList {
            if let host {
                Section {
                    ListRow(title: "Name", accessory: ListRow.Accessory.value(host.label))
                        .panelRow()
                    ListRow(title: "Rename") {
                        Haptics.selection()
                        renameText = host.label
                        renaming = true
                    }
                    .panelRow()
                    .accessibilityIdentifier("settings.hosts.rename")
                } header: {
                    Text("Label")
                }
                Section {
                    ListRow(title: "Endpoint", accessory: ListRow.Accessory.value(host.urlLine))
                        .panelRow()
                    ListRow(title: "Connection", accessory: ListRow.Accessory.value(connectionKind(host)))
                        .panelRow()
                    ListRow(title: "Last connected", accessory: ListRow.Accessory.value(lastConnected(host)))
                        .panelRow()
                } header: {
                    Text("Connection")
                }
                Section {
                    Button(role: .destructive) {
                        confirmRemove = true
                    } label: {
                        Text("Remove host")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .panelRow()
                    .accessibilityIdentifier("settings.hosts.remove")
                } footer: {
                    Text("Removes this host and its saved connections from this device")
                }
            } else {
                EmptyState(title: "Host not found")
                    .panelRow(Palette.background)
            }
        }
        .inlinePageTitle(host?.label ?? "Host")
        .alert("Rename host", isPresented: $renaming) {
            TextField("Label", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                context?.renameHost(hostID, trimmed)
            }
        }
        .confirmationDialog(
            "Remove host?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove host", role: .destructive) {
                context?.forgetHost(hostID)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes this host and its saved connections from this device")
        }
    }

    private func connectionKind(_ host: HostSwitchEntry) -> String {
        if host.isCurrent { return "Connected now" }
        return host.isRelay ? "Encrypted relay" : "Direct"
    }

    private func lastConnected(_ host: HostSwitchEntry) -> String {
        guard let date = host.lastConnectedAt else { return "Never connected on this device" }
        if host.isCurrent { return "Connected now" }
        return "Last connected \(HostsPage.relative(date))"
    }
}

extension HostsPage {
    /// `just now`, `5m ago`, `yesterday`, `3d ago`: the list's age line.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        let days = seconds / 86400
        return days == 1 ? "yesterday" : "\(days)d ago"
    }
}
#endif
