#if canImport(UIKit)
import SwiftUI

/// Where is your daemon, and what's its password. The app does the connecting; this view only
/// collects the details and shows the outcome. Saved hosts come first (tap to connect, swipe to
/// forget, rename), then the direct form (host / port / password / TLS / Advanced URI).
public struct ConnectView: View {
    public enum Status: Equatable {
        case idle
        case connecting
        case failed(String)
    }

    @Binding var host: String
    @Binding var port: String
    @Binding var password: String
    @Binding var useTLS: Bool
    @Binding var connectionURI: String
    var status: Status
    /// Every saved daemon, most recent first. Provided by the app.
    var hosts: [HostSwitchEntry]
    var onConnect: () -> Void
    var onConnectSaved: (UUID) -> Void
    var onForgetSaved: (UUID) -> Void
    var onRenameSaved: (UUID, String) -> Void

    @State private var showAddForm: Bool
    @State private var showAdvanced = false
    @State private var renameTarget: HostSwitchEntry?
    @State private var renameText = ""
    @State private var forgetTarget: HostSwitchEntry?


    public init(
        host: Binding<String>, port: Binding<String>, password: Binding<String>,
        useTLS: Binding<Bool>, connectionURI: Binding<String>, status: Status,
        hosts: [HostSwitchEntry], onConnect: @escaping () -> Void,
        onConnectSaved: @escaping (UUID) -> Void,
        onForgetSaved: @escaping (UUID) -> Void,
        onRenameSaved: @escaping (UUID, String) -> Void
    ) {
        _host = host
        _port = port
        _password = password
        _useTLS = useTLS
        _connectionURI = connectionURI
        self.status = status
        self.hosts = hosts
        self.onConnect = onConnect
        self.onConnectSaved = onConnectSaved
        self.onForgetSaved = onForgetSaved
        self.onRenameSaved = onRenameSaved
        let failed: Bool
        if case .failed = status { failed = true } else { failed = false }
        _showAddForm = State(initialValue: hosts.isEmpty || failed)
    }

    private var connecting: Bool { status == .connecting }
    private var uriState: ConnectionURI.Result { ConnectionURI.parse(connectionURI) }
    private var trimmedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var portNumber: Int? {
        guard let value = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
            (1...65535).contains(value)
        else { return nil }
        return value
    }
    private var portError: String? {
        let trimmed = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, portNumber == nil else { return nil }
        return "Port must be a number between 1 and 65535."
    }
    private var uriError: String? { ConnectionURI.validationError(connectionURI) }
    private var hostError: String? {
        trimmedHost.contains(" ") ? "The host can't contain spaces." : nil
    }
    private var canConnect: Bool {
        guard !connecting else { return false }
        switch uriState {
        case .valid: return true
        case .invalid: return false
        case .empty:
            return !trimmedHost.isEmpty && hostError == nil && portNumber != nil
        }
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer(minLength: 12)
                VStack(spacing: 6) {
                    Text("Paseo").font(.paseo(.largeTitle))
                    Text("Connect to your host")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                }
                Group {
                    if showAddForm || hosts.isEmpty {
                        directForm
                    } else {
                        savedHostsList
                    }
                }
                if case .failed(let message) = status {
                    Text(message)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.failureInk)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
                if showAddForm || hosts.isEmpty { connectButton }
                Spacer()
                Text(
                    "Use your machine's LAN or Tailscale address. Set a password with `paseo daemon set-password`."
                )
                .font(.paseo(.caption))
                .foregroundStyle(Palette.captionInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
            }
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.ink)
        .onChange(of: status) { _, new in
            // A failed connect lands on the form with that host preselected and Retry in reach.
            if case .failed = new {
                Haptics.failure()
                showAddForm = true
            }
        }
        .sheet(item: $renameTarget) { target in renameSheet(target) }
        .confirmationDialog(
            "Forget \(forgetTarget?.label ?? "this host")?",
            isPresented: Binding(
                get: { forgetTarget != nil }, set: { if !$0 { forgetTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Forget host", role: .destructive) {
                if let id = forgetTarget?.id { onForgetSaved(id) }
                forgetTarget = nil
            }
            Button("Cancel", role: .cancel) { forgetTarget = nil }
        } message: {
            Text("The password stored on this device for this host is removed too. The host itself isn't changed.")
        }
    }

    // MARK: Saved hosts

    private var savedHostsList: some View {
        List {
            ForEach(hosts) { host in
                ListRow(
                    title: host.label,
                    subtitle: host.urlLine,
                    systemImage: host.isCurrent ? "checkmark.circle.fill" : "desktopcomputer",
                    accessory: connecting ? ListRow.Accessory.progress : ListRow.Accessory.chevron,
                    action: {
                        Haptics.selection()
                        onConnectSaved(host.id)
                    }
                )
                .disabled(connecting)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        forgetTarget = host
                    } label: {
                        Label("Forget", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        renameText = host.label
                        renameTarget = host
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        forgetTarget = host
                    } label: {
                        Label("Forget", systemImage: "trash")
                    }
                }
                .accessibilityIdentifier("connect.saved.\(host.id.uuidString)")
            }
            ListRow(title: "Add host", systemImage: "plus.circle") {
                Haptics.selection()
                showAddForm = true
            }
            .accessibilityIdentifier("connect.addHost")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: min(60 * CGFloat(hosts.count + 1) + 8, 380))
        .padding(.horizontal, Space.lg)
    }

