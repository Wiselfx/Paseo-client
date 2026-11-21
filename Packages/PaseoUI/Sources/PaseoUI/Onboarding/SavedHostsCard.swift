#if canImport(UIKit)
import SwiftUI

/// A content-sized card, not a `List`: one host must not scroll and the card must never cut
/// its own last row (E2 §4). The List-only swipe-to-delete is replaced by the existing
/// context-menu "Forget" (same confirmation); no new copy.
struct SavedHostsCard: View {
    let hosts: [HostSwitchEntry]
    let connecting: Bool
    let onConnect: (UUID) -> Void
    let onRename: (HostSwitchEntry) -> Void
    let onForget: (HostSwitchEntry) -> Void
    let onAddHost: () -> Void

    var body: some View {
        RowGroup {
            ForEach(hosts.enumerated(), id: \.element.id) { index, host in
                if index > 0 { RowDivider() }
                ListRow(
                    title: host.label,
                    subtitle: host.urlLine,
                    systemImage: host.isCurrent ? "checkmark.circle.fill" : "desktopcomputer",
                    accessory: connecting ? ListRow.Accessory.progress : ListRow.Accessory.chevron,
                    action: {
                        onConnect(host.id)
                    }
                )
                .disabled(connecting)
                .contextMenu {
                    Button {
                        onRename(host)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onForget(host)
                    } label: {
                        Label("Forget", systemImage: "trash")
                    }
                }
                .accessibilityIdentifier("connect.saved.\(host.id.uuidString)")
            }
            RowDivider()
            ListRow(title: "Add host", systemImage: "plus.circle", action: onAddHost)
                .accessibilityIdentifier("connect.addHost")
        }
        .padding(.horizontal, Space.lg)
    }
}
#endif
