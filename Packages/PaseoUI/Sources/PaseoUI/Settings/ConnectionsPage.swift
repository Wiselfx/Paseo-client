#if canImport(UIKit)
import SwiftUI
import UIKit

/// Settings → Host → Connections: one row per saved connection. The daemon exposes no
/// connections list (`messages.ts` has no such RPC); upstream's list is the client-side
/// `HostProfile.connections`, which here are the app's own saved endpoints (`SavedHosts`).
/// Live latency needs a probe this client doesn't run, so rows show label + endpoint and a
/// destructive Remove (the same Keychain-clearing forget as the Hosts page).
struct ConnectionsPage: View {
    @Environment(\.hostSwitch) private var context

    @State private var removeTarget: HostSwitchEntry?

    private let typography = ClaudeTypography()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Connections")
                if hosts.isEmpty {
                    RowGroup {
                        Text("No saved connections. Every successful connection is remembered here.")
                            .font(.system(size: 15))
                            .foregroundStyle(ClaudePalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(minHeight: 52, alignment: .leading)
                    }
                } else {
                    RowGroup {
                        ForEach(Array(hosts.enumerated()), id: \.element.id) { index, host in
                            connectionRow(host)
                            if index < hosts.count - 1 { rowDivider }
                        }
                    }
                }
                Text("One saved endpoint per connection. Removing one also removes its password from this device's Keychain.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .padding(.leading, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .confirmationDialog(
            "Remove connection?",
            isPresented: Binding(
                get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let target = removeTarget { context?.forgetHost(target.id) }
                removeTarget = nil
            }
            Button("Cancel", role: .cancel) { removeTarget = nil }
        } message: {
            Text("This will delete its saved connections from this device.")
        }
    }

    private var hosts: [HostSwitchEntry] { context?.hosts ?? [] }

    private func connectionRow(_ host: HostSwitchEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(host.label)
                        .font(.system(size: 17))
                        .lineLimit(1)
                    if host.isCurrent {
                        Text("Current")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ClaudePalette.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(ClaudePalette.chip, in: .capsule)
                    }
                }
                Text(host.urlLine)
                    .font(typography.mono(12, relativeTo: .footnote))
                    .foregroundStyle(ClaudePalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if host.isRelay {
                    Text("Encrypted relay")
                        .font(.system(size: 12))
                        .foregroundStyle(ClaudePalette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Haptics.selection()
                removeTarget = host
            } label: {
                Text("Remove")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ClaudePalette.failureInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(host.label)")
            .accessibilityIdentifier("settings.connections.remove.\(host.id.uuidString)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(minHeight: 56)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15))
            .foregroundStyle(ClaudePalette.secondary)
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 16)
    }
}
#endif