    private func renameSheet(_ target: HostSwitchEntry) -> some View {
        VStack(spacing: 16) {
            SheetHeader(title: "Rename host", close: { renameTarget = nil })
            RowGroup {
                TextField("Label", text: $renameText)
                    .font(.paseo(.body))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit { saveRename(target) }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .accessibilityIdentifier("connect.rename.field")
            }
            Button {
                saveRename(target)
            } label: {
                Text("Save")
            }
            .buttonStyle(.paseoPrimary())
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, Space.lg)
            .accessibilityIdentifier("connect.rename.save")
            Spacer(minLength: 0)
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }

    private func saveRename(_ target: HostSwitchEntry) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Haptics.selection()
        onRenameSaved(target.id, trimmed)
        renameTarget = nil
    }

    // MARK: Direct form

    private var directForm: some View {
        VStack(spacing: 12) {
            if !hosts.isEmpty {
                HStack {
                    Button {
                        Haptics.selection()
                        showAddForm = false
                    } label: {
                        Label("Saved hosts", systemImage: "chevron.left")
                            .font(.paseo(.callout, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("connect.backToHosts")
                    Spacer()
                }
            }
            RowGroup {
                field(
                    "Host", text: $host, prompt: "example.com or 192.0.2.10",
                    symbol: "desktopcomputer", keyboard: .URL, contentType: .URL)
                RowDivider()
                field("Port", text: $port, prompt: "6767", symbol: "number", keyboard: .numberPad)
                if let portError {
                    errorCaption(portError)
                }
                if let hostError {
                    errorCaption(hostError)
                }
                RowDivider()
                secureField("Password", text: $password, prompt: "Host password")
                RowDivider()
                Toggle(isOn: $useTLS) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use TLS (wss)")
                            .font(.paseo(.body))
                        Text("For daemons behind a TLS terminator (Caddy, nginx).")
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                .tint(Palette.toggleTint)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityIdentifier("connect.tls")
                RowDivider()
                Button {
                    Haptics.selection()
                    withAnimation(Motion.disclosure.animation) { showAdvanced.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        fieldSymbol("chevron.down.chevron.up")
                        Text("Advanced")
                            .font(.paseo(.body))
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.glyph(.small, weight: .semibold))
                            .foregroundStyle(Palette.secondaryInk)
                            .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("connect.advanced")
                if showAdvanced {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 2) {
                        TextField(
                            "", text: $connectionURI,
                            prompt: Text("wss://host:6767/ws").foregroundStyle(Palette.captionInk)
                        )
                        .font(.paseo(.code))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("connect.uri")
                        Text(uriError ?? "Overrides host, port and the TLS switch while filled.")
                            .font(.paseo(.caption))
                            .foregroundStyle(uriError == nil ? Palette.secondaryInk : Palette.failureInk)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func errorCaption(_ message: String) -> some View {
        Text(message)
            .font(.paseo(.caption))
            .foregroundStyle(Palette.failureInk)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
    }

    /// The one primary action: `PrimaryButtonStyle` keeps its width and shows the spinner while
    /// connecting (PLAN §RH, async actions).
    private var connectButton: some View {
        Button(action: onConnect) {
            Text(
                connecting
                    ? "Connecting…" : (status.isFailed ? "Retry" : "Connect"))
        }
        .buttonStyle(.paseoPrimary(isWorking: connecting))
        .disabled(!canConnect)
        .padding(.horizontal, Space.lg)
        .accessibilityIdentifier("connect.submit")
    }

    private func field(
        _ title: String, text: Binding<String>, prompt: String, symbol: String,
        keyboard: UIKeyboardType = .default, contentType: UITextContentType? = nil
    ) -> some View {
        HStack(spacing: 12) {
            fieldSymbol(symbol)
            VStack(alignment: .leading, spacing: 2) {
                fieldTitle(title)
                TextField(
                    "", text: text,
                    prompt: Text(prompt).foregroundStyle(Palette.captionInk)
                )
                .font(.paseo(.body))
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func secureField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 12) {
            fieldSymbol("lock")
            VStack(alignment: .leading, spacing: 2) {
                fieldTitle(title)
                SecureField(
                    "", text: text,
                    prompt: Text(prompt).foregroundStyle(Palette.captionInk)
                )
                .font(.paseo(.body))
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit(onConnect)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func fieldSymbol(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.glyph(.regular, weight: .light))
            .foregroundStyle(Palette.tertiaryInk)
            .frame(width: 23)
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(.paseo(.caption)).foregroundStyle(Palette.secondaryInk)
    }
}

extension ConnectView.Status {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
#endif
