#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The Settings sheet: SheetScaffold provides the header and the `NavigationStack`; every page
/// pushes onto it, so back and swipe-back reach the parent (audit C #10).
struct SettingsRoot: View {
    let session: HostSession
    var onDisconnect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.hostSwitch) private var hostSwitch
    @AppStorage(ClaudeAppearance.storageKey) private var appearance = ClaudeAppearance.system.rawValue
    @AppStorage("paseo.terminal.scrollback") private var terminalScrollback = 2_000

    @State private var confirmDisconnect = false

    private var hostSettings: HostSettingsStore { session.hostSettings }

    var body: some View {
        SheetScaffold("Settings", detents: .large) {
            PageList {
                Section {
                    routeRow(
                        .general, value: appearance,
                        identifier: "settings.route.general")
                    routeRow(.sidebar, identifier: "settings.route.sidebar")
                    routeRow(
                        .terminal, value: scrollbackSummary,
                        identifier: "settings.route.terminal")
                } header: {
                    PageSectionHeader("App")
                }
                Section {
                    if case .failed = hostSettings.phase {
                        InlineBanner(
                            .failure, title: "Couldn't load host settings",
                            action: ("Try again", retryHostSettings)
                        )
                        .panelRow()
                    }
                    routeRow(
                        .overview, value: session.serverInfo?.hostname ?? "Paseo host",
                        identifier: "settings.route.overview")
                    routeRow(.hosts, value: hostsSummary, identifier: "settings.route.hosts")
                    if hostSettings.supportsPairingOffer {
                        routeRow(.pairDevice, identifier: "settings.route.pairDevice")
                    }
                    routeRow(.agents, value: agentsSummary, identifier: "settings.route.agents")
                    routeRow(.metadata, value: metadataSummary, identifier: "settings.route.metadata")
                    routeRow(.voice, value: voiceSummary, identifier: "settings.route.voice")
                    routeRow(
                        .workspaces, value: workspacesSummary,
                        identifier: "settings.route.workspaces")
                    routeRow(.projects, value: projectCountLine, identifier: "settings.route.projects")
                    routeRow(
                        .providers, value: providersSummary, identifier: "settings.route.providers")
                } header: {
                    PageSectionHeader("Host")
                }
                Section {
                    routeRow(.about, value: versionLine, identifier: "settings.route.about")
                    routeRow(.diagnostics, identifier: "settings.route.diagnostics")
                    routeRow(.help, identifier: "settings.route.help")
                } header: {
                    PageSectionHeader("About")
                }
                Section {
                    Button(role: .destructive) {
                        confirmDisconnect = true
                    } label: {
                        Text("Disconnect")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .panelRow()
                    .accessibilityIdentifier("settings.disconnect")
                    // On the trigger, not the sheet, so the dialog animates from the button.
                    .confirmationDialog(
                        "Disconnect from this host?",
                        isPresented: $confirmDisconnect,
                        titleVisibility: .visible
                    ) {
                        Button("Disconnect", role: .destructive) {
                            onDisconnect()
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The connection to the host will be closed. Your settings are kept.")
                    }
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(route)
            }
        }
        .task {
            if hostSettings.config == nil, hostSettings.phase != .loading {
                await hostSettings.load()
            }
            if session.agentControl.phase == .idle {
                await session.agentControl.loadCatalog()
            }
        }
    }

    // MARK: Destinations

    @ViewBuilder private func destination(_ route: SettingsRoute) -> some View {
        switch route {
        case .general: GeneralPage()
        case .sidebar: SidebarPage()
        case .terminal: TerminalPage()
        case .overview: OverviewPage(session: session)
        case .hosts: HostsPage(session: session)
        case .hostDetail(let id): HostDetailPage(hostID: id)
        case .pairDevice: PairDevicePage(session: session)
        case .agents: AgentsPage(session: session)
        case .metadata: MetadataPage(session: session)
        case .metadataModel: MetadataModelPage(session: session)
        case .voice: VoicePage(session: session)
        case .workspaces: WorkspacesPage(session: session)
        case .projects: ProjectsPage(session: session)
        case .project(let id): ProjectPage(session: session, projectID: id)
        case .providers: ProvidersPage(session: session)
        case .provider(let id): ProviderPage(session: session, providerID: id)
        case .about: AboutPage(session: session)
        case .diagnostics: DiagnosticsPage(session: session)
        case .help: HelpPage(session: session)
        }
    }

    // MARK: Rows

    private func routeRow(_ route: SettingsRoute, value: String? = nil, identifier: String) -> some View {
        PageLink(
            route,
            title: route.title ?? "",
            systemImage: route.symbol,
            detail: value
        )
        .accessibilityIdentifier(identifier)
    }

    // MARK: Summaries

    private var scrollbackSummary: String {
        switch terminalScrollback {
        case 1_000: "1k lines"
        case 5_000: "5k lines"
        case 10_000: "10k lines"
        default: "2k lines"
        }
    }

    private var hostsSummary: String {
        let count = hostSwitch?.hosts.count ?? 0
        return count == 0 ? "None" : "\(count) saved"
    }

    /// A host-config summary's detail: the value once the config is in, "Loading…" while it
    /// loads, "Couldn't load" when it failed (the section's banner offers Try again), and
    /// nothing when the value is genuinely absent. A bare dash told those four apart by nothing.
    private func hostDetail(_ value: () -> String?) -> String? {
        if hostSettings.config != nil { return value() }
        switch hostSettings.phase {
        case .idle, .loading: return "Loading…"
        case .failed: return "Couldn't load"
        case .ready: return nil
        }
    }

    private func retryHostSettings() {
        Task { await hostSettings.load() }
    }

    private var agentsSummary: String? {
        hostDetail {
            (hostSettings.config?.mcp?.injectIntoAgents ?? true) ? "Tools on" : "Tools off"
        }
    }

    private var metadataSummary: String? {
        hostDetail {
            let automatic = hostSettings.config?.metadataGeneration?.providers.isEmpty ?? true
            return automatic ? "Automatic" : "Manual"
        }
    }

    private var workspacesSummary: String? {
        hostDetail {
            hostSettings.config?.autoArchiveAfterMerge == true ? "Auto-archive" : "Manual"
        }
    }

    private var projectCountLine: String {
        let count = session.workspaceDirectory.projects.count
        return String(
            AttributedString(localized: "^[\(count) project](inflect: true)", bundle: #bundle).characters)
    }

    private var providersSummary: String {
        let count = session.agentControl.providers.count
        return String(
            AttributedString(localized: "^[\(count) provider](inflect: true)", bundle: #bundle).characters)
    }

    private var voiceSummary: String? {
        hostDetail {
            guard let speech = session.voiceSettings.speechSettings else { return nil }
            let dictation = speech.dictationEnabled ? "Dictation on" : "Dictation off"
            let voiceMode = speech.voiceModeEnabled ? "Voice on" : "Voice off"
            return "\(dictation) · \(voiceMode)"
        }
    }

    private var versionLine: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        default: return "Unknown"
        }
    }
}
#endif
