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
    /// Which restart confirmation is up. Nil closes it.
    @State private var restartKind: RestartKind?
    /// "Host offline" is shown instead of the confirmation when the socket is down.
    @State private var showOffline = false

    private enum RestartKind: Hashable {
        case keepTerminals
        case closeTerminals
    }

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
            if !hostSettings.restartRequiredPaths.isEmpty {
                Section {
                    InlineBanner(
                        .warning,
                        title: restartRequiredTitle,
                        message: restartRequiredMessage,
                        action: ("Restart", { startRestart(.keepTerminals) }))
                        .panelRow(Palette.background)
                }
            }
            Section {
                restartRow
                if hostSettings.terminalsSurviveRestart {
                    closeTerminalsRow
                }
                if let restartError = hostSettings.restartError {
                    InlineBanner(
                        .failure, title: restartErrorTitle(restartError),
                        message: restartErrorMessage(restartError))
                        .panelRow(Palette.background)
                }
            } header: {
                Text("Daemon")
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
        .confirmationDialog(
            "Restart \(hostName)",
            item: $restartKind,
            titleVisibility: .visible
        ) { kind in
            Button(kind == .closeTerminals ? "Restart and close terminals" : "Restart", role: .destructive) {
                restartKind = nil
                Haptics.medium()
                Task { await hostSettings.restart(killTerminals: kind == .closeTerminals) }
            }
            Button("Cancel", role: .cancel) { restartKind = nil }
        } message: { kind in
            Text(kind == .closeTerminals ? closeTerminalsConfirmMessage : restartConfirmMessage)
        }
        .alert("Host offline", isPresented: $showOffline) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "This host is offline. Paseo reconnects automatically-wait until it's back online before restarting."
            )
        }
    }

    // MARK: Restart

    /// Restart card, upstream's copy verbatim (`settings.host.daemon.restart`, en.ts:3074-3094).
    @ViewBuilder private var restartRow: some View {
        ListRow(
            title: "Restart daemon",
            subtitle: "Restarts the daemon process. The app will reconnect automatically",
            systemImage: "arrow.clockwise",
            accessory: ListRow.Accessory.value(
                hostSettings.isRestarting ? "Restarting..." : "Restart"),
            action: { startRestart(.keepTerminals) })
            .panelRow()
            .disabled(hostSettings.isRestarting)
            .accessibilityIdentifier("settings.restart")
    }

    /// Only when the host advertises `terminalsSurviveRestart`; otherwise a restart closes
    /// terminals anyway and offering the choice would lie
    /// (`packages/app/src/screens/settings/host-page.tsx:679-694`).
    @ViewBuilder private var closeTerminalsRow: some View {
        ListRow(
            title: "Restart and close terminals",
            subtitle: "Restart and also close every terminal running on this host.",
            action: { startRestart(.closeTerminals) })
            .panelRow()
            .disabled(hostSettings.isRestarting)
    }

    private var hostName: String { session.serverInfo?.hostname ?? "Paseo host" }

    private var restartConfirmMessage: String {
        "This will restart the daemon. Agents running on it will keep going; the app will reconnect automatically."
    }

    private var closeTerminalsConfirmMessage: String {
        "This will restart the daemon and close every terminal on it, ending the programs running in them. The app will reconnect automatically."
    }

    /// A saved setting the running daemon did not adopt. Upstream's wording for the state is
    /// "saved; not applied" (`public-docs/configuration.md:59`); the paths come from
    /// `daemon.config.reload.response`.
    private var restartRequiredTitle: String { "Restart required" }

    private var restartRequiredMessage: String {
        "Saved; not applied. Restart the daemon to apply: \(hostSettings.restartRequiredPaths.formatted())."
    }

    private func restartErrorTitle(_ error: HostSettingsStore.RestartError) -> String {
        switch error {
        case .requestFailed: "Error"
        case .unableToReconnect: "Unable to reconnect"
        }
    }

    private func restartErrorMessage(_ error: HostSettingsStore.RestartError) -> String {
        switch error {
        case .requestFailed(let message): message
        case .unableToReconnect: "\(hostName) did not come back online. Please verify it restarted."
        }
    }

    /// Asks for the destructive confirmation, unless the socket is down: then say so instead of
    /// sending a request that cannot land (`host-page.tsx:598-611`).
    private func startRestart(_ kind: RestartKind) {
        guard hostSettings.isRestarting == false else { return }
        guard case .connected = session.connection else {
            showOffline = true
            return
        }
        restartKind = kind
    }

    /// The live connection line: the state dot beside the row's value (the R4 row carries one
    /// trailing accessory, so the dot stays its own element).
    private var connectionRow: some View {
        HStack(spacing: Space.sm) {
            StatusDot(connectionKind(session.connection))
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

    private func connectionKind(_ state: ConnectionState) -> StatusDot.State {
        switch state {
        case .connected: .idle
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
