#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The full Settings screen: General, host pages (Overview, Agents, Metadata, Workspaces,
/// Projects, Providers) and About. ClaudeUI's settings layout (glass-circle back/close,
/// pushed pages, grouped rows) wired to the live session and the app's `@AppStorage` keys.
/// Opened from the sidebar avatar.
struct PaseoSettingsView: View {
    let session: HostSession
    var onDisconnect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.hostSwitch) private var hostSwitch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PaseoSettingsKeys.appearance) private var appearance = ClaudeAppearance.system.rawValue
    /// Shared with the terminal view (Settings → Terminal).
    @AppStorage("paseo.terminal.scrollback") private var terminalScrollback = 2_000
    @AppStorage(ClaudeTextScale.contentStorageKey) private var contentTextSize = ClaudeTextScale.Content.medium.rawValue
    @AppStorage(ClaudeTextScale.codeStorageKey) private var codeFontSize = ClaudeTextScale.Code.medium.rawValue
    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""
    @AppStorage(PaseoSettingsKeys.haptics) private var haptics = true
    @AppStorage(PaseoSettingsKeys.mascot) private var mascot = true
    /// M10: post local OS notifications when an agent or terminal needs you. On by default;
    /// permission is requested the first time one arrives, or when this is switched on.
    @AppStorage(AttentionNotificationKeys.enabled) private var notificationsEnabled = true
    /// M12: attention sound cue level (off | soft | clear), DSH wording. Default off.
    @AppStorage(SoundCueLevel.storageKey) private var soundCueLevel = SoundCueLevel.off.rawValue
    @Environment(\.notificationPermissionAction) private var requestNotificationPermission
    /// M8c: what tap does on send while a turn is running (steer | queue | interrupt).
    @AppStorage(DefaultSendBehavior.storageKey) private var defaultSend = DefaultSendBehavior.steer.rawValue
    /// M7f: Full / Collapse tool calls / Collapse turns (Settings → General → Chat).
    @AppStorage(ChatDisplayMode.storageKey) private var chatDisplay = ChatDisplayMode.full.rawValue
    @AppStorage("paseo.reasoning.alwaysExpand") private var alwaysExpandReasoning = false
    @State private var page: Page?
    @State private var providerSheetID: String?
    @State private var confirmDisconnect = false
    @State private var confirmRemoveHost = false
    @State private var confirmRemoveProject: WorkspaceProjectDescriptor?
    @State private var projectPage: WorkspaceProjectDescriptor?
    @State private var appendPromptDraft: String?
    @State private var appendPromptSaving = false
    @State private var resumePromptDraft: String?
    @State private var resumePromptSaving = false
    @FocusState private var appendPromptFocused: Bool
    @FocusState private var resumePromptFocused: Bool

    private let typography = ClaudeTypography()

    enum Page: String, CaseIterable, Identifiable, Equatable {
        case general
        case overview
        case connections
        case pairDevice
        case hosts
        case agents
        case metadata
        case metadataModel
        case voice
        case workspaces
        case projects
        case providers
        case about
        case sidebar
        case terminal
        case diagnostics
        case help

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .overview: "Overview"
            case .connections: "Connections"
            case .pairDevice: "Pair device"
            case .hosts: "Hosts"
            case .agents: "Agents"
            case .metadata: "Metadata"
            case .metadataModel: "Model"
            case .voice: "Voice"
            case .workspaces: "Workspaces"
            case .projects: "Projects"
            case .providers: "Providers"
            case .about: "About"
            case .sidebar: "Sidebar"
            case .terminal: "Terminal"
            case .diagnostics: "Diagnostics"
            case .help: "Help & support"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .overview: "server.rack"
            case .connections: "link"
            case .pairDevice: "qrcode"
            case .hosts: "network"
            case .agents: "person.2"
            case .metadata: "wand.and.stars"
            case .metadataModel: "cpu"
            case .voice: "mic"
            case .workspaces: "square.stack"
            case .projects: "folder"
            case .providers: "cpu"
            case .about: "info.circle"
            case .sidebar: "sidebar.left"
            case .terminal: "terminal"
            case .diagnostics: "stethoscope"
            case .help: "questionmark.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let page {
                detail(for: page)
            } else {
                root
            }
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .tint(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationCornerRadius(40)
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: Binding(
            get: { providerSheetID != nil },
            set: { if !$0 { providerSheetID = nil } })) {
                if let providerSheetID {
                    ProviderDetailSheet(session: session, providerID: providerSheetID)
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
            if session.hostSettings.config == nil, session.hostSettings.phase != .loading {
                await session.hostSettings.load()
            }
            if session.agentControl.phase == .idle {
                await session.agentControl.loadCatalog()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text(page?.title ?? "Settings")
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
            HStack {
                Button {
                    if page == nil {
                        dismiss()
                    } else {
                        open(nil)
                    }
                } label: {
                    Image(systemName: page == nil ? "xmark" : "chevron.left")
                        .font(.system(size: 21, weight: .light))
                        .frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel(page == nil ? "Close settings" : "Back")
                Spacer()
                if page == .providers {
                    Button {
                        Task { await session.agentControl.refreshCatalog() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 19, weight: .light))
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(in: .circle)
                    .accessibilityLabel("Refresh providers")
                } else if page != nil {
                    Button {
                        Task { await session.hostSettings.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 19, weight: .light))
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(in: .circle)
                    .accessibilityLabel("Refresh host settings")
                }
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func open(_ next: Page?) {
        if reduceMotion {
            page = next
            return
        }
        withAnimation(.easeOut(duration: 0.2)) { page = next }
    }

    // MARK: Root

    private var root: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("App")
                RowGroup {
                    settingsRow(.general, symbol: Page.general.symbol, value: appearance)
                    rowDivider
                    settingsRow(.sidebar, symbol: Page.sidebar.symbol)
                    rowDivider
                    settingsRow(.terminal, symbol: Page.terminal.symbol, value: scrollbackSummary)
                }
                sectionLabel("Host")
                RowGroup {
                    settingsRow(
                        .overview, symbol: Page.overview.symbol,
                        value: session.serverInfo?.hostname ?? "Paseo daemon")
                    rowDivider
                    settingsRow(.connections, symbol: Page.connections.symbol)
                    rowDivider
                    if session.hostSettings.supportsPairingOffer {
                        settingsRow(.pairDevice, symbol: Page.pairDevice.symbol)
                        rowDivider
                    }
                    settingsRow(.hosts, symbol: Page.hosts.symbol, value: hostsSummary)
                    rowDivider
                    settingsRow(
                        .agents, symbol: Page.agents.symbol,
                        value: session.hostSettings.config == nil ? "—" : ((session.hostSettings.config?.mcp?.injectIntoAgents ?? true) ? "Tools on" : "Tools off"))
                    rowDivider
                    settingsRow(
                        .metadata, symbol: Page.metadata.symbol,
                        value: session.hostSettings.config == nil ? "—" : (metadataMode == .automatic ? "Automatic" : "Manual"))
                    rowDivider
                    settingsRow(
                        .voice, symbol: Page.voice.symbol,
                        value: voiceSummary)
                    rowDivider
                    settingsRow(
                        .workspaces, symbol: Page.workspaces.symbol,
                        value: session.hostSettings.config == nil ? "—" : ((session.hostSettings.config?.autoArchiveAfterMerge ?? false) ? "Auto-archive" : "Manual"))
                    rowDivider
                    settingsRow(
                        .projects, symbol: Page.projects.symbol,
                        value: projectCountLine)
                    rowDivider
                    settingsRow(
                        .providers, symbol: Page.providers.symbol,
                        value: providersSummary)
                }
                sectionLabel("About")
                RowGroup {
                    settingsRow(.about, symbol: Page.about.symbol, value: versionLine)
                    rowDivider
                    settingsRow(.diagnostics, symbol: Page.diagnostics.symbol)
                    rowDivider
                    settingsRow(.help, symbol: Page.help.symbol)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Pages

    @ViewBuilder private func detail(for page: Page) -> some View {
        switch page {
        case .general: generalPage
        case .overview: overviewPage
        case .connections: ConnectionsPage()
        case .pairDevice: PairDevicePage(session: session)
        case .hosts: HostsPage()
        case .agents: agentsPage
        case .metadata: metadataPage
        case .metadataModel: metadataModelPage
        case .voice: VoicePage(session: session)
        case .workspaces: workspacesPage
        case .projects: projectsPage
        case .providers: providersPage
        case .about: aboutPage
        case .sidebar: SidebarPage()
        case .terminal: TerminalPage()
        case .diagnostics: DiagnosticsPage(session: session)
        case .help:
            ScrollView {
                HelpMenuItems(
                    onRunDiagnostics: { open(.diagnostics) },
                    daemonVersion: session.serverInfo?.version
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: General

    private var defaultSendBehavior: DefaultSendBehavior {
        DefaultSendBehavior(rawValue: defaultSend) ?? .steer
    }

    private var chatDisplayMode: ChatDisplayMode {
        ChatDisplayMode(rawValue: chatDisplay) ?? .full
    }

    private var generalPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Appearance")
                RowGroup {
                    HStack(spacing: 10) {
                        ForEach([ClaudeAppearance.light, .dark, .pureBlack, .system], id: \.self) { choice in
                            Button {
                                Haptics.selection()
                                appearance = choice.rawValue
                            } label: {
                                VStack(spacing: 9) {
                                    appearancePreview(choice)
                                        .frame(height: 68)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 14).stroke(
                                                appearance == choice.rawValue ? Color.blue : .clear,
                                                lineWidth: 2)
                                        }
                                    Text(choice.rawValue)
                                        .font(.system(size: 14))
                                        .foregroundStyle(
                                            appearance == choice.rawValue ? .blue : ClaudePalette.secondaryInk)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(choice.rawValue) appearance")
                            .accessibilityAddTraits(
                                appearance == choice.rawValue ? .isSelected : [])
                            .accessibilityIdentifier("settings.appearance." + choice.rawValue)
                        }
                    }
                    .padding(16)
                }
                sectionLabel("Fonts")
                RowGroup {
                    scaleMenuRow(
                        "Content size", symbol: "textformat.size",
                        options: ClaudeTextScale.Content.allCases,
                        current: contentTextSize,
                        identifier: "settings.fonts.content") { choice in
                            contentTextSize = choice.rawValue
                        }
                    rowDivider
                    scaleMenuRow(
                        "Code size", symbol: "chevron.left.forwardslash.chevron.right",
                        options: ClaudeTextScale.Code.allCases,
                        current: codeFontSize,
                        identifier: "settings.fonts.code") { choice in
                            codeFontSize = choice.rawValue
                        }
                }
                Text("Content size scales prose and headings on top of Dynamic Type; code size scales code blocks, diffs and tool output. Applies live.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .padding(.leading, 16)
                sectionLabel("You")
                RowGroup {
                    HStack {
                        Text("Your name")
                            .font(.system(size: 17))
                        Spacer(minLength: 8)
                        TextField("Your name", text: $name)
                            .font(.system(size: 17))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                }
                Text("Used in the greeting on the home screen and the sidebar avatar.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .padding(.leading, 16)
                sectionLabel("Feedback")
                RowGroup {
                    Toggle(isOn: $haptics) {
                        Label(
                            "Haptic feedback",
                            systemImage: "iphone.gen3.radiowaves.left.and.right"
                        )
                        .font(.system(size: 17))
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .accessibilityIdentifier("settings.haptics")
                    Divider().padding(.leading, 16)
                    Toggle(isOn: $mascot) {
                        Label("Show mascot", systemImage: "sparkles")
                            .font(.system(size: 17))
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .accessibilityIdentifier("settings.mascot")
                }
                sectionLabel("Notifications")
                RowGroup {
                    Toggle(isOn: $notificationsEnabled) {
                        Label("Agent notifications", systemImage: "bell")
                            .font(.system(size: 17))
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .accessibilityIdentifier("settings.notifications.enabled")
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled { requestNotificationPermission() }
                    }
                }
                Text("Local notifications while Paseo is open or recently backgrounded. True push while the app is closed is not available without a relay.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .padding(.leading, 16)
                RowGroup {
                    HStack(spacing: 12) {
                        Label("Sound cue", systemImage: "waveform")
                            .font(.system(size: 17))
                        Spacer(minLength: 8)
                        Picker("Sound cue", selection: $soundCueLevel) {
                            ForEach(SoundCueLevel.allCases, id: \.rawValue) { level in
                                Text(level.title).tag(level.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .accessibilityIdentifier("settings.notifications.soundCue")
                }
                Text("Play a cue when a task finishes or is blocked.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .padding(.leading, 16)
                sectionLabel("Chat")
                RowGroup {
                    HStack(spacing: 12) {
                        Text("Chat display")
                            .font(.system(size: 17))
                        Spacer(minLength: 8)
                        Menu {
                            ForEach(ChatDisplayMode.allCases, id: \.self) { option in
                                Button {
                                    Haptics.selection()
                                    chatDisplay = option.rawValue
                                } label: {
                                    Label(
                                        option.label,
                                        systemImage: chatDisplay == option.rawValue
                                            ? "checkmark" : "circle"
                                    )
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(chatDisplayMode.label)
                                    .font(.system(size: 15))
                                    .foregroundStyle(ClaudePalette.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ClaudePalette.secondary)
                            }
                        }
                        .accessibilityLabel("Chat display, currently \(chatDisplayMode.label)")
                        .accessibilityIdentifier("settings.chatDisplay")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    Divider().padding(.leading, 16)
                    Toggle(isOn: $alwaysExpandReasoning) {
                        Text("Always expand reasoning")
                            .font(.system(size: 17))
                    }
                    .tint(.blue)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .accessibilityIdentifier("settings.alwaysExpandReasoning")
                    Divider().padding(.leading, 16)
                    HStack(spacing: 12) {
                        Text("When the agent is running")
                            .font(.system(size: 17))
                        Spacer(minLength: 8)
                        Menu {
                            ForEach(DefaultSendBehavior.allCases, id: \.self) { option in
                                Button {
                                    Haptics.selection()
                                    defaultSend = option.rawValue
                                } label: {
                                    Label(
                                        option.label,
                                        systemImage: defaultSendBehavior == option ? "checkmark" : "circle"
                                    )
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(defaultSendBehavior.label)
                                    .font(.system(size: 15))
                                    .foregroundStyle(ClaudePalette.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ClaudePalette.secondary)
                            }
                        }
                        .accessibilityLabel("Default send behavior, currently \(defaultSendBehavior.label)")
                        .accessibilityIdentifier("settings.defaultsend")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                }
                Text("Applies when you tap send while a turn is running. Long-press on send does the opposite between Steer and Queue.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .padding(.leading, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private func appearancePreview(_ choice: ClaudeAppearance) -> some View {
        switch choice {
        case .light:
            ZStack {
                Color(white: 0.97)
                previewBars(dark: true)
            }
            .clipShape(.rect(cornerRadius: 14))
            .frame(maxWidth: .infinity)
        case .dark:
            ZStack {
                Color(white: 0.08)
                previewBars(dark: false)
            }
            .clipShape(.rect(cornerRadius: 14))
            .frame(maxWidth: .infinity)
        case .system:
            ZStack {
                HStack(spacing: 0) {
                    Color(white: 0.97)
                    Color(white: 0.08)
                }
                previewBars(dark: true)
            }
            .clipShape(.rect(cornerRadius: 14))
            .frame(maxWidth: .infinity)
        case .pureBlack:
            ZStack {
                Color(white: 0)
                previewBars(dark: false)
            }
            .clipShape(.rect(cornerRadius: 14))
            .frame(maxWidth: .infinity)
        }
    }

    /// A labeled menu row for an S/M/L/XL ladder (used by both font-size rows).
    @ViewBuilder private func scaleMenuRow<Option: CaseIterable & RawRepresentable & Equatable>(
        _ title: String, symbol: String, options: Option.AllCases, current: String,
        identifier: String,
        onSelect: @escaping (Option) -> Void
    ) -> some View where Option.RawValue == String {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .frame(width: 24)
                .foregroundStyle(ClaudePalette.ink.opacity(0.75))
            Text(title)
                .font(.system(size: 17))
            Spacer(minLength: 8)
            Menu {
                ForEach(Array(options), id: \.rawValue) { option in
                    Button {
                        Haptics.selection()
                        onSelect(option)
                    } label: {
                        Label(
                            option.rawValue,
                            systemImage: current == option.rawValue ? "checkmark" : "circle")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(current)
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ClaudePalette.secondary)
                }
            }
            .accessibilityLabel("\(title), currently \(current)")
            .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func previewBars(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule()
                .fill((dark ? Color.black : Color.white).opacity(dark ? 0.8 : 0.5))
                .frame(width: 40, height: 5)
            Capsule()
                .fill((dark ? Color.black : Color.white).opacity(dark ? 0.4 : 0.3))
                .frame(width: 26, height: 5)
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    // MARK: Host pages

    private enum MetadataMode { case automatic, manual }

    private var metadataMode: MetadataMode {
        (session.hostSettings.config?.metadataGeneration?.providers.isEmpty ?? true)
            ? .automatic : .manual
    }

    private var configuredMetadataProviders: [DaemonConfig.StructuredGenerationProvider] {
        session.hostSettings.config?.metadataGeneration?.providers ?? []
    }

    private var metadataModelLabel: String {
        guard let first = configuredMetadataProviders.first else { return "Choose a model…" }
        if let model = first.model, !model.isEmpty { return "\(first.provider) / \(model)" }
        return "\(first.provider) / provider default"
    }

    private var projectCountLine: String {
        let count = session.workspaceDirectory.groups.count
        return count == 1 ? "1 project" : "\(count) projects"
    }

    // MARK: Overview

    private var overviewPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Connection")
                RowGroup {
                    connectionRow
                    rowDivider
                    valueRow(
                        "Server ID", value: session.serverInfo?.serverId ?? "Not connected", mono: true)
                    rowDivider
                    valueRow("Daemon version", value: session.serverInfo?.version ?? "Unknown")
                    rowDivider
                    valueRow(
                        "Protocol version",
                        value: session.serverInfo?.protocolVersion.map(String.init) ?? "Unknown")
                }
                Text(
                    "The badge color below is this device's own identity for the host; the daemon keeps the authoritative name. This client connects to one daemon at a time."
                )
                .font(.system(size: 13))
                .foregroundStyle(ClaudePalette.secondary)
                .padding(.leading, 16)
                appearanceCard
                dangerZone
                sectionLabel("Advanced")
                RowGroup {
                    configToggleRow(
                        "Terminal agent hooks",
                        isOn: configBinding(
                            get: { $0.enableTerminalAgentHooks },
                            set: { $0.enableTerminalAgentHooks = $1 }))
                    rowDivider
                    configToggleRow(
                        "Usage tracking",
                        isOn: configBinding(
                            get: { $0.usage?.enabled ?? false },
                            set: { $0.usage = .init(enabled: $1) }))
                }
                Text(
                    "Unset toggles show as off. Changes apply immediately; the effective config comes back from the daemon."
                )
                .font(.system(size: 13))
                .foregroundStyle(ClaudePalette.secondary)
                .padding(.leading, 16)
                if let error = session.hostSettings.error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .padding(.leading, 16)
                }
                RowGroup {
                    disconnectButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    /// Danger zone (M16): Remove this host, upstream wording. The removal itself (forget +
    /// Keychain clear + switching) is `AppModel.removeHost` behind `hostSwitch.forgetHost`.
    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionLabel("Danger zone")
            RowGroup {
                Button {
                    confirmRemoveHost = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remove host")
                                .font(.system(size: 17))
                                .foregroundStyle(ClaudePalette.failureInk)
                            Text("Removes this host and its saved connections from this device")
                                .font(.system(size: 12))
                                .foregroundStyle(ClaudePalette.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.host.removeHost")
            }
        }
        .confirmationDialog(
            "Remove host",
            isPresented: $confirmRemoveHost,
            titleVisibility: .visible
        ) {
            Button("Remove host", role: .destructive) {
                if let entry = hostSwitch?.currentEntry {
                    hostSwitch?.forgetHost(entry.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(hostSwitch?.currentEntry?.label ?? "this host")? This will delete its saved connections.")
        }
    }

    /// Per-host appearance (M16): identity color + sidebar badge, upstream's card.
    @ViewBuilder private var appearanceCard: some View {
        if let context = hostSwitch, let entry = context.currentEntry {
            sectionLabel("Appearance")
            RowGroup {
                HStack(spacing: 12) {
                    Text("Color")
                        .font(.system(size: 17))
                    Spacer(minLength: 8)
                    colorSwatches(context: context, entry: entry)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                rowDivider
                HStack(spacing: 12) {
                    Text("Sidebar badge")
                        .font(.system(size: 17))
                    Spacer(minLength: 8)
                    Picker("Sidebar badge", selection: badgeBinding(context: context, entry: entry)) {
                        ForEach(HostBadgeDisplay.allCases, id: \.rawValue) { display in
                            Text(display.title).tag(display.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
            }
        }
    }

    private func colorSwatches(context: HostSwitchContext, entry: HostSwitchEntry) -> some View {
        let appearance = context.appearance(for: entry.id)
        return HStack(spacing: 8) {
            ForEach(HostColor.allCases, id: \.rawValue) { color in
                Button {
                    var next = appearance
                    next.color = color
                    context.setAppearance(next, for: entry.id)
                } label: {
                    Circle()
                        .fill(color == .none ? ClaudePalette.chip : color.swiftUIColor)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle()
                                .stroke(
                                    appearance.color == color ? ClaudePalette.ink : ClaudePalette.cardBorder,
                                    lineWidth: appearance.color == color ? 2 : 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.title)
            }
        }
    }

    private func badgeBinding(context: HostSwitchContext, entry: HostSwitchEntry) -> Binding<String> {
        Binding(
            get: { context.appearance(for: entry.id).badgeDisplay.rawValue },
            set: { raw in
                var next = context.appearance(for: entry.id)
                next.badgeDisplay = HostBadgeDisplay(rawValue: raw) ?? .name
                context.setAppearance(next, for: entry.id)
            })
    }

    @ViewBuilder private var connectionRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Connection")
                    .font(.system(size: 17))
                Text(session.serverInfo?.hostname ?? "Paseo daemon")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                PaseoStatusDot(kind: connectionKind(session.connection))
                Text(connectionLabel(session.connection))
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    @ViewBuilder private var disconnectButton: some View {
        Button {
            confirmDisconnect = true
        } label: {
            HStack {
                Text("Disconnect")
                    .font(.system(size: 17))
                    .foregroundStyle(ClaudePalette.failureInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Disconnect")
    }

    // MARK: Agents

    private var agentsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Tools")
                RowGroup {
                    configToggleRow(
                        "Enable Paseo tools",
                        subtitle: "Agents will be able to manage worktrees, agents and schedules",
                        isOn: configBinding(
                            get: { $0.mcp?.injectIntoAgents ?? true },
                            set: { $0.mcp = .init(injectIntoAgents: $1) }))
                    rowDivider
                    configToggleRow(
                        "Browser tools",
                        subtitle: "Agents can control the in-app browser, including logged-in state",
                        isOn: configBinding(
                            get: { $0.browserTools?.enabled ?? false },
                            set: { $0.browserTools = .init(enabled: $1) }))
                }
                sectionLabel("System prompt")
                RowGroup {
                    promptCard(
                        title: "Appended to every agent's system prompt",
                        placeholder: "What every agent should always know…",
                        draft: appendPromptBinding,
                        focused: $appendPromptFocused,
                        saving: appendPromptSaving,
                        dirty: appendPromptDirty) {
                            saveAppendPrompt()
                        }
                }
                if let skills = session.hostSettings.config?.skillsSelection {
                    sectionLabel("Orchestration skills")
                    RowGroup {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Skills")
                                    .font(.system(size: 17))
                                Text("Installed on the host for orchestrating agents")
                                    .font(.system(size: 13))
                                    .foregroundStyle(ClaudePalette.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(skills.label)
                                .font(.system(size: 15))
                                .foregroundStyle(ClaudePalette.secondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                    }
                }
                sectionLabel("Restart recovery")
                RowGroup {
                    configToggleRow(
                        "Resume agents after restart",
                        subtitle: "Agents found mid-task are resumed with this prompt appended",
                        isOn: configBinding(
                            get: { $0.resumeOnStartup ?? false },
                            set: { $0.resumeOnStartup = $1 }))
                    if session.hostSettings.config?.resumeOnStartup == true {
                        rowDivider
                        promptCard(
                            title: "Appended to the resume prompt",
                            placeholder: "What a resumed agent should know…",
                            draft: resumePromptBinding,
                            focused: $resumePromptFocused,
                            saving: resumePromptSaving,
                            dirty: resumePromptDirty) {
                                saveResumePrompt()
                            }
                    }
                }
                sectionLabel("Idle agents")
                RowGroup {
                    configToggleRow(
                        "Release idle agents",
                        subtitle: "Free up memory after an hour of inactivity",
                        isOn: configBinding(
                            get: { $0.idleRuntimeCleanup ?? false },
                            set: { $0.idleRuntimeCleanup = $1 }))
                }
                AgentProfilesSection(session: session)
                if let error = session.hostSettings.error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .padding(.leading, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") {
                        if appendPromptFocused, appendPromptDirty { saveAppendPrompt() }
                        if resumePromptFocused, resumePromptDirty { saveResumePrompt() }
                        appendPromptFocused = false
                        resumePromptFocused = false
                    }
                }
            }
        }
    }

    private var appendPromptBinding: Binding<String> {
        Binding(
            get: { appendPromptDraft ?? session.hostSettings.config?.appendSystemPrompt ?? "" },
            set: { appendPromptDraft = $0 })
    }

    private var appendPromptDirty: Bool {
        guard let draft = appendPromptDraft else { return false }
        return draft != (session.hostSettings.config?.appendSystemPrompt ?? "")
    }

    private func saveAppendPrompt() {
        guard let draft = appendPromptDraft else { return }
        Haptics.selection()
        appendPromptSaving = true
        Task {
            var patch = DaemonConfigPatch()
            patch.appendSystemPrompt = draft
            let ok = await session.hostSettings.save(patch)
            appendPromptSaving = false
            if ok { appendPromptDraft = nil }
            appendPromptFocused = false
        }
    }

    private var resumePromptBinding: Binding<String> {
        Binding(
            get: { resumePromptDraft ?? session.hostSettings.config?.resumePrompt ?? "" },
            set: { resumePromptDraft = $0 })
    }

    private var resumePromptDirty: Bool {
        guard let draft = resumePromptDraft else { return false }
        return draft != (session.hostSettings.config?.resumePrompt ?? "")
    }

    private func saveResumePrompt() {
        guard let draft = resumePromptDraft else { return }
        Haptics.selection()
        resumePromptSaving = true
        Task {
            var patch = DaemonConfigPatch()
            patch.resumePrompt = draft
            let ok = await session.hostSettings.save(patch)
            resumePromptSaving = false
            if ok { resumePromptDraft = nil }
            resumePromptFocused = false
        }
    }

    @ViewBuilder private func promptCard(
        title: String,
        placeholder: String,
        draft: Binding<String>,
        focused: FocusState<Bool>.Binding,
        saving: Bool,
        dirty: Bool,
        onSave: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(ClaudePalette.secondary)
            TextField(placeholder, text: draft, axis: .vertical)
                .font(typography.mono(12.5, relativeTo: .footnote))
                .lineLimit(3...12)
                .padding(12)
                .background(ClaudePalette.background.opacity(0.55), in: .rect(cornerRadius: 12))
                .focused(focused)
            if dirty {
                HStack {
                    Spacer(minLength: 8)
                    Button(action: onSave) {
                        Text(saving ? "Saving…" : "Done")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .disabled(saving)
                }
            }
        }
        .padding(16)
    }

    // MARK: Metadata

    private var metadataPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Metadata generation")
                RowGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Model selection")
                                .font(.system(size: 17))
                            Spacer(minLength: 8)
                            Text(metadataMode == .automatic ? "Automatic" : "Manual")
                                .font(.system(size: 15))
                                .foregroundStyle(ClaudePalette.secondary)
                        }
                        HStack(spacing: 8) {
                            metadataModeChip(.automatic, "Automatic")
                            metadataModeChip(.manual, "Manual")
                        }
                    }
                    .padding(16)
                }
                if metadataMode == .manual {
                    sectionLabel("Model")
                    RowGroup {
                        Button {
                            Haptics.selection()
                            open(.metadataModel)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Model")
                                        .font(.system(size: 17))
                                    Text(metadataModelLabel)
                                        .font(.system(size: 13))
                                        .foregroundStyle(ClaudePalette.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 15))
                                    .foregroundStyle(ClaudePalette.secondary)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 60)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.metadata.model")
                    }
                }
                Text(
                    "Used for titles, branch names, commit messages and pull requests drafted by the host."
                )
                .font(.system(size: 13))
                .foregroundStyle(ClaudePalette.secondary)
                .padding(.leading, 16)
                if let error = session.hostSettings.error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .padding(.leading, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func metadataModeChip(_ mode: MetadataMode, _ title: String) -> some View {
        let isSelected = metadataMode == mode
        return Button {
            Haptics.selection()
            switch mode {
            case .automatic:
                save { $0.metadataGeneration = .init(providers: []) }
            case .manual:
                open(.metadataModel)
            }
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? ClaudePalette.background : ClaudePalette.ink)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(isSelected ? ClaudePalette.ink : ClaudePalette.chip, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.metadata.mode." + title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .disabled(session.hostSettings.config == nil || session.hostSettings.isSaving)
    }

    private func isMetadataModelSelected(provider: String, modelId: String) -> Bool {
        guard let first = configuredMetadataProviders.first, first.provider == provider else {
            return false
        }
        return first.model == modelId
    }

    private func selectMetadataModel(provider: String, modelId: String) {
        let tail = Array(configuredMetadataProviders.dropFirst())
        save {
            $0.metadataGeneration = .init(
                providers: [.init(provider: provider, model: modelId)] + tail)
        }
        open(.metadata)
    }

    private var metadataModelPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if session.agentControl.phase == .loading,
                    session.agentControl.providers.isEmpty
                {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    Text("Loading providers…")
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondary)
                        .frame(maxWidth: .infinity)
                } else if session.agentControl.readyProviders.isEmpty {
                    Text("No usable models on this host. Enable a provider on the Providers page first.")
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondary)
                        .padding(.top, 32)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(session.agentControl.readyProviders) { provider in
                        let models = session.agentControl.models(forProvider: provider.provider)
                        if !models.isEmpty {
                            sectionLabel(provider.label ?? provider.provider)
                            RowGroup {
                                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                                    SheetRow(
                                        title: model.label, detail: model.description,
                                        checked: isMetadataModelSelected(
                                            provider: provider.provider, modelId: model.id),
                                        badge: model.isDefault == true ? "Default" : nil
                                    ) {
                                        Haptics.selection()
                                        selectMetadataModel(provider: provider.provider, modelId: model.id)
                                    }
                                    if index < models.count - 1 { rowDivider }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if session.agentControl.phase == .idle {
                Task { await session.agentControl.loadCatalog() }
            }
        }
    }

    // MARK: Workspaces

    private var workspacesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Workspaces")
                RowGroup {
                    configToggleRow(
                        "Auto-archive after merge",
                        subtitle:
                            "Automatically archive clean Paseo workspaces after their pull request is merged",
                        isOn: configBinding(
                            get: { $0.autoArchiveAfterMerge },
                            set: { $0.autoArchiveAfterMerge = $1 }))
                }
                if let error = session.hostSettings.error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .padding(.leading, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Projects

    private var projectsPage: some View {
        let counts = Dictionary(
            session.workspaceDirectory.groups.map { ($0.project.projectId, $0.workspaces.count) },
            uniquingKeysWith: +)
        let projects = session.workspaceDirectory.groups.map(\.project).sorted {
            ($0.projectCustomName ?? $0.projectDisplayName).localizedCaseInsensitiveCompare(
                $1.projectCustomName ?? $1.projectDisplayName) == .orderedAscending
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("On this host")
                if projects.isEmpty {
                    Text("No projects on this host yet.")
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondary)
                        .padding(.leading, 16)
                } else {
                    RowGroup {
                        ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                            projectRow(project, count: counts[project.id] ?? 0) {
                                projectPage = project
                            }
                            if index < projects.count - 1 { rowDivider }
                        }
                    }
                }
                Text(
                    "Removing a project unregisters it on this host. Files on disk are not changed."
                )
                .font(.system(size: 13))
                .foregroundStyle(ClaudePalette.secondary)
                .padding(.leading, 16)
                if let error = session.workspaceDirectory.actionError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .padding(.leading, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $projectPage) { project in
            ProjectSettingsView(session: session, project: project)
        }
        .confirmationDialog(
            "Remove project?",
            isPresented: Binding(
                get: { confirmRemoveProject != nil },
                set: { if !$0 { confirmRemoveProject = nil } })
        ) {
            Button("Remove", role: .destructive) {
                guard let project = confirmRemoveProject else { return }
                confirmRemoveProject = nil
                Task { _ = await session.workspaceDirectory.removeProject(project.projectId) }
            }
            Button("Cancel", role: .cancel) { confirmRemoveProject = nil }
        } message: {
            Text(
                "The project and its workspaces will be unregistered on this host. Files on disk will not be changed."
            )
        }
    }

    private func projectRow(
        _ project: WorkspaceProjectDescriptor, count: Int, open: @escaping () -> Void
    ) -> some View {
        let title = project.projectCustomName ?? project.projectDisplayName
        return HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 17))
                            .lineLimit(1)
                        Text(project.projectRootPath)
                            .font(typography.mono(12, relativeTo: .footnote))
                            .foregroundStyle(ClaudePalette.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Text(count == 1 ? "1 workspace" : "\(count) workspaces")
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondary)
                        .lineLimit(1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(title) project settings")
            if session.workspaceDirectory.supportsProjectRemove {
                Menu {
                    Button("Remove project", role: .destructive) {
                        confirmRemoveProject = project
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(ClaudePalette.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Project actions")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
    }

    // MARK: Shared save helpers

    private func configBinding(
        get: @escaping (DaemonConfig) -> Bool,
        set: @escaping (inout DaemonConfigPatch, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard let config = session.hostSettings.config else { return false }
                return get(config)
            },
            set: { newValue in
                save { patch in set(&patch, newValue) }
            })
    }

    private func save(_ build: (inout DaemonConfigPatch) -> Void) {
        var patch = DaemonConfigPatch()
        build(&patch)
        Haptics.selection()
        Task { await session.hostSettings.save(patch) }
    }

    @ViewBuilder private func configToggleRow(
        _ title: String, subtitle: String? = nil, isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(.blue)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .disabled(session.hostSettings.isSaving || session.hostSettings.config == nil)
        .accessibilityIdentifier("settings.config." + title)
    }

    // MARK: Providers

    private var providersPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let actionError = session.agentControl.actionError {
                    Text(actionError)
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .padding(.leading, 16)
                }
                if session.agentControl.providers.isEmpty {
                    if session.agentControl.phase == .loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                        Text("Loading providers…")
                            .font(.system(size: 15))
                            .foregroundStyle(ClaudePalette.secondary)
                            .frame(maxWidth: .infinity)
                    } else if case .failed(let message) = session.agentControl.phase {
                        Text(message)
                            .font(.system(size: 15))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .padding(.top, 32)
                    } else {
                        Text("No providers reported by this host.")
                            .font(.system(size: 15))
                            .foregroundStyle(ClaudePalette.secondary)
                            .padding(.top, 32)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    RowGroup {
                        ForEach(Array(session.agentControl.providers.enumerated()), id: \.element.id) {
                            index, provider in
                            providerRow(provider)
                            if index < session.agentControl.providers.count - 1 { rowDivider }
                        }
                    }
                    Text("Enable switches are stored in the daemon's config; status and models come from the host's catalogue.")
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudePalette.secondary)
                        .padding(.leading, 16)
                    if session.hostSettings.config == nil {
                        Text("Daemon config is unavailable — pull to refresh on a Host page to enable toggles.")
                            .font(.system(size: 13))
                            .foregroundStyle(ClaudePalette.secondary)
                            .padding(.leading, 16)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if session.agentControl.phase == .idle {
                Task { await session.agentControl.loadCatalog() }
            }
        }
    }

    private func providerRow(_ provider: ProviderSnapshotEntry) -> some View {
        let modelCount = provider.models?.count ?? 0
        let countLine = "\(modelCount) \(modelCount == 1 ? "model" : "models")"
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Button {
                    Haptics.selection()
                    providerSheetID = provider.provider
                } label: {
                    HStack(spacing: 12) {
                        PaseoStatusDot(kind: dotKind(provider))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(provider.label ?? provider.provider)
                                .font(.system(size: 17))
                                .lineLimit(1)
                            Text(providerDetailLine(provider, countLine: countLine))
                                .font(.system(size: 13))
                                .foregroundStyle(ClaudePalette.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(provider.label ?? provider.provider), \(providerDetailLine(provider, countLine: countLine)), opens provider settings")
                .accessibilityIdentifier("settings.providers.open.\(provider.provider)")
                Spacer(minLength: 8)
                if session.hostSettings.config != nil {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { session.hostSettings.isProviderEnabled(provider.provider) },
                            set: { newValue in
                                save { patch in
                                    patch.providers = [provider.provider: .init(enabled: newValue)]
                                }
                            })
                    )
                    .labelsHidden()
                    .disabled(session.hostSettings.isSaving)
                    .accessibilityLabel("Enable \(provider.label ?? provider.provider)")
                }
            }
            if let error = provider.error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .lineLimit(2)
                    .padding(.leading, 32)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func providerDetailLine(_ provider: ProviderSnapshotEntry, countLine: String) -> String {
        if session.hostSettings.config != nil,
            !session.hostSettings.isProviderEnabled(provider.provider)
        {
            return "\(countLine) · Disabled"
        }
        switch provider.status {
        case .ready: "\(countLine) · Ready"
        case .loading: "\(countLine) · Loading"
        case .error: "\(countLine) · Error"
        case .unavailable: "\(countLine) · Not available"
        case .unknown(let raw): raw.isEmpty ? countLine : "\(countLine) · \(raw)"
        }
    }

    private func statusKind(_ status: ProviderStatus) -> PaseoStatusDot.Kind {
        switch status {
        case .ready: .done
        case .loading: .running
        case .error: .failed
        case .unavailable: .idle
        case .unknown: .idle
        }
    }

    /// Hollow dot when the provider is config-disabled; otherwise its catalogue status.
    private func dotKind(_ provider: ProviderSnapshotEntry) -> PaseoStatusDot.Kind {
        if session.hostSettings.config != nil, !session.hostSettings.isProviderEnabled(provider.provider) {
            return .idle
        }
        return statusKind(provider.status)
    }

    // MARK: About

    private var aboutPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paseo Client")
                        .font(typography.serif(28))
                        .foregroundStyle(ClaudePalette.ink)
                    Text(versionLine)
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondary)
                    Text("A native client for the Paseo daemon.")
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondary)
                }
                .padding(.top, 8)
                sectionLabel("This host")
                RowGroup {
                    valueRow("Host", value: session.serverInfo?.hostname ?? "Not connected")
                    rowDivider
                    valueRow("Daemon version", value: session.serverInfo?.version ?? "Unknown")
                }
                sectionLabel("Links")
                RowGroup {
                    linkRow(
                        "Paseo daemon", detail: "github.com/getpaseo/paseo",
                        url: URL(string: "https://github.com/getpaseo/paseo"))
                    rowDivider
                    linkRow(
                        "Paseo Client", detail: "github.com/Wiselfx/Paseo-client",
                        url: URL(string: "https://github.com/Wiselfx/Paseo-client"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private func linkRow(_ title: String, detail: String, url: URL?) -> some View {
        Button {
            guard let url else { return }
            openURL(url)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17))
                    Text(detail)
                        .font(typography.mono(12, relativeTo: .footnote))
                        .foregroundStyle(ClaudePalette.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(ClaudePalette.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), opens in browser")
    }

    // MARK: Shared bits

    private var rowDivider: some View {
        Divider().padding(.leading, 16).padding(.trailing, 16)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15))
            .foregroundStyle(ClaudePalette.secondary)
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }

    private func settingsRow(
        _ destination: Page, symbol: String, value: String = "", chevron: Bool = true
    ) -> some View {
        Button {
            Haptics.selection()
            open(destination)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .light))
                    .frame(width: 26)
                    .foregroundStyle(ClaudePalette.ink.opacity(0.75))
                Text(destination.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !value.isEmpty {
                    Text(value)
                        .foregroundStyle(ClaudePalette.secondary)
                        .lineLimit(1)
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15))
                        .foregroundStyle(ClaudePalette.secondary)
                }
            }
            .font(.system(size: 17))
            .foregroundStyle(ClaudePalette.ink)
            .padding(.horizontal, 16)
            .frame(height: 51)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.route." + destination.rawValue)
    }

    @ViewBuilder private func valueRow(_ title: String, value: String, mono: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 17))
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? typography.mono(13, relativeTo: .footnote) : .system(size: 15))
                .foregroundStyle(ClaudePalette.secondary)
                .lineLimit(1)
                .truncationMode(mono ? .middle : .tail)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .frame(height: 51)
    }

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
