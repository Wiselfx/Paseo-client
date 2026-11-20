#if canImport(UIKit)
import PaseoStore
import SwiftUI

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
#endif
