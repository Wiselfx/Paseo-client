#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → Host → Overview: this host's connection, identity and the config switches that
/// belong to no other page. Removing the host lives in Hosts (§2), and Disconnect is the root's
/// last section (§1).
struct OverviewPage: View {
    let session: HostSession

    private var hostSettings: HostSettingsStore { session.hostSettings }

    /// The developer facts (server id, protocol, terminal hooks) sit behind one collapsed
    /// "Advanced" disclosure; the page opens on the connection itself (R11 §3).
    @State private var showAdvanced = false

    var body: some View {
        PageList {
            Section {
                connectionRow
                ListRow(
                    title: "Host version",
                    accessory: ListRow.Accessory.value(session.serverInfo?.version ?? "Unknown")
                )
                .panelRow()
            } header: {
                Text("Connection")
            }
            Section {
                DisclosureGroup(isExpanded: $showAdvanced) {
                    ListRow(
                        title: "Server ID",
                        accessory: ListRow.Accessory.value(
                            session.serverInfo?.serverId ?? "Not connected")
                    )
                    .panelRow()
                    ListRow(
                        title: "Protocol version",
                        accessory: ListRow.Accessory.value(
                            session.serverInfo?.protocolVersion.map { String($0) } ?? "Unknown")
                    )
                    .panelRow()
                    ListRow(
                        title: "Terminal agent hooks",
                        accessory: ListRow.Accessory.toggle(
                            configBinding(
                                get: { $0.enableTerminalAgentHooks },
                                set: { $0.enableTerminalAgentHooks = $1 }))
                    )
                    .panelRow()
                    .disabled(configControlsDisabled)
                    .accessibilityIdentifier("settings.config.Terminal agent hooks")
                    ListRow(
                        title: "Usage tracking",
                        accessory: ListRow.Accessory.toggle(
                            configBinding(
                                get: { $0.usage?.enabled ?? false },
                                set: { $0.usage = .init(enabled: $1) }))
                    )
                    .panelRow()
                    .disabled(configControlsDisabled)
                    .accessibilityIdentifier("settings.config.Usage tracking")
                } label: {
                    Text("Advanced")
                        .font(.paseo(.body))
                        .foregroundStyle(Palette.ink)
                }
                .tint(Palette.secondaryInk)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
                .listRowBackground(Palette.panel)
            } footer: {
                Text(
                    "Unset toggles show as off. Changes apply immediately; the effective config comes back from the host."
                )
            }
            if let error = hostSettings.error {
                Section {
                    InlineBanner(
                        .failure, title: error,
                        action: ("Try again", { Task { await hostSettings.load() } }))
                        .panelRow(Palette.background)
                }
            }
        }
        .inlinePageTitle("Overview")
        .refreshable { await hostSettings.load() }
    }

    /// The live connection line: the state dot beside the row's value (the R4 row carries one
    /// trailing accessory, so the dot stays its own element).
    private var connectionRow: some View {
        HStack(spacing: Space.sm) {
            PaseoStatusDot(kind: connectionKind(session.connection))
                .padding(.leading, Space.lg)
            ListRow(
                title: "Connection",
                subtitle: session.serverInfo?.hostname ?? "Paseo host",
                accessory: ListRow.Accessory.value(connectionLabel(session.connection))
            )
        }
        .panelRow()
    }

    private var configControlsDisabled: Bool {
        hostSettings.isSaving || hostSettings.config == nil
    }

    private func configBinding(
        get: @escaping (DaemonConfig) -> Bool,
        set: @escaping (inout DaemonConfigPatch, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard let config = hostSettings.config else { return false }
                return get(config)
            },
            set: { newValue in
                Haptics.selection()
                var patch = DaemonConfigPatch()
                set(&patch, newValue)
                Task { await hostSettings.save(patch) }
            })
    }

    private func connectionKind(_ state: ConnectionState) -> PaseoStatusDot.Kind {
        switch state {
        case .connected: .done
        case .reconnecting, .connecting: .running
        case .failed: .failed
        case .idle: .idle
        }
    }

    private func connectionLabel(_ state: ConnectionState) -> String {
        switch state {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .reconnecting(let attempt, _): "Reconnecting (attempt \(attempt))"
        case .failed: "Disconnected"
        case .idle: "Not connected"
        }
    }
}
#endif
