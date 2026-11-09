#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The full Settings screen: General, Host, Providers and About. ClaudeUI's settings layout
/// (glass-circle back/close, pushed pages, grouped rows) wired to the live session and the app's
/// `@AppStorage` keys. Opened from the sidebar avatar.
struct PaseoSettingsView: View {
    let session: HostSession
    var onDisconnect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PaseoSettingsKeys.appearance) private var appearance = ClaudeAppearance.system.rawValue
    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""
    @AppStorage(PaseoSettingsKeys.haptics) private var haptics = true
    @AppStorage(PaseoSettingsKeys.mascot) private var mascot = true
    @State private var page: Page?
    @State private var confirmDisconnect = false

    private let typography = ClaudeTypography()

    enum Page: String, CaseIterable, Identifiable, Equatable {
        case general
        case host
        case providers
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .host: "Host"
            case .providers: "Providers"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .host: "server.rack"
            case .providers: "cpu"
            case .about: "info.circle"
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
                if page == .host {
                    Button {
                        Task { await session.hostSettings.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 19, weight: .light))
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(in: .circle)
                    .accessibilityLabel("Refresh host settings")
                } else if page == .providers {
                    Button {
                        Task { await session.agentControl.refreshCatalog() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 19, weight: .light))
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(in: .circle)
                    .accessibilityLabel("Refresh providers")
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
                    settingsRow(
                        .host, symbol: Page.host.symbol,
                        value: session.serverInfo?.hostname ?? "Paseo daemon")
                    rowDivider
                    settingsRow(
                        .providers, symbol: Page.providers.symbol,
                        value: providersSummary)
                }
                sectionLabel("About")
                RowGroup {
                    settingsRow(.about, symbol: Page.about.symbol, value: versionLine)
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
        case .host: hostPage
        case .providers: providersPage
        case .about: aboutPage
        }
    }

    // MARK: General

    private var generalPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Appearance")
                RowGroup {
                    HStack(spacing: 10) {
                        ForEach([ClaudeAppearance.light, .dark, .system], id: \.self) { choice in
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
                                            appearance == choice.rawValue ? .blue : ClaudePalette.secondary)
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
        }
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

    // MARK: Host

    private var hostPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Connection")
                RowGroup {
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
                    rowDivider
                    valueRow("Server ID", value: session.serverInfo?.serverId ?? "Not connected", mono: true)
                    rowDivider
                    valueRow("Daemon version", value: session.serverInfo?.version ?? "Unknown")
                }
                sectionLabel("Daemon config")
                RowGroup {
                    configToggleRow(
                        "Auto-archive after merge",
                        isOn: configBinding(
                            get: { $0.autoArchiveAfterMerge }, set: { $0.autoArchiveAfterMerge = $1 }))
                    rowDivider
                    configToggleRow(
                        "Terminal agent hooks",
                        isOn: configBinding(
                            get: { $0.enableTerminalAgentHooks },
                            set: { $0.enableTerminalAgentHooks = $1 }))
                    rowDivider
                    configToggleRow(
                        "Resume on startup",
                        isOn: configBinding(
                            get: { $0.resumeOnStartup ?? false },
                            set: { $0.resumeOnStartup = $1 }))
                    rowDivider
                    configToggleRow(
                        "Idle runtime cleanup",
                        isOn: configBinding(
                            get: { $0.idleRuntimeCleanup ?? false },
                            set: { $0.idleRuntimeCleanup = $1 }))
                    rowDivider
                    configToggleRow(
                        "Relay for remote pairing",
                        isOn: configBinding(
                            get: { $0.relay?.enabled ?? false },
                            set: { $0.relay = .init(enabled: $1) }))
                    rowDivider
                    configToggleRow(
                        "Require protected security",
                        isOn: configBinding(
                            get: { $0.relay?.requireProtectedSecurity ?? false },
                            set: { $0.relay = .init(requireProtectedSecurity: $1) }))
                    rowDivider
                    configToggleRow(
                        "Usage tracking",
                        isOn: configBinding(
                            get: { $0.usage?.enabled ?? false }, set: { $0.usage = .init(enabled: $1) }))
                    rowDivider
                    configToggleRow(
                        "Browser tools",
                        isOn: configBinding(
                            get: { $0.browserTools?.enabled ?? false },
                            set: { $0.browserTools = .init(enabled: $1) }))
                    rowDivider
                    configToggleRow(
                        "Inject MCP into agents",
                        isOn: configBinding(
                            get: { $0.mcp?.injectIntoAgents ?? false },
                            set: { $0.mcp = .init(injectIntoAgents: $1) }))
                    rowDivider
                    configToggleRow(
                        "Plugins enabled",
                        isOn: configBinding(
                            get: { $0.pluginsEnabled ?? false },
                            set: { $0.pluginsEnabled = $1 }))
                }
                if let prompt = session.hostSettings.config?.appendSystemPrompt,
                    !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    Text("Append system prompt")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ClaudePalette.secondary)
                        .padding(.leading, 16)
                    Text(prompt)
                        .font(typography.mono(12, relativeTo: .footnote))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(ClaudePalette.panel, in: .rect(cornerRadius: 16))
                }
                if session.hostSettings.supportsProfiles {
                    RowGroup {
                        valueRow(
                            "Agent profiles",
                            value: "\(session.hostSettings.profiles.count)")
                    }
                }
                Text("Unset toggles show as off. Changes apply immediately; the effective config comes back from the daemon.")
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

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

    @ViewBuilder private func configToggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(.system(size: 17))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .disabled(session.hostSettings.isSaving || session.hostSettings.config == nil)
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
                        Text("Daemon config is unavailable — pull to refresh on the Host page to enable toggles.")
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

    private var providersSummary: String {
        let count = session.agentControl.providers.count
        return "\(count) provider\(count == 1 ? "" : "s")"
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
