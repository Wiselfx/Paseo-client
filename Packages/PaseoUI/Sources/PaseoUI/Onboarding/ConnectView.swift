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
    /// Bumped when a rename is saved; drives the confirmation haptic.
    @State private var renameSaveCount = 0
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
            // The whole page scrolls, never a box inside it: one host must not need a scroll, and
            // many hosts must not be trapped in a fixed-height frame (E2 §4).
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 6) {
                            Text("Paseo").font(.paseo(.largeTitle))
                            Text("Connect to your host")
                                .font(.paseo(.callout))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        Group {
                            if showAddForm || hosts.isEmpty {
                                ConnectDirectForm(
                                    host: $host, port: $port, password: $password, useTLS: $useTLS,
                                    connectionURI: $connectionURI, showAdvanced: $showAdvanced,
                                    showsBackButton: !hosts.isEmpty,
                                    portError: portError, hostError: hostError, uriError: uriError,
                                    canConnect: canConnect,
                                    onBack: { showAddForm = false }, onConnect: onConnect)
                            } else {
                                SavedHostsCard(
                                    hosts: hosts, connecting: connecting,
                                    onConnect: onConnectSaved,
                                    onRename: { host in
                                        renameText = host.label
                                        renameTarget = host
                                    },
                                    onForget: { forgetTarget = $0 },
                                    onAddHost: { showAddForm = true })
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
                        if showAddForm || hosts.isEmpty {
                            ConnectSubmitButton(
                                status: status, canConnect: canConnect, action: onConnect)
                        }
                        Spacer(minLength: 24)
                        Text(
                            "Use your machine's LAN or Tailscale address. Set a password with `paseo daemon set-password`."
                        )
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.captionInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 12)
                    }
                    .padding(.top, 12)
                    // Fits: the spacer above pins the hint to the bottom. Doesn't fit: the page
                    // grows and scrolls as one (`.scrollBounceBehavior(.basedOnSize)`).
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.ink)
        .onChange(of: status) { _, new in
            // A failed connect lands on the form with that host preselected and Retry in reach.
            if case .failed = new {
                showAddForm = true
            }
        }
        .paseoFeedback(.failure, trigger: status) { _, new in
            if case .failed = new { return true }
            return false
        }
        .paseoFeedback(.light, trigger: renameSaveCount)
        .sheet(item: $renameTarget) { target in
            RenameHostSheet(
                text: $renameText, onSave: { saveRename(target) },
                onClose: { renameTarget = nil })
        }
        .confirmationDialog(
            "Forget \(forgetTarget?.label ?? "this host")?",
            item: $forgetTarget,
            titleVisibility: .visible
        ) { _ in
            Button("Forget host", role: .destructive) {
                if let id = forgetTarget?.id { onForgetSaved(id) }
                forgetTarget = nil
            }
            Button("Cancel", role: .cancel) { forgetTarget = nil }
        } message: { _ in
            Text("The password stored on this device for this host is removed too. The host itself isn't changed.")
        }
    }

    private func saveRename(_ target: HostSwitchEntry) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onRenameSaved(target.id, trimmed)
        renameSaveCount += 1
        renameTarget = nil
    }
}

extension ConnectView.Status {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
#endif
