#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Every page in Settings, as one value the navigation stack can push (PLAN §RE).
/// Leaf cases are the root rows; the rest are nested pages, so back always returns to the parent.
enum SettingsRoute: Hashable {
    // App
    case general
    case sidebar
    case terminal
    // Host
    case overview
    case hosts
    case hostDetail(UUID)
    case pairDevice
    case agents
    case metadata
    case metadataModel
    case voice
    case workspaces
    case projects
    case project(String)
    case providers
    case provider(String)
    // About
    case about
    case diagnostics
    case help

    /// The page's navigation title. `nil` when the page titles itself (a host, a project).
    var title: String? {
        switch self {
        case .general: "General"
        case .sidebar: "Sidebar"
        case .terminal: "Terminal"
        case .overview: "Overview"
        case .hosts: "Hosts"
        case .hostDetail: nil
        case .pairDevice: "Pair a device" // en.ts:2916 settings.host.pairDevices.rowTitle
        case .agents: "Agents"
        case .metadata: "Metadata"
        case .metadataModel: "Model"
        case .voice: "Voice"
        case .workspaces: "Workspaces"
        case .projects: "Projects"
        case .project: nil
        case .providers: "Providers"
        case .provider: nil
        case .about: "About"
        case .diagnostics: "Diagnostics"
        case .help: "Help & support"
        }
    }

    /// The row glyph. UX-SPEC §0.3: no `link`, and Model and Providers do not share a symbol.
    var symbol: String? {
        switch self {
        case .general: "gearshape"
        case .sidebar: "sidebar.left"
        case .terminal: "terminal"
        case .overview: "server.rack"
        case .hosts: "network"
        case .hostDetail: nil
        case .pairDevice: "qrcode"
        case .agents: "person.2"
        case .metadata: "wand.and.stars"
        case .metadataModel: "cpu"
        case .voice: "mic"
        case .workspaces: "square.stack"
        case .projects: "folder"
        case .project: nil
        case .providers: "square.stack.3d.up"
        case .provider: nil
        case .about: "info.circle"
        case .diagnostics: "stethoscope"
        case .help: "questionmark.circle"
        }
    }
}

/// A settings row whose trailing value opens a menu (font sizes, scrollback, chat display).
/// The menu's tap target is the whole R4 row.
struct SettingsMenuRow<MenuContent: View>: View {
    private let title: String
    private let value: String
    private let menu: () -> MenuContent

    init(_ title: String, value: String, @ViewBuilder menu: @escaping () -> MenuContent) {
        self.title = title
        self.value = value
        self.menu = menu
    }

    var body: some View {
        Menu {
            menu()
        } label: {
            ListRow(title: title, accessory: ListRow.Accessory.value(value))
        }
        .panelRow()
        .accessibilityLabel("\(title), currently \(value)")
    }
}

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
                    Text("App")
                }
                Section {
                    routeRow(
                        .overview, value: session.serverInfo?.hostname ?? "Paseo daemon",
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
                    Text("Host")
                }
                Section {
                    routeRow(.about, value: versionLine, identifier: "settings.route.about")
                    routeRow(.diagnostics, identifier: "settings.route.diagnostics")
                    routeRow(.help, identifier: "settings.route.help")
                } header: {
                    Text("About")
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
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(route)
            }
        }
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
            Text("The connection to the daemon will be closed. Your settings are kept.")
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
        NavigationLink(value: route) {
            ListRow(
                title: route.title ?? "",
                systemImage: route.symbol,
                accessory: routeAccessory(value)
            )
        }
        .panelRow()
        .accessibilityIdentifier(identifier)
    }

    private func routeAccessory(_ value: String?) -> ListRow.Accessory {
        guard let value else { return ListRow.Accessory.none }
        return ListRow.Accessory.value(value)
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

    private var agentsSummary: String {
        guard let config = hostSettings.config else { return "—" }
        return (config.mcp?.injectIntoAgents ?? true) ? "Tools on" : "Tools off"
    }

    private var metadataSummary: String {
        guard let config = hostSettings.config else { return "—" }
        let automatic = config.metadataGeneration?.providers.isEmpty ?? true
        return automatic ? "Automatic" : "Manual"
    }

    private var workspacesSummary: String {
        guard let config = hostSettings.config else { return "—" }
        return (config.autoArchiveAfterMerge ?? false) ? "Auto-archive" : "Manual"
    }

    private var projectCountLine: String {
        let count = session.workspaceDirectory.groups.count
        return count == 1 ? "1 project" : "\(count) projects"
    }

    private var providersSummary: String {
        let count = session.agentControl.providers.count
        return "\(count) provider\(count == 1 ? "" : "s")"
    }

    private var voiceSummary: String {
        guard let speech = session.voiceSettings.speechSettings else { return "—" }
        let dictation = speech.dictationEnabled ? "Dictation on" : "Dictation off"
        let voiceMode = speech.voiceModeEnabled ? "Voice on" : "Voice off"
        return "\(dictation) · \(voiceMode)"
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

/// The old entry point, kept so the sidebar's call site (`PaseoSidebar.swift`) compiles while
/// Shell moves to `SettingsRoot`. Same sheet, same arguments; it is not deprecated on purpose,
/// so the call site does not warn.
struct PaseoSettingsView: View {
    let session: HostSession
    var onDisconnect: () -> Void

    var body: some View {
        SettingsRoot(session: session, onDisconnect: onDisconnect)
    }
}
#endif
